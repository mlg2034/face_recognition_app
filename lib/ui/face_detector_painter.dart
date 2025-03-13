import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/services/recognition.dart';

class FaceDetectorPainter extends CustomPainter {
  FaceDetectorPainter(this.absoluteImageSize, this.faces, this.cameraDirection);

  final Size absoluteImageSize;
  final List<Recognition> faces;
  final CameraLensDirection cameraDirection;

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / absoluteImageSize.width;
    final double scaleY = size.height / absoluteImageSize.height;

    for (Recognition face in faces) {
      // Determine color based on recognition status or quality score
      Color boxColor;
      if (face.name.contains("Unknown")) {
        boxColor = Colors.red;
      } else if (face.name.contains("Turn") || 
                face.name.contains("Align") || 
                face.name.contains("Open") ||
                face.name.contains("Straighten") ||
                face.name.contains("Neutral")) {
        boxColor = Colors.orange;
      } else if (face.qualityScore < 70) {
        boxColor = Colors.yellow;
      } else {
        boxColor = Colors.green;
      }
      
      // Draw face rectangle with dynamic color
      final Paint boxPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0
        ..color = boxColor;

      // Draw face rectangle
      canvas.drawRect(
        Rect.fromLTRB(
          cameraDirection == CameraLensDirection.front
              ? (absoluteImageSize.width - face.location.right) * scaleX
              : face.location.left * scaleX,
          face.location.top * scaleY,
          cameraDirection == CameraLensDirection.front
              ? (absoluteImageSize.width - face.location.left) * scaleX
              : face.location.right * scaleX,
          face.location.bottom * scaleY,
        ),
        boxPaint,
      );
      
      // Draw semi-transparent background for text
      final Paint textBackgroundPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.black.withOpacity(0.5);
      
      // Calculate text position
      final double textX = cameraDirection == CameraLensDirection.front
          ? (absoluteImageSize.width - face.location.right) * scaleX
          : face.location.left * scaleX;
      final double textY = face.location.top * scaleY - 30; // Position above face
      
      // Prepare name text
      TextSpan nameSpan = TextSpan(
        style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        text: face.name
      );
      TextPainter namePainter = TextPainter(
        text: nameSpan,
        textAlign: TextAlign.left,
        textDirection: TextDirection.ltr
      );
      namePainter.layout();
      
      // Draw text background
      canvas.drawRect(
        Rect.fromLTWH(
          textX - 4, 
          textY - 4, 
          namePainter.width + 8, 
          namePainter.height + 8
        ),
        textBackgroundPaint
      );
      
      // Draw name text
      namePainter.paint(canvas, Offset(textX, textY));
      
      // If quality score is available and face is not a guidance message, show it
      if (face.qualityScore > 0 && 
          !face.name.contains("Turn") && 
          !face.name.contains("Open") &&
          !face.name.contains("Straighten") &&
          !face.name.contains("Neutral")) {
        
        // Prepare quality score text
        TextSpan qualitySpan = TextSpan(
          style: TextStyle(
            color: getQualityScoreColor(face.qualityScore), 
            fontSize: 14,
            fontWeight: FontWeight.bold
          ),
          text: "Quality: ${face.qualityScore.toStringAsFixed(0)}%"
        );
        TextPainter qualityPainter = TextPainter(
          text: qualitySpan,
          textAlign: TextAlign.left,
          textDirection: TextDirection.ltr
        );
        qualityPainter.layout();
        
        // Draw quality score below the name
        qualityPainter.paint(
          canvas, 
          Offset(textX, textY + namePainter.height + 2)
        );
      }
    }
  }
  
  // Helper method to get color based on quality score
  Color getQualityScoreColor(double score) {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.lightGreen;
    if (score >= 50) return Colors.yellow;
    if (score >= 30) return Colors.orange;
    return Colors.red;
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return true;
  }
} 