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
