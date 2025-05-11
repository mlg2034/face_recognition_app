import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/src/services/emergency_image_converter.dart';
import 'package:realtime_face_recognition/src/services/face_detector_utils.dart';
import 'package:realtime_face_recognition/src/services/image_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:realtime_face_recognition/src/services/recognizer.dart';

class FaceDetectionService {
  late FaceDetector faceDetector;
  late Recognizer recognizer;
  
  bool _useEmergencyConverter = false;
  
  FaceDetectionService() {
    var options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.accurate,
      enableLandmarks: true,
      enableContours: true,
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,
    );
    faceDetector = FaceDetector(options: options);
    recognizer = Recognizer();
  }
  
  Future<void> initialize() async {
    await recognizer.loadRegisteredFaces();
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
    
    img.Image? image;
    try {
      if (_useEmergencyConverter) {
        print('Using emergency image converter');
        image = EmergencyImageConverter.convertToGrayscale(frame);
      } else {
        try {
          image = Platform.isIOS 
              ? await ImageService.convertBGRA8888ToImage(frame) 
              : await ImageService.convertNV21(frame);
        } catch (e) {
          print('Normal conversion failed, switching to emergency converter: $e');
          _useEmergencyConverter = true;
          image = EmergencyImageConverter.convertToGrayscale(frame);
        }
      }
      
      if (image == null) {
        print('Image conversion returned null, using emergency converter');
        image = EmergencyImageConverter.convertToGrayscale(frame);
      }
      
      image = img.copyRotate(image!,
          angle: cameraDirection == CameraLensDirection.front ? 270 : 90);
      
      Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      for (Face face in faces) {
        try {
          // Calculate face quality score
          double qualityScore = FaceDetectorUtils.calculateFaceQualityScore(face, imageSize);
          
          // Apply stricter face quality checks using the utility class
          if (!FaceDetectorUtils.isFaceSuitableForRecognition(face, imageSize)) {
            // Add a recognition with guidance message for feedback
            String guidanceMessage = FaceDetectorUtils.getFaceAlignmentGuidance(face);
            recognitions.add(Recognition(
              guidanceMessage, 
              face.boundingBox, 
              [], 
              1.0,
              qualityScore: qualityScore
            ));
            continue;
          }
          
          // Get expanded face rectangle with padding using utility
          Rect paddedRect = FaceDetectorUtils.getExpandedFaceRect(face, imageSize);
          
          // Add safety checks for crop operation
          if (paddedRect.left < 0 || paddedRect.top < 0 || 
              paddedRect.right > image.width || paddedRect.bottom > image.height ||
              paddedRect.width <= 0 || paddedRect.height <= 0) {
            print('Warning: Invalid face crop rectangle');
            continue;
          }
          
          // Safely crop the face
          img.Image croppedFace;
          try {
            croppedFace = img.copyCrop(
              image, 
              x: paddedRect.left.toInt(),
              y: paddedRect.top.toInt(),
              width: paddedRect.width.toInt(),
              height: paddedRect.height.toInt()
            );
          } catch (e) {
            print('Error cropping face, using dummy face: $e');
            croppedFace = EmergencyImageConverter.createDummyFace(112, 112);
          }
          
          img.Image enhancedFace = ImageService.enhanceImage(croppedFace);
          
          Recognition recognition = recognizer.recognize(enhancedFace, face.boundingBox);
          
          // Add quality score to recognition
          recognition.qualityScore = qualityScore;
          
          // Improved confidence calculation
          double confidence = (1 - recognition.distance) * 100;
          confidence = confidence.clamp(0, 100);
          
          // More strict threshold for unknown faces
          if (recognition.distance > 0.6) {
            recognition.name = "Unknown";
          } else {
            recognition.name = "${recognition.name} (${confidence.toStringAsFixed(1)}%)";
          }
          
          recognitions.add(recognition);
        } catch (e) {
          print('Error processing face: $e');
          continue;
        }
      }
    } catch (e) {
      print('Error in processRecognitions: $e');
      _useEmergencyConverter = true; // Switch to emergency converter for future frames
    }
    
    return recognitions;
  }
  
  bool isFaceQualityGood(Face face) {
    // More comprehensive face quality check
    
    // Check if face landmarks are detected
    bool hasLandmarks = face.landmarks.isNotEmpty;
    
    // Check face angles (roll, pitch, yaw)
    bool goodAngles = true;
    if (face.headEulerAngleY != null && face.headEulerAngleZ != null && face.headEulerAngleX != null) {
      // Check for yaw (left-right rotation)
      bool goodYaw = face.headEulerAngleY!.abs() < 15;
      
      // Check for roll (tilt)
      bool goodRoll = face.headEulerAngleZ!.abs() < 15;
      
      // Check for pitch (up-down rotation)
      bool goodPitch = face.headEulerAngleX!.abs() < 15;
      
      goodAngles = goodYaw && goodRoll && goodPitch;
    }
    
    // Check if eyes are open (if classification is available)
    bool eyesOpen = true;
    if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
      eyesOpen = (face.leftEyeOpenProbability! > 0.7) && (face.rightEyeOpenProbability! > 0.7);
    }
    
    // Check if smiling (optional, can be removed if not needed)
    bool notSmiling = true;
    if (face.smilingProbability != null) {
      notSmiling = face.smilingProbability! < 0.7; // Prefer neutral expression
    }
    
    // Check face size (bigger faces have more details)
    bool goodSize = face.boundingBox.width > 100 && face.boundingBox.height > 100;
    
    // Return combined quality check
    return hasLandmarks && goodAngles && eyesOpen && notSmiling && goodSize;
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

double max(double a, double b) {
  return a > b ? a : b;
}

double min(double a, double b) {
  return a < b ? a : b;
} 