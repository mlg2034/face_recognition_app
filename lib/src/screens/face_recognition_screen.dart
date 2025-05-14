import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/core/app/ui/app_fonts.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';
import 'package:realtime_face_recognition/src/screens/user_list_screen.dart';


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
          
          // Overlay with title and information
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
                      'Биометрия с проверкой живости', 
                      style: AppFonts.w600s24,
                    ),
                  ),
                  
                  const SizedBox(height: 12),
                  
                  // Instructions container
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Для регистрации нажмите "Регистрация" и пройдите проверку живости', 
                      style: AppFonts.w400s16,
                      textAlign: TextAlign.center,
                    ),
                  ),

                  const Spacer(),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const UserListScreen()),
          );
        },
        tooltip: 'Список пользователей',
        child: const Icon(Icons.people),
      ),
    );
  }
}
