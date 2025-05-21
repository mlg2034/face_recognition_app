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
  late final FaceDetector _faceDetector;
  final RecognitionLogger _logger = RecognitionLogger();
  Recognizer? _recognizer;
  bool _useEmergencyConverter = false;
  
  // Quality threshold for face recognition
  static const double MIN_QUALITY_THRESHOLD = 0.6;
  
  // Store recent face quality scores
  final Map<String, List<double>> _faceQualityHistory = {};
  
  FaceDetectionService() {
    final options = FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      enableContours: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.15,
    );
    
    _faceDetector = FaceDetector(options: options);
    _recognizer = Recognizer();
  }
  
  // Initialize method
  Future<void> initialize() async {
    await _logger.initialize();
    if (_recognizer != null) {
      await _recognizer!.loadModel();
      await _recognizer!.loadRegisteredFaces();
    }
  }
  
  // Method to detect faces
  Future<List<Face>> detectFaces(InputImage inputImage) async {
    try {
      return await _faceDetector.processImage(inputImage);
    } catch (e) {
      print('Error detecting faces: $e');
      return [];
    }
  }
  
  // Process recognitions from detected faces
  Future<List<Recognition>> processRecognitions(
    List<Face> faces, 
    CameraImage frame, 
    CameraLensDirection cameraDirection
  ) async {
    // Default to "Unknown" person ID for non-registration process
    return processImage(frame, cameraDirection, false, "Unknown");
  }
  
  // Get accuracy report as a string
  String getAccuracyReport() {
    final metrics = _logger.getAccuracyMetrics();
    return "Acc: ${(metrics['accuracy'] * 100).toStringAsFixed(1)}% | " +
           "FAR: ${(metrics['far'] * 100).toStringAsFixed(1)}% | " +
           "FRR: ${(metrics['frr'] * 100).toStringAsFixed(1)}%";
  }
  
  // Show face recognition statistics
  Future<void> showFaceRecognitionStats() async {
    final metrics = _logger.getAccuracyMetrics();
    final roc = await _logger.calculateROCCurve();
    
    print('\n=== FACE RECOGNITION STATISTICS ===');
    print('Total samples: ${metrics['samples']}');
    print('Accuracy: ${(metrics['accuracy'] * 100).toStringAsFixed(2)}%');
    print('Precision: ${(metrics['precision'] * 100).toStringAsFixed(2)}%');
    print('Recall: ${(metrics['recall'] * 100).toStringAsFixed(2)}%');
    print('F1 Score: ${(metrics['f1_score'] * 100).toStringAsFixed(2)}%');
    print('False Accept Rate: ${(metrics['far'] * 100).toStringAsFixed(2)}%');
    print('False Reject Rate: ${(metrics['frr'] * 100).toStringAsFixed(2)}%');
    print('Current threshold: ${metrics['threshold']}');
    
    if (roc.isNotEmpty) {
      print('\n=== ROC CURVE DATA (SAMPLE) ===');
      for (int i = 0; i < min(5.0, roc.length.toDouble()); i++) {
        print('Threshold: ${roc[i]['threshold']}, TPR: ${roc[i]['tpr']}, FPR: ${roc[i]['fpr']}');
      }
      print('... (${roc.length} points total)');
    }
    
    return;
  }
  
  // Export ROC data
  Future<String> exportROCData() async {
    try {
      final roc = await _logger.calculateROCCurve();
      if (roc.isEmpty) {
        return '';
      }
      
      // Get documents directory
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/roc_curve_data.csv';
      
      // Create CSV data
      final buffer = StringBuffer();
      buffer.writeln('Threshold,TPR,FPR,FAR,FRR');
      
      for (var point in roc) {
        buffer.writeln('${point['threshold']},${point['tpr']},${point['fpr']},${point['far']},${point['frr']}');
      }
      
      // Write to file
      final file = File(path);
      await file.writeAsString(buffer.toString());
      
      return path;
    } catch (e) {
      print('Error exporting ROC data: $e');
      return '';
    }
  }
  
  // Generate metrics log
  Future<String> generateMetricsLog() async {
    try {
      final metrics = _logger.getAccuracyMetrics();
      
      // Get documents directory
      final directory = await getApplicationDocumentsDirectory();
      final path = '${directory.path}/face_recognition_metrics.txt';
      
      // Create metrics report
      final buffer = StringBuffer();
      buffer.writeln('=== FACE RECOGNITION METRICS ===');
      buffer.writeln('Generated: ${DateTime.now().toIso8601String()}');
      buffer.writeln('');
      buffer.writeln('Total samples: ${metrics['samples']}');
      buffer.writeln('True Positives: ${metrics['truePositives']}');
      buffer.writeln('False Positives: ${metrics['falsePositives']}');
      buffer.writeln('True Negatives: ${metrics['trueNegatives']}');
      buffer.writeln('False Negatives: ${metrics['falseNegatives']}');
      buffer.writeln('');
      buffer.writeln('Accuracy: ${(metrics['accuracy'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('Precision: ${(metrics['precision'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('Recall: ${(metrics['recall'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('F1 Score: ${(metrics['f1_score'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('False Accept Rate: ${(metrics['far'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('False Reject Rate: ${(metrics['frr'] * 100).toStringAsFixed(2)}%');
      buffer.writeln('Current threshold: ${metrics['threshold']}');
      
      // Write to file
      final file = File(path);
      await file.writeAsString(buffer.toString());
      
      return path;
    } catch (e) {
      print('Error generating metrics log: $e');
      return '';
    }
  }
  
  Future<List<Recognition>> processImage(
    CameraImage frame,
    CameraLensDirection cameraDirection,
    bool isRegistering,
    String personId,
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
      
      // Convert to InputImage for ML Kit
      final bytes = img.encodePng(image);
      final inputImage = InputImage.fromBytes(
        bytes: Uint8List.fromList(bytes),
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.width,
        ),
      );
      
      // Process with face detector
      final List<Face> faces = await _faceDetector.processImage(inputImage);
      
      for (Face face in faces) {
        final rect = face.boundingBox;
        final Rect faceRect = Rect.fromLTRB(
          rect.left.toDouble(),
          rect.top.toDouble(),
          rect.right.toDouble(),
          rect.bottom.toDouble(),
        );
        
        // Convert landmarks to Point objects for alignment
        List<Point> landmarks = [];
        if (face.landmarks.containsKey(FaceLandmarkType.leftEye)) {
          final leftEye = face.landmarks[FaceLandmarkType.leftEye]!.position;
          landmarks.add(Point(leftEye.x.toDouble(), leftEye.y.toDouble()));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.rightEye)) {
          final rightEye = face.landmarks[FaceLandmarkType.rightEye]!.position;
          landmarks.add(Point(rightEye.x.toDouble(), rightEye.y.toDouble()));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.noseBase)) {
          final nose = face.landmarks[FaceLandmarkType.noseBase]!.position;
          landmarks.add(Point(nose.x.toDouble(), nose.y.toDouble()));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.leftMouth)) {
          final leftMouth = face.landmarks[FaceLandmarkType.leftMouth]!.position;
          landmarks.add(Point(leftMouth.x.toDouble(), leftMouth.y.toDouble()));
        }
        if (face.landmarks.containsKey(FaceLandmarkType.rightMouth)) {
          final rightMouth = face.landmarks[FaceLandmarkType.rightMouth]!.position;
          landmarks.add(Point(rightMouth.x.toDouble(), rightMouth.y.toDouble()));
        }
        
        // Extract and preprocess the face region
        img.Image faceImage = extractAndPreprocessFace(image!, faceRect, landmarks);
        
        // Assess face quality
        double faceQuality = ImageService.assessImageQuality(faceImage);
        
        // Only proceed with recognition if face quality is acceptable
        if (faceQuality >= MIN_QUALITY_THRESHOLD) {
          // Log face quality
          _updateFaceQualityHistory(personId, faceQuality);
          
          Recognition recognition = _recognizer!.recognize(faceImage, faceRect);
          
          // Add quality score to recognition
          recognition.quality = faceQuality;
          
          // Log recognition in the logger
          if (!isRegistering) {
            await _logger.logRecognition(
              personName: personId,
              matchedName: recognition.label,
              distance: recognition.distance,
              qualityScore: faceQuality,
            );
          }
          
          recognitions.add(recognition);
        } else {
          print('Face quality too low: $faceQuality - skipping recognition');
          Recognition lowQualityRecognition = Recognition("Low Quality", faceRect, [], 1.0);
          lowQualityRecognition.quality = faceQuality;
          recognitions.add(lowQualityRecognition);
        }
      }
    } catch (e) {
      print('Error in processImage: $e');
    }
    
    return recognitions;
  }
  
  img.Image extractAndPreprocessFace(img.Image image, Rect faceRect, List<Point> landmarks) {
    try {
      // If we have enough landmarks, use alignment
      if (landmarks.length >= 2) {
        return ImageService.alignFace(image, landmarks);
      } else {
        // Otherwise just crop without alignment
        return cropAndEnhanceFace(image, faceRect);
      }
    } catch (e) {
      print('Error in extractAndPreprocessFace: $e');
      return cropAndEnhanceFace(image, faceRect);
    }
  }
  
  img.Image cropAndEnhanceFace(img.Image image, Rect faceRect) {
    // Add padding to face rect
    double padding = 0.2;
    int left = (faceRect.left - faceRect.width * padding).round();
    int top = (faceRect.top - faceRect.height * padding).round();
    int width = (faceRect.width * (1 + 2 * padding)).round();
    int height = (faceRect.height * (1 + 2 * padding)).round();
    
    // Ensure coordinates are valid
    left = left < 0 ? 0 : left;
    top = top < 0 ? 0 : top;
    width = left + width > image.width ? image.width - left : width;
    height = top + height > image.height ? image.height - top : height;
    
    if (width <= 0 || height <= 0) {
      return image;
    }
    
    // Crop the face region
    img.Image cropped = img.copyCrop(image, x: left, y: top, width: width, height: height);
    
    // Enhance the cropped face
    return ImageService.enhanceFaceImage(cropped);
  }
  
  // Update face quality history for a person
  void _updateFaceQualityHistory(String personId, double quality) {
    if (!_faceQualityHistory.containsKey(personId)) {
      _faceQualityHistory[personId] = [];
    }
    
    // Add new quality score
    _faceQualityHistory[personId]!.add(quality);
    
    // Keep only the last 10 scores
    if (_faceQualityHistory[personId]!.length > 10) {
      _faceQualityHistory[personId]!.removeAt(0);
    }
  }
  
  // Get average face quality for a person
  double getAverageFaceQuality(String personId) {
    if (!_faceQualityHistory.containsKey(personId) || 
        _faceQualityHistory[personId]!.isEmpty) {
      return 0.0;
    }
    
    double sum = 0.0;
    for (double quality in _faceQualityHistory[personId]!) {
      sum += quality;
    }
    
    return sum / _faceQualityHistory[personId]!.length;
  }
  
  // Get adaptive recognition threshold based on face quality
  double getAdaptiveThreshold(double faceQuality) {
    // Base threshold
    double baseThreshold = Recognizer.RECOGNITION_THRESHOLD;
    
    // Adjust threshold based on quality
    if (faceQuality < 0.65) {
      // More conservative threshold for lower quality
      return baseThreshold - 0.05;
    } else if (faceQuality > 0.85) {
      // More lenient threshold for high quality
      return baseThreshold + 0.05;
    }
    
    return baseThreshold;
  }
  
  Future<void> registerFace(CameraImage frame, CameraLensDirection cameraDirection, String name) async {
    try {
      List<Recognition> recognitions = await processImage(frame, cameraDirection, true, name);
      
      if (recognitions.isNotEmpty) {
        Recognition bestRecognition = recognitions[0];
        
        // Only register if quality is good enough
        if (bestRecognition.quality >= 0.7) {
          await _recognizer?.registerFaceInDB(name, bestRecognition.embeddings);
          print('Face registered successfully with quality: ${bestRecognition.quality}');
        } else {
          print('Face quality too low for registration: ${bestRecognition.quality}');
        }
      } else {
        print('No face detected for registration');
      }
    } catch (e) {
      print('Error registering face: $e');
    }
  }
  
  Future<List<String>> getRegisteredUsers() async {
    return await _recognizer?.getRegisteredUsers() ?? [];
  }
  
  Future<void> deleteUser(String userName) async {
    await _recognizer?.deleteUser(userName);
  }
  
  Future<void> clearAllData() async {
    await _recognizer?.clearAllData();
  }
  
  // Register face using pre-processed embeddings
  Future<void> registerFaceEmbeddings(String name, List<double> embeddings) async {
    try {
      // Quality check is not needed since embeddings are already processed
      await _recognizer?.registerFaceInDB(name, embeddings);
      print('Face registered successfully with pre-processed embeddings');
    } catch (e) {
      print('Error registering face with embeddings: $e');
    }
  }
  
  void dispose() {
    _faceDetector.close();
    _recognizer?.close();
  }
} 

double max(double a, double b) {
  return a > b ? a : b;
}

double min(double a, double b) {
  return a < b ? a : b;
} 