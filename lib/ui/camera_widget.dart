import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
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

  bool isBusy = false;
  late Size size;
  CameraImage? frame;
  bool register = false;
  List<Recognition> recognitions = [];

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
    }
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
          
          // Status bar with metrics at the top
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
                    ..._buildMetricsWidgets(),
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
          
          // Add control buttons if needed
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
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
                  icon: Icons.bar_chart,
                  label: "Stats",
                  onPressed: _showFaceRecognitionStats,
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
                await faceDetectionService.showFaceRecognitionStats();
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
}
