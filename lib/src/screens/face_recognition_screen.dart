import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/core/app/ui/app_fonts.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';

class FaceRecognitionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceRecognitionScreen({super.key, required this.cameras});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  final RecognitionLogger _logger = RecognitionLogger();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera widget takes the full screen
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: CameraWidget(cameras: widget.cameras),
          ),
          
          // Overlay with title
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title at the top
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Пройдите биометрию', 
                      style: AppFonts.w600s24,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
