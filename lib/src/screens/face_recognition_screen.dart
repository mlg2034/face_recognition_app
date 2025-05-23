import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_face_recognition/core/app/ui/app_fonts.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';
import 'package:realtime_face_recognition/src/logic/turnstile_bloc/turnstile_bloc.dart';

class FaceRecognitionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const FaceRecognitionScreen({super.key, required this.cameras});

  @override
  State<FaceRecognitionScreen> createState() => _FaceRecognitionScreenState();
}

class _FaceRecognitionScreenState extends State<FaceRecognitionScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocProvider(
        create: (context) => TurnstileBloc(),
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: CameraWidget(cameras: widget.cameras),
        ),
      ),
    );
  }
}
