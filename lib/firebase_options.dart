// File generated by FlutterFire CLI.
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Default [FirebaseOptions] for use with your Firebase apps.
///
/// Example:
/// ```dart
/// import 'firebase_options.dart';
/// // ...
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
          'you can reconfigure this by running the FlutterFire CLI again.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAUlU7BfI5GUsQoY-Mjrq3wCfLmSBjLcoE',
    appId: '1:214963952975:web:cbfc531cf136fdd919793a',
    messagingSenderId: '214963952975',
    projectId: 'face-recognition-diploma',
    authDomain: 'face-recognition-diploma.firebaseapp.com',
    storageBucket: 'face-recognition-diploma.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBXcjKTt6BrcjVo7-yRQr_v9yMssrnetfM',
    appId: '1:214963952975:android:554c667878db15eb19793a',
    messagingSenderId: '214963952975',
    projectId: 'face-recognition-diploma',
    storageBucket: 'face-recognition-diploma.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCNG9O7iMF2cajxI4L02ceOSYeR3s2zl00',
    appId: '1:214963952975:ios:7a145891b55c31bf19793a',
    messagingSenderId: '214963952975',
    projectId: 'face-recognition-diploma',
    storageBucket: 'face-recognition-diploma.firebasestorage.app',
    iosBundleId: 'com.example.realtimeFaceRecognition',
  );
}
