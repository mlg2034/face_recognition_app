import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorUtils {
  static bool isFaceSuitableForRecognition(Face face, Size imageSize) {
    final double faceWidthRatio = face.boundingBox.width / imageSize.width;
    final double faceHeightRatio = face.boundingBox.height / imageSize.height;
    
    final bool goodSize = faceWidthRatio > 0.1 && faceHeightRatio > 0.1;
    
    bool goodAngles = true;
    if (face.headEulerAngleY != null && 
        face.headEulerAngleZ != null && 
        face.headEulerAngleX != null) {
      final bool goodYaw = face.headEulerAngleY!.abs() < 35;
      
      final bool goodRoll = face.headEulerAngleZ!.abs() < 35;
      final bool goodPitch = face.headEulerAngleX!.abs() < 35;
      
      goodAngles = goodYaw && goodRoll && goodPitch;
    }
    
    bool eyesOpen = true;
    if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
      eyesOpen = (face.leftEyeOpenProbability! > 0.5) && 
                 (face.rightEyeOpenProbability! > 0.5);
    }
    
    bool neutralExpression = true;
    if (face.smilingProbability != null) {
      neutralExpression = face.smilingProbability! < 0.8;
    }
    
    final bool hasLandmarks = face.landmarks.length >= 1;
    
    print('📊 Face Quality Check:');
    print('   Size: $goodSize (w: ${faceWidthRatio.toStringAsFixed(2)}, h: ${faceHeightRatio.toStringAsFixed(2)})');
    print('   Angles: $goodAngles (yaw: ${face.headEulerAngleY?.toStringAsFixed(1)}°, roll: ${face.headEulerAngleZ?.toStringAsFixed(1)}°, pitch: ${face.headEulerAngleX?.toStringAsFixed(1)}°)');
    print('   Eyes: $eyesOpen (left: ${face.leftEyeOpenProbability?.toStringAsFixed(2)}, right: ${face.rightEyeOpenProbability?.toStringAsFixed(2)})');
    print('   Expression: $neutralExpression (smile: ${face.smilingProbability?.toStringAsFixed(2)})');
    print('   Landmarks: $hasLandmarks (count: ${face.landmarks.length})');
    print('   Overall: ${goodSize && goodAngles && eyesOpen && neutralExpression && hasLandmarks}');
    
    return goodSize && goodAngles && eyesOpen && neutralExpression && hasLandmarks;
  }
  
  static double calculateFaceQualityScore(Face face, Size imageSize) {
    double score = 100.0;
    
    final double faceWidthRatio = face.boundingBox.width / imageSize.width;
    final double faceHeightRatio = face.boundingBox.height / imageSize.height;
    
    if (faceWidthRatio < 0.1) {
      score -= 20 * (0.1 - faceWidthRatio) / 0.1;
    }
    
    if (faceHeightRatio < 0.1) {
      score -= 20 * (0.1 - faceHeightRatio) / 0.1;
    }
    
    if (face.headEulerAngleY != null) {
      score -= min(15, face.headEulerAngleY!.abs() * 0.5);
    }
    
    if (face.headEulerAngleZ != null) {
      score -= min(15, face.headEulerAngleZ!.abs() * 0.5);
    }
    
    if (face.headEulerAngleX != null) {
      score -= min(15, face.headEulerAngleX!.abs() * 0.5);
    }
    
    if (face.leftEyeOpenProbability != null) {
      score -= 10 * (1 - face.leftEyeOpenProbability!);
    }
    
    if (face.rightEyeOpenProbability != null) {
      score -= 10 * (1 - face.rightEyeOpenProbability!);
    }
    
    if (face.smilingProbability != null && face.smilingProbability! > 0.8) {
      score -= 5 * (face.smilingProbability! - 0.8) / 0.2;
    }
    
    return score.clamp(0, 100);
  }
  
  static Rect getExpandedFaceRect(Face face, Size imageSize, {double padding = 0.2}) {
    final Rect faceRect = face.boundingBox;
    
    final double padWidth = faceRect.width * padding;
    final double padHeight = faceRect.height * padding;
    
    return Rect.fromLTRB(
      max(0, faceRect.left - padWidth),
      max(0, faceRect.top - padHeight),
      min(imageSize.width, faceRect.right + padWidth),
      min(imageSize.height, faceRect.bottom + padHeight)
    );
  }
  
  static String getFaceAlignmentGuidance(Face face) {
    if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 30) {
      return face.headEulerAngleY! > 0 
          ? "Turn face slightly left" 
          : "Turn face slightly right";
    }
    
    if (face.headEulerAngleZ != null && face.headEulerAngleZ!.abs() > 30) {
      return "Straighten your head";
    }
    
    if (face.headEulerAngleX != null && face.headEulerAngleX!.abs() > 30) {
      return face.headEulerAngleX! > 0 
          ? "Lower your chin slightly" 
          : "Raise your chin slightly";
    }
    
    if (face.leftEyeOpenProbability != null && 
        face.rightEyeOpenProbability != null &&
        (face.leftEyeOpenProbability! < 0.5 || face.rightEyeOpenProbability! < 0.5)) {
      return "Open your eyes";
    }
    
    if (face.smilingProbability != null && face.smilingProbability! > 0.8) {
      return "Neutral expression please";
    }
    
    return "Perfect - Hold steady";
  }
} 