import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:realtime_face_recognition/screens/face_recognition_screen.dart';
import 'package:realtime_face_recognition/ui/camera_widget.dart';
import 'package:realtime_face_recognition/services/isolate_utils.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  cameras = await availableCameras();
  
  await IsolateUtils.initialize();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Recognition',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: FaceRecognitionScreen(cameras: cameras),
    );
  }
}
