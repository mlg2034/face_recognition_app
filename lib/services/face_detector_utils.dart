import 'dart:math';
import 'dart:ui';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectorUtils {
  static bool isFaceSuitableForRecognition(Face face, Size imageSize) {
    final double faceWidthRatio = face.boundingBox.width / imageSize.width;
    final double faceHeightRatio = face.boundingBox.height / imageSize.height;
    
    final bool goodSize = faceWidthRatio > 0.15 && faceHeightRatio > 0.15;
    
    bool goodAngles = true;
    if (face.headEulerAngleY != null && 
        face.headEulerAngleZ != null && 
        face.headEulerAngleX != null) {
      final bool goodYaw = face.headEulerAngleY!.abs() < 15;
      
      final bool goodRoll = face.headEulerAngleZ!.abs() < 15;
      final bool goodPitch = face.headEulerAngleX!.abs() < 15;
      
      goodAngles = goodYaw && goodRoll && goodPitch;
    }
    
    bool eyesOpen = true;
    if (face.leftEyeOpenProbability != null && face.rightEyeOpenProbability != null) {
      eyesOpen = (face.leftEyeOpenProbability! > 0.7) && 
                 (face.rightEyeOpenProbability! > 0.7);
    }
    
    bool neutralExpression = true;
    if (face.smilingProbability != null) {
      neutralExpression = face.smilingProbability! < 0.7;
    }
    
    final bool hasLandmarks = face.landmarks.length >= 3;
    
    return goodSize && goodAngles && eyesOpen && neutralExpression && hasLandmarks;
  }
  
  static double calculateFaceQualityScore(Face face, Size imageSize) {
    double score = 100.0;
    
    final double faceWidthRatio = face.boundingBox.width / imageSize.width;
    final double faceHeightRatio = face.boundingBox.height / imageSize.height;
    
    if (faceWidthRatio < 0.15) {
      score -= 30 * (0.15 - faceWidthRatio) / 0.15;
    }
    
    if (faceHeightRatio < 0.15) {
      score -= 30 * (0.15 - faceHeightRatio) / 0.15;
    }
    
    if (face.headEulerAngleY != null) {
      score -= min(30, face.headEulerAngleY!.abs() * 2);
    }
    
    if (face.headEulerAngleZ != null) {
      score -= min(30, face.headEulerAngleZ!.abs() * 2);
    }
    
    if (face.headEulerAngleX != null) {
      score -= min(30, face.headEulerAngleX!.abs() * 2);
    }
    
    if (face.leftEyeOpenProbability != null) {
      score -= 20 * (1 - face.leftEyeOpenProbability!);
    }
    
    if (face.rightEyeOpenProbability != null) {
      score -= 20 * (1 - face.rightEyeOpenProbability!);
    }
    
    if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
      score -= 10 * (face.smilingProbability! - 0.7) / 0.3;
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
    if (face.headEulerAngleY != null && face.headEulerAngleY!.abs() > 15) {
      return face.headEulerAngleY! > 0 
          ? "Turn face left" 
          : "Turn face right";
    }
    
    if (face.headEulerAngleZ != null && face.headEulerAngleZ!.abs() > 15) {
      return face.headEulerAngleZ! > 0 
          ? "Straighten your head" 
          : "Straighten your head";
    }
    
    if (face.headEulerAngleX != null && face.headEulerAngleX!.abs() > 15) {
      return face.headEulerAngleX! > 0 
          ? "Lower your chin" 
          : "Raise your chin";
    }
    
    if (face.leftEyeOpenProbability != null && 
        face.rightEyeOpenProbability != null &&
        (face.leftEyeOpenProbability! < 0.7 || face.rightEyeOpenProbability! < 0.7)) {
      return "Open your eyes";
    }
    
    if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
      return "Neutral expression please";
    }
    
    return "Perfect";
  }
} 