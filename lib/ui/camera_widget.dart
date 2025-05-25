import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/src/services/camera_service.dart';
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:realtime_face_recognition/src/screens/face_registration_screen.dart';
import 'package:realtime_face_recognition/src/screens/registered_users_screen.dart';
import 'package:realtime_face_recognition/ui/face_detector_painter.dart';
import 'package:realtime_face_recognition/src/services/image_service.dart';
import 'package:realtime_face_recognition/src/services/isolate_utils.dart';
import 'package:realtime_face_recognition/src/services/emergency_image_converter.dart' as emergency;
import 'package:realtime_face_recognition/src/logic/turnstile_bloc/turnstile_bloc.dart';

import '../core/app/ui/ui.dart';

class CameraWidget extends StatefulWidget {
  final List<CameraDescription> cameras;
  final bool isAdminMode;

  const CameraWidget({Key? key, required this.cameras, this.isAdminMode = false}) : super(key: key);

  @override
  _CameraWidgetState createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget>
    with WidgetsBindingObserver {
  late CameraService cameraService;
  late FaceDetectionService faceDetectionService;

  bool isBusy = false;
  late Size size;
  CameraImage? frame;
  bool register = false;
  List<Recognition> recognitions = [];
  
  // Turnstile control variables
  String? lastRecognizedUser;
  DateTime? lastRecognitionTime;
  bool turnstileAccessGranted = false;
  static const Duration RECOGNITION_COOLDOWN = Duration(seconds: 5); // Deprecated - using smart BLoC-based logic now
  static const Duration ACCESS_DISPLAY_DURATION = Duration(seconds: 3); // How long to show access granted

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cameraService = CameraService();
    faceDetectionService = FaceDetectionService();

    initializeServices();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (cameraService.controller == null ||
        !cameraService.controller!.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraService.dispose();
    } else if (state == AppLifecycleState.resumed) {
      initializeServices();
    }
  }

  Future<void> initializeServices() async {
    await cameraService.initialize(widget.cameras);
    await faceDetectionService.initialize();

    if (mounted) {
      setState(() {});
      startImageStream();
    }
  }

  void startImageStream() {
    cameraService.startImageStream((image) {
      if (!isBusy) {
        isBusy = true;
        frame = image;
        processImage();
      }
    });
  }

  Future<void> processImage() async {
    if (frame == null) {
      isBusy = false;
      return;
    }

    InputImage? inputImage =
        cameraService.getInputImage(frame!, widget.cameras);
    if (inputImage == null) {
      isBusy = false;
      return;
    }

    List<Face> faces = await faceDetectionService.detectFaces(inputImage);

    List<Recognition> results = await faceDetectionService.processRecognitions(
        faces, frame!, cameraService.cameraLensDirection);

    if (mounted) {
      setState(() {
        recognitions = results;
        isBusy = false;
      });

      if (register && results.isNotEmpty) {
        navigateToFaceRegistration(results.first);
        register = false;
      }

      _checkForSuccessfulRecognition(results);
    }
  }

  void _checkForSuccessfulRecognition(List<Recognition> results) {
    final now = DateTime.now();
    final turnstileState = context.read<TurnstileBloc>().state;
    
    // Проверяем, что турникет не в процессе обработки запроса
    if (turnstileState is TurnstileLoading) {
      return; // Не отправляем новые запросы пока идет загрузка
    }
    
    // Базовый cooldown для предотвращения слишком частых запросов (сокращен до 2 секунд)
    if (lastRecognitionTime != null && 
        now.difference(lastRecognitionTime!) < const Duration(seconds: 2)) {
      return;
    }
    
    for (Recognition recognition in results) {
      // Check if this is a successful recognition (not Unknown, not guidance messages)
      bool isSuccessfulRecognition = recognition.label != "Unknown" && 
                                    recognition.label != "No faces registered" &&
                                    !recognition.label.contains("Look") &&
                                    !recognition.label.contains("Move") &&
                                    !recognition.label.contains("Quality") &&
                                    recognition.distance <= 0.15; // Use our strict threshold
      
      if (isSuccessfulRecognition) {
        // Extract the name from the label (it might have confidence percentage)
        String recognizedName = recognition.label;
        if (recognizedName.contains('(')) {
          recognizedName = recognizedName.split('(')[0].trim();
        }
        
        print('🎯 SUCCESSFUL RECOGNITION: $recognizedName (distance: ${recognition.distance.toStringAsFixed(4)})');
        print('🔄 Current turnstile state: ${turnstileState.runtimeType}');
        
        // Разрешаем новый вызов турникета только если:
        // 1. Турникет в состоянии Initial (готов к новому запросу)
        // 2. Прошло минимальное время cooldown
        // 3. Это новый пользователь или достаточно времени прошло для того же пользователя
        bool canCallTurnstile = turnstileState is TurnstileInitial &&
                              (lastRecognizedUser != recognizedName || 
                               lastRecognitionTime == null ||
                               now.difference(lastRecognitionTime!) > const Duration(seconds: 3));
        
        if (canCallTurnstile) {
          _callTurnstile(recognizedName);
          lastRecognizedUser = recognizedName;
          lastRecognitionTime = now;
        } else {
          print('⏳ Turnstile call skipped - State: ${turnstileState.runtimeType}, Last user: $lastRecognizedUser, Time since last: ${lastRecognitionTime != null ? now.difference(lastRecognitionTime!).inSeconds : 'N/A'}s');
        }
        
        break; // Only process the first successful recognition
      }
    }
  }
  
  void _callTurnstile(String userName) {
    print('🚪 CALLING TURNSTILE for user: $userName');

    context.read<TurnstileBloc>().add(CallTurnstile());
    
    setState(() {
      turnstileAccessGranted = true;
    });
    
    // Clear access granted status after some time
    Future.delayed(ACCESS_DISPLAY_DURATION, () {
      if (mounted) {
        setState(() {
          turnstileAccessGranted = false;
        });
      }
    });
  }

  void _resetTurnstile() {
    print('🔄 MANUALLY RESETTING TURNSTILE STATE');
    context.read<TurnstileBloc>().add(ResetTurnstile());
    setState(() {
      turnstileAccessGranted = false;
      lastRecognizedUser = null;
      lastRecognitionTime = null;
    });
  }

  void navigateToFaceRegistration(Recognition recognition) async {
    if (frame == null) return;

    await cameraService.stopImageStream();

    img.Image? image;
    try {
      image = emergency.EmergencyImageConverter.convertToGrayscale(frame!);
      
      // Rotate image based on camera direction
      image = img.copyRotate(image,
          angle: cameraService.cameraLensDirection == CameraLensDirection.front
              ? 270
              : 90);
              
      if (recognition.location.left < 0 || 
          recognition.location.top < 0 || 
          recognition.location.right > image.width || 
          recognition.location.bottom > image.height ||
          recognition.location.width <= 0 || 
          recognition.location.height <= 0) {
        print('Warning: Invalid face crop rectangle');
        // Create a dummy face instead
        img.Image croppedFace = emergency.EmergencyImageConverter.createDummyFace(112, 112);
        
        if (!mounted) return;
        
        // Navigate to registration screen with dummy face
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FaceRegistrationScreen(
              croppedFace: croppedFace,
              recognition: recognition,
              faceDetectionService: faceDetectionService,
            ),
          ),
        );
      } else {
        // Safely crop the face
        img.Image croppedFace = img.copyCrop(image,
            x: recognition.location.left.toInt(),
            y: recognition.location.top.toInt(),
            width: recognition.location.width.toInt(),
            height: recognition.location.height.toInt());

        if (!mounted) return;

        // Navigate to registration screen
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => FaceRegistrationScreen(
              croppedFace: croppedFace,
              recognition: recognition,
              faceDetectionService: faceDetectionService,
            ),
          ),
        );
      }
    } catch (e) {
      print('Error in navigateToFaceRegistration: $e');
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing face image. Please try again.'))
        );
      }
    }

    // Resume camera stream
    if (mounted) {
      startImageStream();
    }
  }

  void navigateToRegisteredUsers() async {
    await cameraService.stopImageStream();

    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => RegisteredUsersScreen(
          faceDetectionService: faceDetectionService,
        ),
      ),
    );

    if (mounted) {
      startImageStream();
    }
  }

  Widget buildResult() {
    if (recognitions.isEmpty ||
        cameraService.controller == null ||
        !cameraService.controller!.value.isInitialized) {
      return const Center(
          child: Text('Camera is not initialized', style: AppFonts.w500s20));
    }

    final Size imageSize = Size(
      cameraService.controller!.value.previewSize!.height,
      cameraService.controller!.value.previewSize!.width,
    );

    return CustomPaint(
      painter: FaceDetectorPainter(
          recognitions, imageSize, Size(size.width, size.height)),
      size: Size(size.width, size.height),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraService.dispose();
    faceDetectionService.dispose();
    IsolateUtils.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    size = MediaQuery.of(context).size;
    
    if (cameraService.controller == null || !cameraService.controller!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: Text('Initializing camera...', style: AppFonts.w500s20),
        ),
      );
    }

    final double screenAspectRatio = size.width / size.height;
    final double cameraAspectRatio = cameraService.controller!.value.aspectRatio;
    
    final double previewWidth;
    final double previewHeight;
    
    if (screenAspectRatio < cameraAspectRatio) {
      previewWidth = size.width;
      previewHeight = size.width / cameraAspectRatio;
    } else {
      previewHeight = size.height;
      previewWidth = size.height * cameraAspectRatio;
    }

    return BlocListener<TurnstileBloc, TurnstileState>(
      listener: (context, state) {
        // Handle turnstile state changes
        if (state is TurnstileSuccess) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('🚪 Turnstile opened for $lastRecognizedUser'),
                ],
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
        } else if (state is TurnstileError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.error, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('❌ Turnstile error: ${state.error}'),
                ],
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      child: Container(
        color: Colors.black,
        width: size.width,
        height: size.height,
        child: Stack(
          children: [
            // Camera preview
            Center(
              child: SizedBox(
                width: previewWidth,
                height: previewHeight,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CameraPreview(cameraService.controller!),
                ),
              ),
            ),
            
            // Face detection overlay
            SizedBox(
              width: size.width,
              height: size.height,
              child: buildResult(),
            ),
            
            Positioned(
              top: MediaQuery.of(context).padding.top + 10,
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    if (recognitions.isNotEmpty)
                      // ..._buildMetricsWidgets(),
                    if (recognitions.isEmpty)
                      const Text('No face detected', style: TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ),
            
            // Accuracy metrics bar at the bottom
            Positioned(
              bottom: 80, // Above the control buttons
              left: 10,
              right: 10,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        faceDetectionService.getAccuracyReport(),
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // Turnstile Status Indicator with BLoC
            BlocBuilder<TurnstileBloc, TurnstileState>(
              builder: (context, turnstileState) {
                return Positioned(
                  bottom: 150, // Above control buttons and metrics
                  left: 20,
                  right: 20,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _getTurnstileStatusColor(turnstileState).withOpacity(0.9),
                      borderRadius: BorderRadius.circular(25),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _getTurnstileStatusIcon(turnstileState),
                          color: Colors.white,
                          size: 24,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _getTurnstileStatusText(turnstileState),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            
            // Success Recognition Indicator (temporary)
            if (turnstileAccessGranted)
              Positioned(
                top: MediaQuery.of(context).padding.top + 80,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.9),
                    borderRadius: BorderRadius.circular(25),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Access Granted: $lastRecognizedUser',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Add control buttons if in admin mode
            if (widget.isAdminMode)
              Positioned(
                bottom: 20,
                left: 10,
                right: 10,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildControlButton(
                      icon: Icons.cached,
                      label: "Switch",
                      onPressed: () async {
                        await cameraService.toggleCameraDirection(widget.cameras);
                        if (mounted) {
                          setState(() {});
                          startImageStream();
                        }
                      },
                    ),
                    _buildControlButton(
                      icon: Icons.people,
                      label: "Users",
                      onPressed: navigateToRegisteredUsers,
                    ),
                    _buildControlButton(
                      icon: Icons.face_retouching_natural,
                      label: "Register",
                      onPressed: () {
                        setState(() {
                          register = true;
                        });
                      },
                    ),
                    _buildControlButton(
                      icon: Icons.refresh,
                      label: "Reset\nTurnstile",
                      onPressed: _resetTurnstile,
                    ),
                    _buildControlButton(
                      icon: Icons.bar_chart,
                      label: "Stats",
                      onPressed: _showFaceRecognitionStats,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.7),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: IconButton(
            icon: Icon(icon, color: Colors.white),
            iconSize: 20,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 11),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
  
  // Show face recognition statistics dialog
  Future<void> _showFaceRecognitionStats() async {
    await cameraService.stopImageStream();
    
    if (!mounted) return;
    
    // Show dialog with stats options
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Face Recognition Statistics'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select an option to view or export face recognition metrics:'),
            const SizedBox(height: 20),
            _buildStatsButton(
              icon: Icons.show_chart,
              label: 'Show ROC Curve & Statistics',
              onPressed: () async {
                Navigator.pop(context);
                // Delay slightly to let dialog close
                await Future.delayed(const Duration(milliseconds: 200));
                // Show all statistics including ROC curve
                faceDetectionService.showFaceRecognitionStats();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Statistics displayed in console logs'))
                );
              },
            ),
            const SizedBox(height: 12),
            _buildStatsButton(
              icon: Icons.file_download,
              label: 'Export ROC Data (CSV)',
              onPressed: () async {
                Navigator.pop(context);
                final filePath = await faceDetectionService.exportROCData();
                if (filePath.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('ROC data exported to: $filePath'))
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error exporting ROC data'))
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            _buildStatsButton(
              icon: Icons.text_snippet,
              label: 'Generate Metrics Log',
              onPressed: () async {
                Navigator.pop(context);
                final filePath = await faceDetectionService.generateMetricsLog();
                if (filePath.isNotEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Metrics log saved to: $filePath'))
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error generating metrics log'))
                  );
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    
    // Resume camera stream
    if (mounted) {
      startImageStream();
    }
  }
  
  Widget _buildStatsButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
          ],
        ),
      ),
    );
  }
  
  // Build metrics widgets for the status bar
  List<Widget> _buildMetricsWidgets() {
    if (recognitions.isEmpty) return [];
    
    final recognition = recognitions.first;
    final String name = recognition.label;
    final double distance = recognition.distance;
    final double quality = recognition.quality;
    
    return [
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Name', style: TextStyle(color: Colors.white70, fontSize: 10)),
          Text(
            name.length > 12 ? '${name.substring(0, 10)}...' : name, 
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Distance', style: TextStyle(color: Colors.white70, fontSize: 10)),
          Text(
            distance.toStringAsFixed(3),
            style: TextStyle(
              color: distance < Recognition.DEFAULT_THRESHOLD ? Colors.green : Colors.red,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Quality', style: TextStyle(color: Colors.white70, fontSize: 10)),
          Text(
            quality.toStringAsFixed(1),
            style: TextStyle(
              color: quality > 70 ? Colors.green : Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    ];
  }

  Color _getTurnstileStatusColor(TurnstileState state) {
    switch (state.runtimeType) {
      case TurnstileInitial:
        return Colors.grey;
      case TurnstileLoading:
        return Colors.orange;
      case TurnstileSuccess:
        return Colors.green;
      case TurnstileError:
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  IconData _getTurnstileStatusIcon(TurnstileState state) {
    switch (state.runtimeType) {
      case TurnstileInitial:
        return Icons.door_front_door;
      case TurnstileLoading:
        return Icons.hourglass_empty;
      case TurnstileSuccess:
        return Icons.lock_open;
      case TurnstileError:
        return Icons.error;
      default:
        return Icons.door_front_door;
    }
  }

  String _getTurnstileStatusText(TurnstileState state) {
    switch (state.runtimeType) {
      case TurnstileInitial:
        return 'Turnstile Ready';
      case TurnstileLoading:
        return 'Opening...';
      case TurnstileSuccess:
        return 'Access Granted';
      case TurnstileError:
        final errorState = state as TurnstileError;
        return 'Error: ${errorState.error}';
      default:
        return 'Turnstile Status';
    }
  }
}
