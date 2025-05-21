import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'dart:ui' as ui;

class FaceDetectorPainter extends CustomPainter {
  final List<Recognition> recognitions;
  final Size cameraPreviewSize;
  final Size screenSize;

  FaceDetectorPainter(this.recognitions, this.cameraPreviewSize, this.screenSize);

  @override
  void paint(Canvas canvas, Size size) {
    for (Recognition recognition in recognitions) {
      // Get label and status
      final String label = recognition.label;
      
      // Different colors based on recognition status
      Color boxColor = Colors.green;
      if (label == "Unknown") {
        boxColor = Colors.red;
      } else if (label == "Low Quality") {
        boxColor = Colors.orange;
      } else if (label == "Looking Away") {
        boxColor = Colors.yellow;
      } else if (label == "No faces registered") {
        boxColor = Colors.blue;
      }
      
      // Quality score affects box transparency
      double quality = recognition.quality;
      
      // Draw bounding box
      _drawBoundingBox(canvas, recognition.location, boxColor, quality, label);
      
      // Draw quality bar if quality score is available
      if (quality > 0) {
        _drawQualityBar(canvas, recognition.location, quality);
      }
    }
  }

  void _drawBoundingBox(Canvas canvas, Rect boundingBox, Color color, double quality, String label) {
    // Scale coordinates to screen size
    final Rect scaledRect = Rect.fromLTRB(
      boundingBox.left * screenSize.width / cameraPreviewSize.width,
      boundingBox.top * screenSize.height / cameraPreviewSize.height,
      boundingBox.right * screenSize.width / cameraPreviewSize.width,
      boundingBox.bottom * screenSize.height / cameraPreviewSize.height,
    );
    
    // Draw bounding box
    final paint = Paint()
      ..color = color.withAlpha(100)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    
    canvas.drawRect(scaledRect, paint);
    
    // Draw label
    _drawLabel(canvas, scaledRect, label, color);
    
    // Draw quality score
    if (quality > 0) {
      // Format quality score text
      final qualityText = '${(quality * 100).toStringAsFixed(0)}%';
      final double qualityValue = quality * 100; // Convert to percentage
      
      // Determine text color based on quality value
      Color textColor = Colors.red;
      if (qualityValue >= 90) {
        textColor = Colors.green;
      } else if (qualityValue >= 75) {
        textColor = Colors.lightGreen;
      } else if (qualityValue >= 60) {
        textColor = Colors.orange;
      } else if (qualityValue >= 40) {
        textColor = Colors.deepOrange;
      }
      
      // Draw quality text
      final textSpan = TextSpan(
        text: qualityText,
        style: TextStyle(
          color: textColor,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black45,
        ),
      );
      
      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
      );
      
      textPainter.layout();
      
      // Position for quality text (bottom left of the bounding box)
      final qualityOffset = Offset(
        scaledRect.left,
        scaledRect.bottom + 16, // Position below the label
      );
      
      textPainter.paint(canvas, qualityOffset);
    }
  }

  void _drawLabel(Canvas canvas, Rect boundingBox, String label, Color color) {
    // Format and paint text
    final textSpan = TextSpan(
      text: label,
      style: TextStyle(
        color: color,
        fontSize: 18,
        fontWeight: FontWeight.bold,
        backgroundColor: Colors.black45,
      ),
    );
    
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    
    textPainter.layout();
    
    // Position for label text (top left of bounding box)
    final offset = Offset(
      boundingBox.left,
      boundingBox.top - textPainter.height - 8,
    );
    
    textPainter.paint(canvas, offset);
  }
  
  void _drawQualityBar(Canvas canvas, Rect boundingBox, double quality) {
    // Scale rectangle to screen size
    final Rect scaledRect = Rect.fromLTRB(
      boundingBox.left * screenSize.width / cameraPreviewSize.width,
      boundingBox.top * screenSize.height / cameraPreviewSize.height,
      boundingBox.right * screenSize.width / cameraPreviewSize.width,
      boundingBox.bottom * screenSize.height / cameraPreviewSize.height,
    );
    
    // Quality bar dimensions
    final double barWidth = scaledRect.width;
    final double barHeight = 6.0;
    
    // Background (gray bar)
    final bgPaint = Paint()
      ..color = Colors.grey.withAlpha(180)
      ..style = PaintingStyle.fill;
    
    final bgRect = Rect.fromLTWH(
      scaledRect.left,
      scaledRect.bottom + 4,
      barWidth,
      barHeight,
    );
    
    canvas.drawRect(bgRect, bgPaint);
    
    // Foreground (colored by quality level)
    Color qualityColor = Colors.red;
    if (quality >= 0.9) {
      qualityColor = Colors.green;
    } else if (quality >= 0.75) {
      qualityColor = Colors.lightGreen;
    } else if (quality >= 0.6) {
      qualityColor = Colors.orange;
    } else if (quality >= 0.4) {
      qualityColor = Colors.deepOrange;
    }
    
    final fgPaint = Paint()
      ..color = qualityColor.withAlpha(220)
      ..style = PaintingStyle.fill;
    
    final fgRect = Rect.fromLTWH(
      scaledRect.left,
      scaledRect.bottom + 4,
      barWidth * quality,
      barHeight,
    );
    
    canvas.drawRect(fgRect, fgPaint);
  }

  @override
  bool shouldRepaint(FaceDetectorPainter oldDelegate) {
    return oldDelegate.recognitions != recognitions;
  }
} 