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
          SizedBox(
            width: MediaQuery.of(context).size.width,
            height: MediaQuery.of(context).size.height,
            child: CameraWidget(cameras: cameras),
          ),
        ],
      ),
    );
  }
}
