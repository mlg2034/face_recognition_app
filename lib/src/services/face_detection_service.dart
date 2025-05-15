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
  int _consecutiveErrors = 0;
  static const int MAX_CONSECUTIVE_ERRORS = 5;
  
  // Cache the last known face
  Recognition? _lastKnownFace;
  int _framesSinceLastRecognition = 0;
  static const int RECOGNITION_FREQUENCY = 10; // Only process every N frames for known faces
  
  FaceDetectionService() {
    var options = FaceDetectorOptions(
      performanceMode: FaceDetectorMode.fast,  // Use fast mode by default
      enableLandmarks: true,
      enableContours: false,  // Disable contours for performance
      enableClassification: true,
      enableTracking: true,
      minFaceSize: 0.15,
    );
    faceDetector = FaceDetector(options: options);
    recognizer = Recognizer();
  }
  
  Future<void> initialize() async {
    try {
      // Wait for registered faces to be loaded
      await recognizer.loadRegisteredFaces();
      print('Face detection service initialized successfully');
    } catch (e) {
      print('Error initializing face detection service: $e');
      // Rethrow so the caller knows initialization failed
      rethrow;
    }
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
    
    if (faces.isEmpty) {
      _framesSinceLastRecognition = 0;
      _lastKnownFace = null;
      return recognitions;
    }
    
    // Increment frame counter
    _framesSinceLastRecognition++;
    
    // Only reuse _lastKnownFace if we're very confident in the recognition
    if (_lastKnownFace != null && 
        _lastKnownFace!.distance < 0.3 && // Only reuse high confidence matches
        _framesSinceLastRecognition < RECOGNITION_FREQUENCY) {
      
      // Make sure the face is in a similar position to avoid misidentification
      Rect currentFaceRect = faces.first.boundingBox;
      Rect lastFaceRect = _lastKnownFace!.location;
      
      // Calculate overlap between current face and last known face
      Rect intersection = Rect.fromLTRB(
        max(currentFaceRect.left, lastFaceRect.left),
        max(currentFaceRect.top, lastFaceRect.top),
        min(currentFaceRect.right, lastFaceRect.right),
        min(currentFaceRect.bottom, lastFaceRect.bottom)
      );
      
      // Only reuse if there's significant overlap
      double overlapArea = intersection.width * intersection.height;
      if (overlapArea <= 0) {
        // No overlap, don't reuse
        _lastKnownFace = null;
      } else {
        double lastFaceArea = lastFaceRect.width * lastFaceRect.height;
        double currentFaceArea = currentFaceRect.width * currentFaceRect.height;
        double overlapRatio = overlapArea / min(lastFaceArea, currentFaceArea);
        
        if (overlapRatio > 0.7) { // 70% overlap required
          // Only update the bounding box and increment recognition count
          Recognition updatedRecognition = Recognition(
            _lastKnownFace!.name,
            faces.first.boundingBox,
            _lastKnownFace!.embeddings,
            _lastKnownFace!.distance,
            qualityScore: _lastKnownFace!.qualityScore
          );
          recognitions.add(updatedRecognition);
          return recognitions;
        } else {
          // Not enough overlap
          _lastKnownFace = null;
        }
      }
    }
    
    // Restart recognition from scratch
    try {
      // Try faster conversion methods first
      img.Image? image;
      if (!_useEmergencyConverter) {
        try {
          image = Platform.isIOS 
              ? await ImageService.convertBGRA8888Fast(frame) 
              : await ImageService.convertYUVToImage(frame);
        } catch (e) {
          print('Ошибка преобразования изображения: $e');
          _consecutiveErrors++;
          if (_consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
            _useEmergencyConverter = true;
          }
          image = EmergencyImageConverter.convertToGrayscale(frame);
        }
      } else {
        image = EmergencyImageConverter.convertToGrayscale(frame);
      }
      
      if (image == null) {
        print('Преобразование изображения вернуло null');
        _useEmergencyConverter = true;
        image = EmergencyImageConverter.convertToGrayscale(frame);
      }
      
      // Rotate image based on camera direction
      int rotationAngle = cameraDirection == CameraLensDirection.front ? 270 : 90;
      image = img.copyRotate(image, angle: rotationAngle);
      
      Size imageSize = Size(image.width.toDouble(), image.height.toDouble());
      
      // Process all faces but prioritize larger ones
      List<Face> sortedFaces = List.from(faces)
        ..sort((a, b) => (b.boundingBox.width * b.boundingBox.height)
                        .compareTo(a.boundingBox.width * a.boundingBox.height));
      
      // Process up to 2 largest faces for better performance
      int processedFaces = 0;
      for (Face face in sortedFaces) {
        if (processedFaces >= 2) break; // Only process max 2 faces for performance
        
        // Face quality check
        if (!FaceDetectorUtils.isFaceSuitableForRecognition(face, imageSize)) {
          String guidanceMessage = FaceDetectorUtils.getFaceAlignmentGuidance(face);
          recognitions.add(Recognition(
            guidanceMessage, 
            face.boundingBox, 
            [], 
            1.0
          ));
          continue;
        }
        
        processedFaces++;
        
        // Get face rectangle with safety checks
        Rect paddedRect = FaceDetectorUtils.getExpandedFaceRect(face, imageSize);
        if (paddedRect.left < 0 || paddedRect.top < 0 || 
            paddedRect.right > image.width || paddedRect.bottom > image.height ||
            paddedRect.width <= 0 || paddedRect.height <= 0) {
          recognitions.add(Recognition(
            "Лицо слишком близко к краю", 
            face.boundingBox, 
            [], 
            1.0
          ));
          continue;
        }
        
        // Crop face
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
          print('Ошибка обрезки лица: $e');
          continue;
        }
        
        // Process recognition
        Recognition recognition = recognizer.recognize(croppedFace, face.boundingBox);
        
        // Calculate quality score based on face attributes
        double qualityScore = 0;
        if (face.headEulerAngleY != null && face.headEulerAngleZ != null) {
          // Better score for frontal faces
          double angleYawPenalty = (face.headEulerAngleY!.abs() / 36.0) * 30; // Up to 30% penalty
          double angleRollPenalty = (face.headEulerAngleZ!.abs() / 36.0) * 20; // Up to 20% penalty
          qualityScore = 100 - angleYawPenalty - angleRollPenalty;
          qualityScore = qualityScore.clamp(0, 100);
        }
        recognition.qualityScore = qualityScore;
        
        // Add confidence level
        double confidence = (1 - recognition.distance) * 100;
        confidence = confidence.clamp(0, 100);
        
        // Debug output
        print('Recognition result: name=${recognition.name}, distance=${recognition.distance.toStringAsFixed(3)}, confidence=${confidence.toStringAsFixed(1)}%');
        
        // Only identify faces with good confidence
        if (recognition.name != "Unknown" && confidence > 65) { // Increased threshold for better accuracy
          recognition.name = "${recognition.name.split(' ')[0]} (${confidence.toStringAsFixed(0)}%)"; // Only show name without previous confidence
          
          // Cache this face for future frames only if it's high confidence
          if (confidence > 80) { // Increased threshold for caching
            _lastKnownFace = recognition;
            _framesSinceLastRecognition = 0;
          }
        } else {
          recognition.name = "Unknown";
          // Don't reset _lastKnownFace immediately to avoid flickering
          if (_framesSinceLastRecognition > RECOGNITION_FREQUENCY * 2) {
            _lastKnownFace = null;
          }
        }
        
        recognitions.add(recognition);
      }
      
      // Reset error counter on success
      _consecutiveErrors = 0;
    } catch (e) {
      print('Ошибка в processRecognitions: $e');
      _consecutiveErrors++;
      if (_consecutiveErrors >= MAX_CONSECUTIVE_ERRORS) {
        _useEmergencyConverter = true;
      }
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
    _lastKnownFace = null; // Reset cache after deletion
  }
  
  void dispose() {
    recognizer.close();
    faceDetector.close();
  }
  
  // Add a method to reset face recognition state
  Future<void> resetRecognitionCache() async {
    _lastKnownFace = null;
    _framesSinceLastRecognition = 0;
    _useEmergencyConverter = false;
    _consecutiveErrors = 0;
    await recognizer.loadRegisteredFaces();
  }
  
  // Method to check if registration database has any faces
  Future<bool> hasRegisteredFaces() async {
    List<String> users = await recognizer.getRegisteredUsers();
    return users.isNotEmpty;
  }
} 

double max(double a, double b) {
  return a > b ? a : b;
}

double min(double a, double b) {
  return a < b ? a : b;
} 