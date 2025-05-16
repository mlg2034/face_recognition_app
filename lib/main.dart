import 'package:bloc/bloc.dart';
import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/core/app/logic/multi_bloc_wrapper.dart';
import 'package:realtime_face_recognition/firebase_options.dart';
import 'package:realtime_face_recognition/src/screens/face_recognition_screen.dart';
import 'package:realtime_face_recognition/src/services/isolate_utils.dart';

import 'core/app/logic/app_observer.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure Android to use CameraX automatically - package provides this by default
  
  cameras = await availableCameras();

  await IsolateUtils.initialize();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  Bloc.observer = AppObserver();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocWrapper(
      child: MaterialApp(
        title: 'Face Recognition',
        theme: ThemeData(
          primarySwatch: Colors.blue,
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        home: FaceRecognitionScreen(cameras: cameras),
      ),
    );
  }
}
