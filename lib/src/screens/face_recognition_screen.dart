import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/core/app/ui/app_fonts.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';


class FaceRecognitionScreen extends StatelessWidget {
  final List<CameraDescription> cameras;

  const FaceRecognitionScreen({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Camera widget takes the full screen
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: CameraWidget(cameras: cameras),
          ),
          
          // Overlay with title and registration button
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

                  const Spacer(),

                  // Registration button at the bottom if needed
                  // (This is optional since we already have a register button in the camera widget)
                  /*
                  ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(30),
                      ),
                    ),
                    child: const Text(
                      'Registration',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                  const SizedBox(height: 20),
                  */
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
