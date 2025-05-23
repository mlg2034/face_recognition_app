import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:realtime_face_recognition/src/services/emergency_image_converter.dart';
import 'package:realtime_face_recognition/src/services/face_detector_utils.dart';
import 'package:realtime_face_recognition/src/services/image_service.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:realtime_face_recognition/src/services/recognizer.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

class LocalEmergencyConverter {
  static img.Image convertToGrayscale(CameraImage cameraImage) {
    img.Image image = img.Image(width: cameraImage.width, height: cameraImage.height);
    
    for (int y = 0; y < cameraImage.height; y++) {
      for (int x = 0; x < cameraImage.width; x++) {
        final int index = y * cameraImage.width + x;
        if (index < cameraImage.planes[0].bytes.length) {
          final int value = cameraImage.planes[0].bytes[index];
          image.setPixelRgb(x, y, value, value, value);
        }
      }
    }
    
    return image;
  }
  
  static img.Image createDummyFace(int width, int height) {
    final img.Image result = img.Image(width: width, height: height);
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int value = ((x * 255) ~/ width + (y * 255) ~/ height) ~/ 2;
        result.setPixelRgb(x, y, value, value, value);
      }
    }
    
    return result;
  }
}

// Add missing functions from ImageService
extension ImageProcessing on ImageService {
  static img.Image normalizeIllumination(img.Image image) {
    final result = img.Image(width: image.width, height: image.height);
    
    // Calculate mean luminance
    double totalLuminance = 0;
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        totalLuminance += pixel.r;
      }
    }
    double meanLuminance = totalLuminance / (image.width * image.height);
    
    // Apply normalization
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        int newValue = (pixel.r - meanLuminance + 128).round().clamp(0, 255);
        result.setPixelRgb(x, y, newValue, newValue, newValue);
      }
    }
    
    return result;
  }
  
  static img.Image adjustBrightnessContrast(img.Image image, 
      {double brightness = 0, double contrast = 1.0}) {
    final result = img.Image(width: image.width, height: image.height);
    
    // Apply brightness and contrast adjustment
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        double value = pixel.r.toDouble();
        
        // Apply brightness adjustment
        value += brightness;
        
        // Apply contrast adjustment
        value = ((value - 128) * contrast) + 128;
        
        // Clamp to valid range
        int newValue = value.round().clamp(0, 255);
        result.setPixelRgb(x, y, newValue, newValue, newValue);
      }
    }
    
    return result;
  }
}

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
      minFaceSize: 0.1,  // Reduced from 0.15 for better frontal detection
    );
    faceDetector = FaceDetector(options: options);
    recognizer = Recognizer();
  }
  
  Future<void> initialize() async {
    await recognizer.initDB();
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
        image = LocalEmergencyConverter.convertToGrayscale(frame);
      } else {
        try {
          image = Platform.isIOS 
              ? await ImageService.convertBGRA8888ToImage(frame) 
              : await ImageService.convertNV21(frame);
        } catch (e) {
          print('Normal conversion failed, switching to emergency converter: $e');
          _useEmergencyConverter = true;
          image = LocalEmergencyConverter.convertToGrayscale(frame);
        }
      }
      
      if (image == null) {
        print('Image conversion returned null, using emergency converter');
        image = LocalEmergencyConverter.convertToGrayscale(frame);
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
            Recognition recognition = Recognition(
              guidanceMessage, 
              face.boundingBox, 
              [], 
              1.0
            );
            recognition.quality = qualityScore;
            recognitions.add(recognition);
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
            croppedFace = LocalEmergencyConverter.createDummyFace(112, 112);
          }
          
          img.Image enhancedFace = ImageService.enhanceImage(croppedFace);
          
          Recognition recognition = recognizer.recognize(enhancedFace, face.boundingBox);
          
          // Add quality score to recognition
          recognition.quality = qualityScore;
          
          // Improved confidence calculation
          double confidence = (1 - recognition.distance) * 100;
          confidence = confidence.clamp(0, 100);
          
          // Use consistent threshold for unknown faces (matching recognizer.dart)
          if (recognition.distance > 0.15) {  // Changed from 0.6 to 0.15 to match RECOGNITION_THRESHOLD
            recognition.label = "Unknown";
          }
          // Note: Don't modify label if it's already properly set by recognizer
          
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
    // Much more lenient face quality check for frontal faces
    
    // Check if face landmarks are detected (very lenient)
    bool hasLandmarks = face.landmarks.length >= 1;  // Was checking for non-empty
    
    // Much more lenient face angles (roll, pitch, yaw)
    bool goodAngles = true;
    if (face.headEulerAngleY != null && face.headEulerAngleZ != null && face.headEulerAngleX != null) {
      // Much more lenient angle checks for frontal faces
      bool goodYaw = face.headEulerAngleY!.abs() < 45;   // Was 15
      bool goodRoll = face.headEulerAngleZ!.abs() < 45;  // Was 15
      bool goodPitch = face.headEulerAngleX!.abs() < 45; // Was 15
      
      goodAngles = goodYaw && goodRoll && goodPitch;
      
      // Debug logging for angles
      print('🔄 Head Angles: Yaw: ${face.headEulerAngleY!.toStringAsFixed(1)}°, Roll: ${face.headEulerAngleZ!.toStringAsFixed(1)}°, Pitch: ${face.headEulerAngleX!.toStringAsFixed(1)}°');
    }
    
    // More lenient eye requirements
    bool eyesOpen = true;
    if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
      eyesOpen = (face.leftEyeOpenProbability! > 0.3) && (face.rightEyeOpenProbability! > 0.3);  // Was 0.7
      print('👀 Eyes: Left: ${face.leftEyeOpenProbability!.toStringAsFixed(2)}, Right: ${face.rightEyeOpenProbability!.toStringAsFixed(2)}');
    }
    
    // More lenient smiling check
    bool notSmiling = true;
    if (face.smilingProbability != null) {
      notSmiling = face.smilingProbability! < 0.9; // Was 0.7 - very lenient now
      print('😊 Smile: ${face.smilingProbability!.toStringAsFixed(2)}');
    }
    
    // More lenient face size check
    bool goodSize = face.boundingBox.width > 50 && face.boundingBox.height > 50;  // Was 100
    print('📏 Face Size: ${face.boundingBox.width.toInt()}x${face.boundingBox.height.toInt()}');
    
    // Debug overall result
    bool result = hasLandmarks && goodAngles && eyesOpen && notSmiling && goodSize;
    print('✅ Face Quality: ${result ? "GOOD" : "BAD"} (landmarks: $hasLandmarks, angles: $goodAngles, eyes: $eyesOpen, expression: $notSmiling, size: $goodSize)');
    
    return result;
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
  
  void registerFaceEmbeddings(String name, List<double> embeddings) {
    recognizer.registerFaceInDB(name, embeddings);
  }
  
  String getAccuracyReport() {
    final RecognitionLogger logger = RecognitionLogger();
    final metrics = logger.getAccuracyMetrics();
    
    double accuracy = metrics['accuracy'] ?? 0.0;
    double far = metrics['far'] ?? 0.0;
    double frr = metrics['frr'] ?? 0.0;
    int samples = metrics['samples'] ?? 0;
    
    if (samples == 0) {
      return "No recognition data available yet";
    }
    
    return "Accuracy: ${(accuracy * 100).toStringAsFixed(1)}% | FAR: ${(far * 100).toStringAsFixed(1)}% | FRR: ${(frr * 100).toStringAsFixed(1)}% | Samples: $samples";
  }
  
  void showFaceRecognitionStats() {
    final RecognitionLogger logger = RecognitionLogger();
    final metrics = logger.getAccuracyMetrics();
    
    print('\n----------------------------------------');
    print('📊 FACE RECOGNITION STATISTICS 📊');
    print('----------------------------------------');
    print('Accuracy: ${(metrics['accuracy'] * 100).toStringAsFixed(2)}%');
    print('Precision: ${(metrics['precision'] * 100).toStringAsFixed(2)}%');
    print('Recall: ${(metrics['recall'] * 100).toStringAsFixed(2)}%');
    print('F1 Score: ${(metrics['f1_score'] * 100).toStringAsFixed(2)}%');
    print('False Accept Rate: ${(metrics['far'] * 100).toStringAsFixed(2)}%');
    print('False Reject Rate: ${(metrics['frr'] * 100).toStringAsFixed(2)}%');
    print('Total Samples: ${metrics['samples']}');
    print('Current Threshold: ${metrics['threshold']}');
    print('----------------------------------------\n');
  }
  
  Future<String> exportROCData() async {
    try {
      final RecognitionLogger logger = RecognitionLogger();
      final csvData = await logger.exportROCDataAsCSV();
      
      // Save to file
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${appDocDir.path}/roc_data_$timestamp.csv');
      
      await file.writeAsString(csvData);
      
      print('ROC data exported to: ${file.path}');
      return file.path;
    } catch (e) {
      print('Error exporting ROC data: $e');
      return '';
    }
  }
  
  Future<String> generateMetricsLog() async {
    try {
      final RecognitionLogger logger = RecognitionLogger();
      final metrics = logger.getAccuracyMetrics();
      
      // Format metrics as JSON with nice indentation
      String metricsJson = '''
{
  "accuracy": ${metrics['accuracy']},
  "precision": ${metrics['precision']},
  "recall": ${metrics['recall']},
  "f1_score": ${metrics['f1_score']},
  "false_accept_rate": ${metrics['far']},
  "false_reject_rate": ${metrics['frr']},
  "samples": ${metrics['samples']},
  "threshold": ${metrics['threshold']},
  "true_positives": ${metrics['truePositives']},
  "false_positives": ${metrics['falsePositives']},
  "true_negatives": ${metrics['trueNegatives']},
  "false_negatives": ${metrics['falseNegatives']},
  "timestamp": "${DateTime.now().toIso8601String()}"
}
''';
      
      // Save to file
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${appDocDir.path}/face_metrics_$timestamp.json');
      
      await file.writeAsString(metricsJson);
      
      print('Metrics log saved to: ${file.path}');
      return file.path;
    } catch (e) {
      print('Error generating metrics log: $e');
      return '';
    }
  }
}

double max(double a, double b) {
  return a > b ? a : b;
}

double min(double a, double b) {
  return a < b ? a : b;
} 