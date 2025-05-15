import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'dart:math' as Math;

class ImageService {
  static var IOS_BYTES_OFFSET = 28;
  
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static SendPort? _sendPort;
  static bool _isolateReady = false;
  
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
      final Uint8List uvPlane = image.planes[1].bytes;
      
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      final int uvRowStride = image.planes[1].bytesPerRow;
      
      for (int y = 0; y < image.height; y++) {
        for (int x = 0; x < image.width; x++) {
          final int yIndex = y * image.width + x;
          
          final int uvRowIndex = (y ~/ 2) * uvRowStride;
          final int uvColIndex = (x ~/ 2) * uvPixelStride;
          
          if (yIndex >= yPlane.length) continue;
          
          int yValue = yPlane[yIndex] & 0xFF;
          
          int uValue = 128;
          int vValue = 128;
          
          final int uvIndex = uvRowIndex + uvColIndex;
          if (uvIndex + 1 < uvPlane.length) {
            uValue = uvPlane[uvIndex] & 0xFF;
            vValue = uvPlane[uvIndex + 1] & 0xFF;
          }
          
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
      // Return a safe fallback
      return img.Image(width: image.width, height: image.height);
    }
  }
  
  // Add fast YUV conversion method
  static Future<img.Image?> convertYUVToImage(CameraImage image) async {
    try {
      // Direct pixel access for better performance
      final img.Image result = img.Image(width: image.width, height: image.height);
      
      final Uint8List yPlane = image.planes[0].bytes;
      final Uint8List uPlane = image.planes[1].bytes;
      final Uint8List vPlane = image.planes[2].bytes;
      
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
      
      for (int y = 0; y < image.height; y += 2) {
        for (int x = 0; x < image.width; x += 2) {
          final int uvIndex = (y ~/ 2) * uvRowStride + (x ~/ 2) * uvPixelStride;
          
          // Fast method processes 2x2 blocks at once for better performance
          _convertYUVblock(
            result, x, y, 
            yPlane, uPlane, vPlane, 
            y * image.width + x, uvIndex, uvPixelStride, 
            image.width
          );
        }
      }
      
      return result;
    } catch (e) {
      return null;
    }
  }
  
  static void _convertYUVblock(
    img.Image output, int x, int y,
    Uint8List yPlane, Uint8List uPlane, Uint8List vPlane,
    int yIndex, int uvIndex, int uvPixelStride, int width
  ) {
    final int u = uPlane[uvIndex];
    final int v = vPlane[uvIndex];
    
    // Precompute color conversion
    int rOffset = (1.370705 * (v - 128)).toInt();
    int gOffset = (-0.698001 * (v - 128) - 0.337633 * (u - 128)).toInt();
    int bOffset = (1.732446 * (u - 128)).toInt();
    
    // Process 2x2 block
    for (int j = 0; j < 2; j++) {
      for (int i = 0; i < 2; i++) {
        if (x + i < output.width && y + j < output.height) {
          int pixelIndex = yIndex + j * width + i;
          if (pixelIndex < yPlane.length) {
            int yValue = yPlane[pixelIndex] & 0xFF;
            
            // YUV to RGB conversion
            int r = (yValue + rOffset).clamp(0, 255);
            int g = (yValue + gOffset).clamp(0, 255);
            int b = (yValue + bOffset).clamp(0, 255);
            
            output.setPixelRgb(x + i, y + j, r, g, b);
          }
        }
      }
    }
  }

  // Fast BGRA conversion for iOS
  static Future<img.Image?> convertBGRA8888Fast(CameraImage image) async {
    try {
      final plane = image.planes[0];
      
      // Use direct buffer access for better performance
      return img.Image.fromBytes(
        width: image.width,
        height: image.height,
        bytes: plane.bytes.buffer,
        bytesOffset: IOS_BYTES_OFFSET,
        order: img.ChannelOrder.bgra,
      );
    } catch (e) {
      try {
        // Fallback to manual conversion
        final plane = image.planes[0];
        final img.Image result = img.Image(width: image.width, height: image.height);
        
        // Process in blocks for better performance
        const int blockSize = 16;
        for (int y = 0; y < image.height; y += blockSize) {
          for (int x = 0; x < image.width; x += blockSize) {
            _processBGRABlock(result, plane, x, y, 
                              Math.min(blockSize, image.width - x), 
                              Math.min(blockSize, image.height - y));
          }
        }
        
        return result;
      } catch (e) {
        return null;
      }
    }
  }
  
  static void _processBGRABlock(img.Image output, Plane plane, int startX, int startY, int width, int height) {
    final int bytesPerPixel = 4;
    
    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int pixelIndex = IOS_BYTES_OFFSET + 
                              (startY + y) * plane.bytesPerRow + 
                              (startX + x) * bytesPerPixel;
        
        if (pixelIndex + 3 < plane.bytes.length) {
          final int b = plane.bytes[pixelIndex] & 0xFF;
          final int g = plane.bytes[pixelIndex + 1] & 0xFF;
          final int r = plane.bytes[pixelIndex + 2] & 0xFF;
          
          output.setPixelRgb(startX + x, startY + y, r, g, b);
        }
      }
    }
  }
  
  // Adding image enhancement with reduced processing
  static img.Image enhanceImage(img.Image input) {
    // Simply return the input image since complex processing is costly
    return input;
  }
  
  static img.Image convertNV21Sync(CameraImage image) {
    return _safeConvertNV21(image);
  }
  
  static img.Image convertBGRA8888ToImageSync(CameraImage image) {
    return _safeConvertBGRA8888(image);
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