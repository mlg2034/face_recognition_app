import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';
import 'package:realtime_face_recognition/src/logic/turnstile_bloc/turnstile_bloc.dart';

class AdminCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const AdminCameraScreen({super.key, required this.cameras});

  @override
  State<AdminCameraScreen> createState() => _AdminCameraScreenState();
}

class _AdminCameraScreenState extends State<AdminCameraScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Admin Camera - Registration Mode',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.orange,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: BlocProvider(
        create: (context) => TurnstileBloc(),
        child: SizedBox(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          child: CameraWidget(cameras: widget.cameras, isAdminMode: true),
        ),
      ),
    );
  }
} 