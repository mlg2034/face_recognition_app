import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/src/services/camera_service.dart';
import 'package:realtime_face_recognition/src/services/face_detection_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:realtime_face_recognition/src/screens/face_registration_screen.dart';
import 'package:realtime_face_recognition/src/screens/registered_users_screen.dart';
import 'package:realtime_face_recognition/ui/face_detector_painter.dart';
import 'package:realtime_face_recognition/src/services/isolate_utils.dart';
import 'package:realtime_face_recognition/src/services/emergency_image_converter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../core/app/ui/ui.dart';

class CameraWidget extends StatefulWidget {
  final List<CameraDescription> cameras;

  const CameraWidget({Key? key, required this.cameras}) : super(key: key);

  @override
  _CameraWidgetState createState() => _CameraWidgetState();
}

class _CameraWidgetState extends State<CameraWidget>
    with WidgetsBindingObserver {
  late final CameraService cameraService;
  late final FaceDetectionService faceDetectionService;

  bool isBusy = false;
  late Size size;
  CameraImage? frame;
  bool register = false;
  List<Recognition> recognitions = [];
  bool _isFirstFrameReceived = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    cameraService = CameraService();
    faceDetectionService = FaceDetectionService();

    // Enable wakelock to prevent screen from turning off
    WakelockPlus.enable();
    
    // Initialize camera and face detection in parallel
    _parallelInitialization();
  }

  Future<void> _parallelInitialization() async {
    // Show a blank screen while initializing
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Initialize camera and face detection service in parallel
    await Future.wait([
      _initializeCamera(),
      _initializeFaceDetection(),
    ]);
    
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _initializeCamera() async {
    try {
      await safeDisposeCameraResources();
      if (!mounted) return;
      
      // Initialize camera with optimized settings
      await cameraService.initialize(
        widget.cameras,
        resolutionPreset: ResolutionPreset.medium, // Lower resolution for speed
        enableAudio: false, // Disable audio for faster startup
      );
      
      // Lock orientation for better performance
      await cameraService.controller?.lockCaptureOrientation(DeviceOrientation.portraitUp);
      
      // Set lower FPS to improve performance (only on Android)
      if (cameraService.controller != null) {
        try {
          // We use a try-catch because setFpsRange might not be available on all platforms
          // This method is implemented in CameraService
          await cameraService.setFpsRange(15, 15);
        } catch (e) {
          print('Warning: Could not set FPS range: $e');
        }
      }
      
      // Lock focus mode
      await cameraService.controller?.setFocusMode(FocusMode.auto);
      
      // Listen for first frame to start processing stream
      cameraService.controller?.addListener(() {
        if (cameraService.controller!.value.isInitialized && 
            !_isFirstFrameReceived) {
          print('First frame received, starting image processing');
          _isFirstFrameReceived = true;
          startImageStream();
        }
      });
      
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Camera initialization error: $e')),
        );
      }
    }
  }

  Future<void> _initializeFaceDetection() async {
    try {
      await faceDetectionService.initialize();
    } catch (e) {
      print('Face detection service initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading face data: $e')),
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (cameraService.controller == null) {
      return;
    }

    // Handle app lifecycle changes
    if (state == AppLifecycleState.inactive) {
      // Safely dispose camera resources when app goes to background
      safeDisposeCameraResources();
      _isFirstFrameReceived = false;
    } else if (state == AppLifecycleState.resumed) {
      // Reinitialize camera when app comes back to foreground
      _parallelInitialization();
    }
  }

  Future<void> safeDisposeCameraResources() async {
    try {
      if (cameraService.controller != null && 
          cameraService.controller!.value.isInitialized) {
        if (cameraService.controller!.value.isStreamingImages) {
          await cameraService.stopImageStream();
        }
        await Future.delayed(const Duration(milliseconds: 200)); // Give time for stream to stop
      }
    } catch (e) {
      print('Error safely disposing camera: $e');
    }
  }

  void startImageStream() {
    if (cameraService.controller == null || 
        !cameraService.controller!.value.isInitialized) {
      print('Cannot start image stream, camera not initialized');
      return;
    }
    
    try {
      cameraService.startImageStream((image) {
        if (!isBusy) {
          isBusy = true;
          frame = image;
          processImage();
        }
      });
    } catch (e) {
      print('Error starting image stream: $e');
    }
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
        try {
          img.Image croppedFace = img.copyCrop(
            image, 
            x: recognition.location.left.round(), 
            y: recognition.location.top.round(),
            width: recognition.location.width.round(),
            height: recognition.location.height.round()
          );
          croppedFace = img.copyResize(
            croppedFace,
            width: 112,
            height: 112,
            interpolation: img.Interpolation.cubic
          );

          print('Prepared face image for registration: ${croppedFace.width}x${croppedFace.height}');

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
        } catch (e) {
          print('Error cropping face: $e');
          // Create a dummy face as fallback
          img.Image dummyFace = EmergencyImageConverter.createDummyFace(112, 112);
          
          if (!mounted) return;
          
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => FaceRegistrationScreen(
                croppedFace: dummyFace,
                recognition: recognition,
                faceDetectionService: faceDetectionService,
              ),
            ),
          );
        }
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
          child: CupertinoActivityIndicator());
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
                //TODO registered user buttons

                // _buildControlButton(
                //   icon: Icons.people,
                //   label: "Users",
                //   onPressed: navigateToRegisteredUsers,
                // ),
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

  @override
  void dispose() {
    WakelockPlus.disable();
    safeDisposeCameraResources();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}