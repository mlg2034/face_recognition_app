import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class RecognitionLogger {
  static final RecognitionLogger _instance = RecognitionLogger._internal();
  factory RecognitionLogger() => _instance;
  RecognitionLogger._internal();

  late final DatabaseReference _databaseRef;
  late final String _deviceId;
  late final File _logFile;
  bool _initialized = false;

  // Detailed logging of face embedding values
  bool _logFaceEmbeddings = true;
  
  Future<void> initialize() async {
    if (_initialized) return;
    
    // Set up Firebase
    _databaseRef = FirebaseDatabase.instance.ref('recognition_logs');
    
    // Generate a random device ID if not already available
    _deviceId = DateTime.now().millisecondsSinceEpoch.toString();
    
    // Set up local logging
    final directory = await getApplicationDocumentsDirectory();
    _logFile = File('${directory.path}/face_recognition_logs.txt');
    
    _initialized = true;
    
    // Log initialization
    _logToConsole('Recognition logger initialized');
    await _logToFile('===== RECOGNITION LOGGER INITIALIZED =====');
  }
  
  Future<void> logRecognition({
    required String personName,
    required String matchedName,
    required double distance,
    required double qualityScore,
    List<double>? embedding,
  }) async {
    if (!_initialized) await initialize();
    
    final timestamp = DateTime.now().toIso8601String();
    
    // Prepare log data
    final Map<String, dynamic> logData = {
      'timestamp': timestamp,
      'personName': personName,
      'matchedName': matchedName,
      'distance': distance,
      'qualityScore': qualityScore,
      'recognized': matchedName != 'Unknown',
    };
    
    // Add embeddings if enabled
    if (_logFaceEmbeddings && embedding != null) {
      // Only log a subset of embedding values to avoid excessive output
      // For full embeddings, consider storing to file instead
      final embeddingSample = embedding.take(10).toList();
      logData['embeddingSample'] = embeddingSample;
      logData['embeddingNorm'] = _calculateNorm(embedding);
    }
    
    // Log to console
    _logToConsole('RECOGNITION: $matchedName (distance: ${distance.toStringAsFixed(4)}, quality: ${qualityScore.toStringAsFixed(2)})');
    
    if (_logFaceEmbeddings && embedding != null) {
      _logToConsole('EMBEDDING SAMPLE: ${embedding.take(5).map((e) => e.toStringAsFixed(4)).join(", ")}...');
      _logToConsole('EMBEDDING NORM: ${_calculateNorm(embedding).toStringAsFixed(4)}');
    }
    
    // Log to file
    await _logToFile(jsonEncode(logData));
    
    // Log to Firebase if available
    try {
      await _databaseRef.child(_deviceId).push().set(logData);
    } catch (e) {
      _logToConsole('Failed to log to Firebase: $e');
    }
  }
  
  Future<void> logFaceQuality({
    required double qualityScore,
    required Map<String, dynamic> qualityMetrics,
  }) async {
    if (!_initialized) await initialize();
    
    final timestamp = DateTime.now().toIso8601String();
    
    final Map<String, dynamic> logData = {
      'timestamp': timestamp,
      'qualityScore': qualityScore,
      'qualityMetrics': qualityMetrics,
    };
    
    // Log to console
    _logToConsole('FACE QUALITY: ${qualityScore.toStringAsFixed(2)}, metrics: $qualityMetrics');
    
    // Log to file
    await _logToFile(jsonEncode(logData));
  }
  
  Future<void> logProcessingTime({
    required String operation,
    required int milliseconds,
  }) async {
    if (!_initialized) await initialize();
    
    final timestamp = DateTime.now().toIso8601String();
    
    final Map<String, dynamic> logData = {
      'timestamp': timestamp,
      'operation': operation,
      'milliseconds': milliseconds,
    };
    
    // Log to console
    _logToConsole('TIMING: $operation took $milliseconds ms');
    
    // Log to file
    await _logToFile(jsonEncode(logData));
  }
  
  Future<void> _logToFile(String message) async {
    try {
      await _logFile.writeAsString('$message\n', mode: FileMode.append);
    } catch (e) {
      debugPrint('Error writing to log file: $e');
    }
  }
  
  void _logToConsole(String message) {
    debugPrint('👤 $message');
  }
  
  double _calculateNorm(List<double> vector) {
    double sumSquares = 0.0;
    for (final value in vector) {
      sumSquares += value * value;
    }
    return sumSquares > 0 ? sqrt(sumSquares) : 0.0;
  }
  
  // Enable/disable logging of face embeddings
  void setEmbeddingLogging(bool enabled) {
    _logFaceEmbeddings = enabled;
    _logToConsole('Face embedding logging ${enabled ? 'enabled' : 'disabled'}');
  }
  
  // Get logs as string
  Future<String> getLogsAsString() async {
    if (!_initialized) await initialize();
    
    try {
      if (await _logFile.exists()) {
        return await _logFile.readAsString();
      }
    } catch (e) {
      debugPrint('Error reading log file: $e');
    }
    
    return 'No logs available';
  }
  
  // Clear logs
  Future<void> clearLogs() async {
    if (!_initialized) await initialize();
    
    try {
      await _logFile.writeAsString('');
      _logToConsole('Logs cleared');
    } catch (e) {
      debugPrint('Error clearing log file: $e');
    }
  }
} 