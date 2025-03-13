import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class EmergencyImageConverter {
  static img.Image convertToGrayscale(CameraImage cameraImage) {
    final img.Image result = img.Image(width: cameraImage.width, height: cameraImage.height);
    
    try {
      final Uint8List yPlane = cameraImage.planes[0].bytes;
      final int yRowStride = cameraImage.planes[0].bytesPerRow;
      
      final int width = cameraImage.width;
      final int height = cameraImage.height;
      
      for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
          final int yIndex = y * yRowStride + x;
          
          if (yIndex < yPlane.length) {
            final int yValue = yPlane[yIndex] & 0xFF;
            result.setPixelRgb(x, y, yValue, yValue, yValue);
          }
        }
      }
      
      print('Converted image safely: ${width}x${height}');
    } catch (e) {
      print('Error in emergency conversion: $e');
    }
    
    return result;
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