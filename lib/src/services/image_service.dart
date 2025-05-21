import 'dart:isolate';
import 'dart:typed_data';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

class Point {
  final double x;
  final double y;
  
  Point(this.x, this.y);
}

class ImageService {
  static var IOS_BYTES_OFFSET = 28;
  
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static SendPort? _sendPort;
  static bool _isolateReady = false;
  
  // Image quality threshold (0-1)
  static const double QUALITY_THRESHOLD = 0.65;
  
  static Future<void> initializeIsolate() async {
    if (_isolateReady) return;
    
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);
    
    _sendPort = await _receivePort!.first;
    _isolateReady = true;
    print('Image processing isolate initialized');
  }
  
  static void _isolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) {
      if (message is _ImageProcessRequest) {
        try {
          final result = _processImageInIsolate(message);
          message.responsePort.send(result);
        } catch (e) {
          print('Error in image processing isolate: $e');
          message.responsePort.send(null);
        }
      }
    });
  }
  
  static img.Image? _processImageInIsolate(_ImageProcessRequest request) {
    try {
      if (request.isAndroid) {
        return _safeConvertNV21(request.cameraImage);
      } else {
        return _safeConvertBGRA8888(request.cameraImage);
      }
    } catch (e) {
      print('Error in isolate image processing: $e');
      return null;
    }
  }
  
  static Future<img.Image?> processImageWithIsolate(CameraImage cameraImage, bool isAndroid) async {
    if (!_isolateReady) {
      await initializeIsolate();
    }
    
    if (_sendPort == null) {
      print('Error: Image processing isolate not ready');
      return null;
    }
    
    try {
      final responsePort = ReceivePort();
      final request = _ImageProcessRequest(
        cameraImage: cameraImage,
        isAndroid: isAndroid,
        responsePort: responsePort.sendPort
      );
      
      _sendPort!.send(request);
      
      final result = await responsePort.first.timeout(
        Duration(seconds: 5),
        onTimeout: () {
          print('Image processing timeout');
          return null;
        }
      );
      
      return result as img.Image?;
    } catch (e) {
      print('Error processing image with isolate: $e');
      return null;
    }
  }
  
  static img.Image _safeConvertNV21(CameraImage image) {
    final img.Image result = img.Image(width: image.width, height: image.height);
    
    try {
      final Uint8List yPlane = image.planes[0].bytes;
      
      // Check if we have a valid second plane for UV data
      if (image.planes.length < 2 || image.planes[1].bytes.isEmpty) {
        // Fallback to grayscale if UV data is not available
        for (int y = 0; y < image.height; y++) {
          for (int x = 0; x < image.width; x++) {
            final int yIndex = y * image.width + x;
            
            if (yIndex < yPlane.length) {
              final int yValue = yPlane[yIndex] & 0xFF;
              result.setPixelRgb(x, y, yValue, yValue, yValue);
            }
          }
        }
        return result;
      }
      
      final Uint8List uvPlane = image.planes[1].bytes;
      
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      final int uvRowStride = image.planes[1].bytesPerRow;
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final int yIndex = y * image.width + x;
          
          // Make sure we don't access invalid indices
          if (yIndex >= yPlane.length) continue;
          
          int yValue = yPlane[yIndex] & 0xFF;
          
          // Default UV values (grayscale)
          int uValue = 128;
          int vValue = 128;
          
          // Try to get actual UV values if available
          final int uvRowIndex = (y ~/ 2) * uvRowStride;
          final int uvColIndex = (x ~/ 2) * uvPixelStride;
          final int uvIndex = uvRowIndex + uvColIndex;
          
          if (uvIndex < uvPlane.length && uvIndex + uvPixelStride < uvPlane.length) {
            uValue = uvPlane[uvIndex] & 0xFF;
            vValue = uvPlane[uvIndex + uvPixelStride] & 0xFF;
          }
          
          // YUV to RGB conversion
          int y1192 = 1192 * (yValue - 16);
          if (y1192 < 0) y1192 = 0;
          
          int r = (y1192 + 1634 * (vValue - 128)) >> 10;
          int g = (y1192 - 833 * (vValue - 128) - 400 * (uValue - 128)) >> 10;
          int b = (y1192 + 2066 * (uValue - 128)) >> 10;
          
          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);
          
          result.setPixelRgb(x, y, r, g, b);
        }
      }
    } catch (e) {
      print('Error in _safeConvertNV21: $e');
    }
    
    return result;
  }
  
  static img.Image _safeConvertBGRA8888(CameraImage image) {
    try {
      final plane = image.planes[0];
      
      final img.Image result = img.Image(width: image.width, height: image.height);
      
      if (plane.bytes.length >= IOS_BYTES_OFFSET + (image.height * plane.bytesPerRow)) {
        try {
    return img.Image.fromBytes(
            width: image.width,
            height: image.height,
      bytes: plane.bytes.buffer,
      rowStride: plane.bytesPerRow,
      bytesOffset: IOS_BYTES_OFFSET,
      order: img.ChannelOrder.bgra,
    );
        } catch (e) {
          print('Error using fromBytes for BGRA: $e');
        }
      }
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final int pixelIndex = IOS_BYTES_OFFSET + y * plane.bytesPerRow + x * 4;
          
          // Check bounds before accessing
          if (pixelIndex + 3 >= plane.bytes.length) continue;
          
          final int b = plane.bytes[pixelIndex] & 0xFF;
          final int g = plane.bytes[pixelIndex + 1] & 0xFF;
          final int r = plane.bytes[pixelIndex + 2] & 0xFF;
          
          result.setPixelRgb(x, y, r, g, b);
        }
      }
      
      return result;
    } catch (e) {
      print('Error in _safeConvertBGRA8888: $e');
      return img.Image(width: image.width, height: image.height);
    }
  }
  
  // Public methods that use the isolate-based processing
  static Future<img.Image?> convertNV21(CameraImage image) async {
    try {
      // First try with isolate
      if (_isolateReady) {
        final result = await processImageWithIsolate(image, true);
        if (result != null) return result;
      }
      
      // Fall back to synchronous method if isolate fails
      return convertNV21Sync(image);
    } catch (e) {
      print('Error in convertNV21: $e');
      // Return a safe fallback
      return img.Image(width: image.width, height: image.height);
    }
  }
  
  static Future<img.Image?> convertBGRA8888ToImage(CameraImage image) async {
    try {
      // First try with isolate
      if (_isolateReady) {
        final result = await processImageWithIsolate(image, false);
        if (result != null) return result;
      }
      
      // Fall back to synchronous method if isolate fails
      return convertBGRA8888ToImageSync(image);
    } catch (e) {
      print('Error in convertBGRA8888ToImage: $e');
      // Return a safe fallback
      return img.Image(width: image.width, height: image.height);
    }
  }
  
  static img.Image convertNV21Sync(CameraImage image) {
    return _safeConvertNV21(image);
  }
  
  static img.Image convertBGRA8888ToImageSync(CameraImage image) {
    return _safeConvertBGRA8888(image);
  }

  // New method to enhance image quality for better face recognition
  static img.Image enhanceImage(img.Image inputImage) {
    try {
    // Step 1: Convert to grayscale for better feature extraction
    img.Image grayscale = img.grayscale(inputImage);
    
    // Step 2: Apply brightness and contrast adjustment
    img.Image adjusted = adjustBrightnessContrast(grayscale);
    
    // Step 3: Apply light normalization to reduce lighting variations
    img.Image normalized = normalizeIllumination(adjusted);
    
    // Step 4: Apply slight gaussian blur to reduce noise (optional)
    img.Image smoothed = img.gaussianBlur(normalized, radius: 1);
    
    // Step 5: Convert back to RGB if needed for the recognition model
    return img.copyResize(smoothed, width: inputImage.width, height: inputImage.height);
    } catch (e) {
      print('Error in enhanceImage: $e');
      return inputImage; // Return original image on error
    }
  }
  
  // Helper method for brightness and contrast adjustment
  static img.Image adjustBrightnessContrast(img.Image image, {int brightness = 0, double contrast = 1.2}) {
    try {
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        
        // Apply brightness and contrast adjustment
        int value = pixel.r.toInt(); // For grayscale, r=g=b
        double adjusted = (value - 128) * contrast + 128 + brightness;
        
        // Manual clamping to avoid type issues
        int finalValue;
        if (adjusted < 0) {
          finalValue = 0;
        } else if (adjusted > 255) {
          finalValue = 255;
        } else {
          finalValue = adjusted.round();
        }
        
        result.setPixelRgb(x, y, finalValue, finalValue, finalValue);
      }
    }
    
    return result;
    } catch (e) {
      print('Error in adjustBrightnessContrast: $e');
      return image; // Return original image on error
    }
  }
  
  // Helper method for illumination normalization
  static img.Image normalizeIllumination(img.Image image) {
    try {
    // Calculate mean pixel value
    double sum = 0;
    int count = 0;
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        sum += pixel.r; // For grayscale, r=g=b
        count++;
      }
    }
    
    final int mean = (sum / count).toInt();
    
    // Create a new image with normalized illumination
    final result = img.Image(width: image.width, height: image.height);
    
    for (int y = 0; y < image.height; y++) {
      for (int x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Adjust pixel value to normalize illumination
        int newValue = (pixel.r - mean + 128).clamp(0, 255).toInt();
        result.setPixelRgb(x, y, newValue, newValue, newValue);
      }
    }
    
    return result;
    } catch (e) {
      print('Error in normalizeIllumination: $e');
      return image; // Return original image on error
    }
  }
  
  // Clean up resources
  static void dispose() {
    if (_isolate != null) {
      _isolate!.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _isolateReady = false;
  }

  // New method for face alignment based on eye positions
  static img.Image alignFace(img.Image image, List<Point> landmarks) {
    if (landmarks.length < 5) {
      print('Warning: Not enough landmarks for face alignment');
      return image;
    }
    
    try {
      // Extract eye landmarks
      Point leftEye = landmarks[0];
      Point rightEye = landmarks[1];
      
      // Calculate angle for alignment
      double deltaY = rightEye.y - leftEye.y;
      double deltaX = rightEye.x - leftEye.x;
      double angle = math.atan2(deltaY, deltaX) * 180 / math.pi;
      
      // Rotate image to align eyes horizontally
      img.Image rotated = img.copyRotate(image, angle: -angle);
      
      // Calculate center of face from landmarks
      double centerX = 0;
      double centerY = 0;
      for (Point landmark in landmarks) {
        centerX += landmark.x;
        centerY += landmark.y;
      }
      centerX /= landmarks.length;
      centerY /= landmarks.length;
      
      // Calculate face size based on distance between landmarks
      double maxDistance = 0;
      for (Point landmark in landmarks) {
        double dx = landmark.x - centerX;
        double dy = landmark.y - centerY;
        double distance = math.sqrt(dx * dx + dy * dy);
        if (distance > maxDistance) {
          maxDistance = distance;
        }
      }
      
      // Calculate crop region with margin
      double margin = maxDistance * 1.5;
      int cropX = math.max(0, (centerX - margin).round());
      int cropY = math.max(0, (centerY - margin).round());
      int cropWidth = math.min(rotated.width - cropX, (margin * 2).round());
      int cropHeight = math.min(rotated.height - cropY, (margin * 2).round());
      
      if (cropWidth <= 0 || cropHeight <= 0) {
        print('Warning: Invalid crop dimensions, using original image');
        return image;
      }
      
      // Crop to face region
      img.Image cropped = img.copyCrop(
        rotated, 
        x: cropX, 
        y: cropY, 
        width: cropWidth, 
        height: cropHeight
      );
      
      // Enhance the cropped face image
      return enhanceFaceImage(cropped);
    } catch (e) {
      print('Error in face alignment: $e');
      return image; // Return original image on error
    }
  }
  
  // Enhanced method specifically for face images
  static img.Image enhanceFaceImage(img.Image faceImage) {
    try {
      // 1. Convert to grayscale for better feature extraction
      img.Image grayscale = img.grayscale(faceImage);
      
      // 2. Apply histogram equalization for better contrast
      img.Image equalized = histogramEqualization(grayscale);
      
      // 3. Apply adaptive brightness and contrast
      img.Image adjusted = adjustBrightnessContrast(equalized, 
          brightness: 0, contrast: 1.3);
      
      // 4. Apply light normalization to reduce lighting variations
      img.Image normalized = normalizeIllumination(adjusted);
      
      // 5. Apply slight gaussian blur to reduce noise (optional)
      img.Image smoothed = img.gaussianBlur(normalized, radius: 1);
      
      return smoothed;
    } catch (e) {
      print('Error in enhanceFaceImage: $e');
      return faceImage; // Return original image on error
    }
  }
  
  // Add histogram equalization for better contrast
  static img.Image histogramEqualization(img.Image image) {
    try {
      final result = img.Image(width: image.width, height: image.height);
      
      // Calculate histogram
      List<int> histogram = List<int>.filled(256, 0);
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          histogram[pixel.r.toInt()]++;
        }
      }
      
      // Calculate cumulative histogram
      List<int> cdf = List<int>.filled(256, 0);
      cdf[0] = histogram[0];
      for (int i = 1; i < 256; i++) {
        cdf[i] = cdf[i-1] + histogram[i];
      }
      
      // Normalize CDF
      int pixelCount = image.width * image.height;
      List<int> equalized = List<int>.filled(256, 0);
      for (int i = 0; i < 256; i++) {
        equalized[i] = ((cdf[i] * 255) ~/ pixelCount);
      }
      
      // Apply equalization
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          int newValue = equalized[pixel.r.toInt()];
          result.setPixelRgb(x, y, newValue, newValue, newValue);
        }
      }
      
      return result;
    } catch (e) {
      print('Error in histogramEqualization: $e');
      return image; // Return original image on error
    }
  }
  
  // Assess image quality for face recognition (0-1 scale)
  static double assessImageQuality(img.Image image) {
    try {
      // 1. Check resolution - faces should be at least 80x80
      double sizeScore = math.min(1.0, (math.min(image.width, image.height) / 80.0));
      
      // 2. Check contrast
      double contrastScore = calculateContrastScore(image);
      
      // 3. Check brightness
      double brightnessScore = calculateBrightnessScore(image);
      
      // 4. Combine scores (weighted average)
      double qualityScore = (sizeScore * 0.3) + (contrastScore * 0.4) + (brightnessScore * 0.3);
      
      // Clamp to [0, 1]
      return qualityScore.clamp(0.0, 1.0);
    } catch (e) {
      print('Error assessing image quality: $e');
      return 0.5; // Default medium quality on error
    }
  }
  
  // Calculate contrast score for quality assessment
  static double calculateContrastScore(img.Image image) {
    try {
      int min = 255;
      int max = 0;
      
      // Find min and max pixel values
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          if (pixel.r.toInt() < min) min = pixel.r.toInt();
          if (pixel.r.toInt() > max) max = pixel.r.toInt();
        }
      }
      
      // Calculate contrast ratio
      if (max == min) return 0.0;
      
      double contrast = (max - min) / 255.0;
      
      // Low contrast and too high contrast are both bad
      if (contrast < 0.3) return contrast; // Linearly penalize low contrast
      if (contrast > 0.8) return 1.0 - ((contrast - 0.8) * 2); // Penalize too high contrast
      
      // Ideal contrast range: 0.3 - 0.8
      return math.min(1.0, contrast / 0.8);
    } catch (e) {
      print('Error calculating contrast score: $e');
      return 0.5;
    }
  }
  
  // Calculate brightness score for quality assessment
  static double calculateBrightnessScore(img.Image image) {
    try {
      double sum = 0;
      int count = 0;
      
      // Calculate average brightness
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final pixel = image.getPixel(x, y);
          sum += pixel.r.toDouble();
          count++;
        }
      }
      
      double avgBrightness = sum / (count * 255.0); // Normalize to 0-1
      
      // Ideal brightness is around 0.5
      // Penalize too dark or too bright
      double distance = (avgBrightness - 0.5).abs();
      
      // Score from 0-1 where 1 is optimal (brightness = 0.5)
      return 1.0 - math.min(1.0, distance * 2);
    } catch (e) {
      print('Error calculating brightness score: $e');
      return 0.5;
    }
  }
}

// Class for isolate communication
class _ImageProcessRequest {
  final CameraImage cameraImage;
  final bool isAndroid;
  final SendPort responsePort;
  
  _ImageProcessRequest({
    required this.cameraImage,
    required this.isAndroid,
    required this.responsePort
  });
}

 img.Image convertNV21(CameraImage image) {
  try {
    // Create a blank image with the camera dimensions
    final img.Image result = img.Image(width: image.width, height: image.height);
    
    // Get the Y plane (first plane) which contains grayscale data
    final Uint8List yPlane = image.planes[0].bytes;
    final int yRowStride = image.planes[0].bytesPerRow;
    
    final int width = image.width;
    final int height = image.height;
    
    // Process each pixel safely
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        // Calculate the index in the Y plane
        final int yIndex = y * yRowStride + x;
        
        // Only access the buffer if the index is valid
        if (yIndex < yPlane.length) {
          final int yValue = yPlane[yIndex] & 0xFF;
          result.setPixelRgb(x, y, yValue, yValue, yValue);
        }
      }
    }
    
    print('Converted NV21 image safely: ${width}x${height}');
    return result;
  } catch (e) {
    print('Error in convertNV21: $e');
    // Return a blank image in case of error
    return img.Image(width: image.width, height: image.height);
  }
}