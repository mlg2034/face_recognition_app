import 'dart:isolate';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;

class IsolateUtils {
  static Isolate? _isolate;
  static ReceivePort? _receivePort;
  static SendPort? _sendPort;
  static bool _initialized = false;
  
  static Future<void> initialize() async {
    if (_initialized) return;
    
    _receivePort = ReceivePort();
    _isolate = await Isolate.spawn(_isolateEntryPoint, _receivePort!.sendPort);
    _sendPort = await _receivePort!.first;
    _initialized = true;
    print('Isolate initialized successfully');
  }
  
  static void _isolateEntryPoint(SendPort sendPort) {
    final receivePort = ReceivePort();
    sendPort.send(receivePort.sendPort);
    
    receivePort.listen((message) {
      if (message is _IsolateMessage) {
        try {
          final result = _processInIsolate(message);
          message.responsePort.send(result);
        } catch (e) {
          print('Error in isolate: $e');
          message.responsePort.send(null);
        }
      }
    });
  }
  
  static dynamic _processInIsolate(_IsolateMessage message) {
    switch (message.type) {
      case _IsolateMessageType.processImage:
        final data = message.data as Map<String, dynamic>;
        final width = data['width'] as int;
        final height = data['height'] as int;
        final bytes = data['bytes'] as Uint8List;
        final isAndroid = data['isAndroid'] as bool;
        
        final img.Image result = img.Image(width: width, height: height);
        
        if (isAndroid) {
          try {
            final int processLength = bytes.length < (width * height) ? bytes.length : (width * height);
            
            for (int i = 0; i < processLength; i++) {
              final int y = i ~/ width;
              final int x = i % width;
              final int yValue = bytes[i] & 0xFF;
              result.setPixelRgb(x, y, yValue, yValue, yValue);
            }
          } catch (e) {
            print('Error processing NV21 in isolate: $e');
          }
        } else {
          try {
            final int bytesPerRow = data['bytesPerRow'] as int;
            final int offset = 28; // iOS offset
            
            for (int y = 0; y < height; y++) {
              for (int x = 0; x < width; x++) {
                final int pixelIndex = offset + y * bytesPerRow + x * 4;
                
                if (pixelIndex + 3 < bytes.length) {
                  final int b = bytes[pixelIndex] & 0xFF;
                  final int g = bytes[pixelIndex + 1] & 0xFF;
                  final int r = bytes[pixelIndex + 2] & 0xFF;
                  result.setPixelRgb(x, y, r, g, b);
                }
              }
            }
          } catch (e) {
            print('Error processing BGRA in isolate: $e');
          }
        }
        
        return result;
        
      default:
        return null;
    }
  }
  
  static Future<img.Image?> processImageInIsolate(CameraImage cameraImage, bool isAndroid) async {
    if (!_initialized) {
      await initialize();
    }
    
    if (_sendPort == null) {
      print('Isolate not initialized');
      return null;
    }
    
    try {
      final responsePort = ReceivePort();
      
      final message = _IsolateMessage(
        type: _IsolateMessageType.processImage,
        data: {
          'width': cameraImage.width,
          'height': cameraImage.height,
          'bytes': cameraImage.planes[0].bytes,
          'bytesPerRow': cameraImage.planes[0].bytesPerRow,
          'isAndroid': isAndroid,
        },
        responsePort: responsePort.sendPort
      );
      
      _sendPort!.send(message);
      
      final result = await responsePort.first.timeout(
        Duration(seconds: 2),
        onTimeout: () {
          print('Isolate processing timed out');
          return null;
        }
      );
      
      return result as img.Image?;
    } catch (e) {
      print('Error in processImageInIsolate: $e');
      return null;
    }
  }
  
  static void dispose() {
    if (_isolate != null) {
      _isolate!.kill(priority: Isolate.immediate);
      _isolate = null;
    }
    _receivePort?.close();
    _receivePort = null;
    _sendPort = null;
    _initialized = false;
  }
}

enum _IsolateMessageType {
  processImage,
}

class _IsolateMessage {
  final _IsolateMessageType type;
  final dynamic data;
  final SendPort responsePort;
  
  _IsolateMessage({
    required this.type,
    required this.data,
    required this.responsePort
  });
} 