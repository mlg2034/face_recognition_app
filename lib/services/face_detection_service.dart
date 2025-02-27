import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/services/image_service.dart';
import 'package:realtime_face_recognition/services/recognition.dart';
import 'package:realtime_face_recognition/services/recognizer.dart';

class FaceDetectionService {
  late FaceDetector faceDetector;
  late Recognizer recognizer;
  
  FaceDetectionService() {
    var options = FaceDetectorOptions(performanceMode: FaceDetectorMode.accurate);
    faceDetector = FaceDetector(options: options);
    recognizer = Recognizer();
  }
  
  Future<void> initialize() async {
    // Initialize recognizer if needed
  }
  
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    return await faceDetector.processImage(inputImage);
  }
  
  Future<List<Recognition>> processRecognitions(
    List<Face> faces, 
    CameraImage frame, 
    CameraLensDirection cameraDirection
  ) async {
    List<Recognition> recognitions = [];
    
    img.Image? image = Platform.isIOS 
        ? ImageService.convertBGRA8888ToImage(frame) 
        : ImageService.convertNV21(frame);
    
    image = img.copyRotate(image, 
        angle: cameraDirection == CameraLensDirection.front ? 270 : 90);
    
    for (Face face in faces) {
      if (!isFaceQualityGood(face)) {
        continue;
      }
      
      Rect faceRect = face.boundingBox;
      img.Image croppedFace = img.copyCrop(
        image, 
        x: faceRect.left.toInt(),
        y: faceRect.top.toInt(),
        width: faceRect.width.toInt(),
        height: faceRect.height.toInt()
      );
      
      Recognition recognition = recognizer.recognize(croppedFace, faceRect);
      
      double confidence = (1 - recognition.distance * 0.5) * 100;
      confidence = confidence.clamp(0, 100);
      
      if (recognition.distance > 0.7) {
        recognition.name = "Unknown";
      } else {
        recognition.name = "${recognition.name} (${confidence.toStringAsFixed(1)}%)";
      }
      
      recognitions.add(recognition);
    }
    
    return recognitions;
  }
  
  bool isFaceQualityGood(Face face) {
    // Check if face is frontal enough
    if (face.headEulerAngleY != null && face.headEulerAngleZ != null) {
      return face.headEulerAngleY!.abs() < 20 && face.headEulerAngleZ!.abs() < 20;
    }
    return true;
  }
  
  Future<void> registerFace(String name, List<double> embeddings) async {
    recognizer.registerFaceInDB(name, embeddings);
  }
  
  Future<List<String>> getRegisteredUsers() async {
    return await recognizer.getRegisteredUsers();
  }
  
  Future<void> deleteUser(String name) async {
    await recognizer.deleteUser(name);
  }
  
  void dispose() {
    faceDetector.close();
  }
} 