import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/src/services/camera_service.dart';
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/liveness_detection_service.dart';
import 'package:realtime_face_recognition/src/services/liveness_settings_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:realtime_face_recognition/src/screens/face_registration_screen.dart';
import 'package:realtime_face_recognition/src/screens/registered_users_screen.dart';
import 'package:realtime_face_recognition/ui/face_detector_painter.dart';
import 'package:realtime_face_recognition/ui/liveness_check_widget.dart';
import 'package:realtime_face_recognition/src/services/image_service.dart';
import 'package:realtime_face_recognition/src/services/isolate_utils.dart';
import 'package:realtime_face_recognition/src/services/emergency_image_converter.dart';

import '../core/app/ui/ui.dart';

class CameraWidget extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraWidget({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraWidgetState createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget>
    with WidgetsBindingObserver {
  late CameraService cameraService;
  late FaceDetectionService faceDetectionService;
  late LivenessDetectionService livenessDetectionService;

  bool isBusy = false;
  late Size size;
  CameraImage? frame;
  bool register = false;
  bool showLivenessCheck = false;
  bool livenessCheckRequired = true;
  bool livenessVerified = false;
  List<Recognition> recognitions = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cameraService = CameraService();
    faceDetectionService = FaceDetectionService();
    livenessDetectionService = LivenessDetectionService();

    _loadLivenessSettings();
    initializeServices();
  }

  Future<void> _loadLivenessSettings() async {
    final required = await LivenessSettingsService.isLivenessCheckRequired();
    setState(() {
      livenessCheckRequired = required;
      livenessVerified = !required;
    });
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
      _loadLivenessSettings();
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

    // Process liveness check if active
    if (showLivenessCheck && 
        livenessDetectionService.state == LivenessState.inProgress) {
      bool livenessCompleted = livenessDetectionService.processFrame(faces);
      if (livenessCompleted) {
        setState(() {
          livenessVerified = true;
        });
        // Сохраняем успешное прохождение проверки
        await LivenessSettingsService.setLivenessCheckPassed();
      }
    }

    List<Recognition> results = await faceDetectionService.processRecognitions(
        faces, frame!, cameraService.cameraLensDirection);

    if (mounted) {
      setState(() {
        recognitions = results;
        isBusy = false;
      });

      if (register && results.isNotEmpty && (!livenessCheckRequired || livenessVerified)) {
        navigateToFaceRegistration(results.first);
        register = false;
      }
    }
  }

  void startLivenessCheck() {
    setState(() {
      showLivenessCheck = true;
      livenessVerified = false;
    });
    livenessDetectionService.start();
  }

  void cancelLivenessCheck() {
    setState(() {
      showLivenessCheck = false;
    });
    livenessDetectionService.reset();
    _loadLivenessSettings(); // Перезагружаем настройки
  }

  void navigateToFaceRegistration(Recognition recognition) async {
    if (frame == null) return;

    await cameraService.stopImageStream();

    img.Image? image;
    try {
      image = EmergencyImageConverter.convertToGrayscale(frame!);
      
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
        img.Image croppedFace = EmergencyImageConverter.createDummyFace(112, 112);
        
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

    // Reset liveness state
    setState(() {
      showLivenessCheck = false;
      livenessVerified = false;
    });
    livenessDetectionService.reset();

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
          imageSize, recognitions, cameraService.cameraLensDirection),
      size: Size(size.width, size.height),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    cameraService.dispose();
    faceDetectionService.dispose();
    livenessDetectionService.dispose();
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

    // Calculate the size to maintain aspect ratio
    final double screenAspectRatio = size.width / size.height;
    final double cameraAspectRatio = cameraService.controller!.value.aspectRatio;
    
    final double previewWidth;
    final double previewHeight;
    
    if (screenAspectRatio < cameraAspectRatio) {
      // Screen is narrower than camera feed
      previewWidth = size.width;
      previewHeight = size.width / cameraAspectRatio;
    } else {
      // Screen is wider than camera feed
      previewHeight = size.height;
      previewWidth = size.height * cameraAspectRatio;
    }

    return Container(
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
          
          // Liveness check overlay
          if (showLivenessCheck)
            Positioned(
              top: MediaQuery.of(context).padding.top + 20,
              left: 20,
              right: 20,
              child: LivenessCheckWidget(
                livenessService: livenessDetectionService,
                onStart: () {
                  startLivenessCheck();
                },
                onCancel: () {
                  cancelLivenessCheck();
                },
              ),
            ),
          
          // Liveness verified indicator
          if (livenessVerified)
            Positioned(
              top: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'Живость подтверждена',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          
          // Add control buttons
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildControlButton(
                  icon: Icons.cached,
                  label: "Переключить",
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
                  label: "Пользователи",
                  onPressed: navigateToRegisteredUsers,
                ),
                _buildControlButton(
                  icon: Icons.face_retouching_natural,
                  label: "Регистрация",
                  onPressed: () {
                    // Если требуется проверка живости и она еще не пройдена
                    if (livenessCheckRequired && !livenessVerified) {
                      setState(() {
                        showLivenessCheck = true;
                      });
                    } else {
                      setState(() {
                        register = true;
                      });
                    }
                  },
                ),
                _buildControlButton(
                  icon: Icons.security,
                  label: "Проверка",
                  onPressed: () {
                    setState(() {
                      showLivenessCheck = true;
                      livenessVerified = false;
                    });
                    livenessDetectionService.reset();
                  },
                ),
              ],
            ),
          ),
        ],
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
          width: 50,
          height: 50,
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
            iconSize: 24,
            onPressed: onPressed,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ],
    );
  }
}
