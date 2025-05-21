import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:logger/logger.dart';
import 'package:realtime_face_recognition/firebase_options.dart';
import 'package:realtime_face_recognition/src/screens/face_recognition_screen.dart';
import 'package:realtime_face_recognition/src/services/isolate_utils.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

// Global logger instance
final logger = Logger(
  filter: ProductionFilter(),
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: true,
  ),
);

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  logger.i('🔍 Starting Face Recognition App');
  
  cameras = await availableCameras();
  logger.i('📷 Found ${cameras.length} camera(s)');

  // Initialize the face recognition logger
  final recognitionLogger = RecognitionLogger();
  await recognitionLogger.initialize();
  logger.i('📊 Recognition logger initialized');
  
  await IsolateUtils.initialize();
  logger.i('⚡ Isolate utils initialized');
  
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  logger.i('🔥 Firebase initialized');
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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
