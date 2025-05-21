import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'package:logger/logger.dart';
import 'dart:async';

class RecognitionData {
  final String personName;
  final String matchedName;
  final double distance;
  final double qualityScore;
  final DateTime timestamp;
  final bool isMatch;
  
  RecognitionData({
    required this.personName,
    required this.matchedName,
    required this.distance,
    required this.qualityScore,
    required this.timestamp,
  }) : isMatch = personName == matchedName;
  
  Map<String, dynamic> toJson() {
    return {
      'personName': personName,
      'matchedName': matchedName,
      'distance': distance,
      'qualityScore': qualityScore,
      'timestamp': timestamp.toIso8601String(),
      'isMatch': isMatch,
    };
  }
  
  factory RecognitionData.fromJson(Map<String, dynamic> json) {
    return RecognitionData(
      personName: json['personName'],
      matchedName: json['matchedName'],
      distance: json['distance'],
      qualityScore: json['qualityScore'] ?? 0.0,
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class RecognitionLogger {
  static final RecognitionLogger _instance = RecognitionLogger._();
  factory RecognitionLogger() => _instance;
  RecognitionLogger._();
  
  final _logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );
  
  List<RecognitionData> _recognitionLog = [];
  File? _logFile;
  File? _metricsFile;
  
  // ROC curve data
  List<Map<String, dynamic>> _rocPoints = [];
  double _currentThreshold = 0.48; // From Recognition.RECOGNITION_THRESHOLD
  
  // Metrics
  int _totalAttempts = 0;
  int _correctMatches = 0;
  int _incorrectMatches = 0;
  int _correctRejects = 0;
  int _incorrectRejects = 0;
  
  StreamController<Map<String, dynamic>> _metricsStreamController = 
      StreamController<Map<String, dynamic>>.broadcast();
  
  Stream<Map<String, dynamic>> get metricsStream => _metricsStreamController.stream;
  
  Future<void> initialize() async {
    try {
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      _logFile = File('${appDocDir.path}/face_recognition_log.json');
      _metricsFile = File('${appDocDir.path}/face_recognition_metrics.json');
      
      if (await _logFile!.exists()) {
        _loadExistingLog();
      }
      
      _logger.i('🔍 Starting Face Recognition App');
    } catch (e) {
      _logger.e('Error initializing logger: $e');
    }
  }
  
  Future<void> _loadExistingLog() async {
    try {
      final String content = await _logFile!.readAsString();
      final List<dynamic> jsonList = jsonDecode(content);
      _recognitionLog = jsonList
          .map((json) => RecognitionData.fromJson(json))
          .toList();
      
      _calculateMetrics();
      _logger.i('Loaded ${_recognitionLog.length} log entries');
    } catch (e) {
      _logger.e('Error loading log: $e');
    }
  }
  
  Future<void> _saveLog() async {
    try {
      if (_logFile != null) {
        final jsonList = _recognitionLog.map((data) => data.toJson()).toList();
        await _logFile!.writeAsString(jsonEncode(jsonList));
      }
    } catch (e) {
      _logger.e('Error saving log: $e');
    }
  }
  
  Future<void> logRecognition({
    required String personName,
    required String matchedName,
    required double distance,
    required double qualityScore,
  }) async {
    final RecognitionData data = RecognitionData(
      personName: personName,
      matchedName: matchedName,
      distance: distance,
      qualityScore: qualityScore,
      timestamp: DateTime.now(),
    );
    
    _recognitionLog.add(data);
    
    // Add data point for ROC curve
    _rocPoints.add({
      'distance': distance,
      'isMatch': data.isMatch,
      'qualityScore': qualityScore,
    });
    
    // Update metrics
    _calculateMetrics();
    
    // Save log every 10 entries
    if (_recognitionLog.length % 10 == 0) {
      await _saveLog();
      await _saveMetrics();
    }
    
    // Emit updated metrics to stream
    _metricsStreamController.add(getAccuracyMetrics());
    
    // Log the recognition details
    _logger.i('🔍 FACE RECOGNITION: ${data.isMatch ? '✅' : '❌'} Person: ${data.personName}, Matched as: ${data.matchedName}, Distance: ${data.distance.toStringAsFixed(4)}');
  }
  
  void _calculateMetrics() {
    // Reset counters
    _totalAttempts = _recognitionLog.length;
    _correctMatches = 0;
    _incorrectMatches = 0;
    _correctRejects = 0;
    _incorrectRejects = 0;
    
    for (var data in _recognitionLog) {
      bool predictedMatch = data.distance < _currentThreshold;
      
      if (data.isMatch && predictedMatch) {
        _correctMatches++; // True Positive
      } else if (!data.isMatch && !predictedMatch) {
        _correctRejects++; // True Negative
      } else if (!data.isMatch && predictedMatch) {
        _incorrectMatches++; // False Positive
      } else if (data.isMatch && !predictedMatch) {
        _incorrectRejects++; // False Negative
      }
    }
  }
  
  Future<void> _saveMetrics() async {
    try {
      if (_metricsFile != null) {
        final metrics = getAccuracyMetrics();
        await _metricsFile!.writeAsString(jsonEncode(metrics));
      }
    } catch (e) {
      _logger.e('Error saving metrics: $e');
    }
  }
  
  Map<String, dynamic> getAccuracyMetrics() {
    if (_totalAttempts == 0) {
      return {
        'accuracy': 0.0,
        'precision': 0.0,
        'recall': 0.0,
        'f1_score': 0.0,
        'far': 0.0,
        'frr': 0.0,
        'samples': 0,
        'threshold': _currentThreshold,
      };
    }
    
    // Calculate accuracy metrics
    final accuracy = (_correctMatches + _correctRejects) / _totalAttempts;
    
    // Precision: TP / (TP + FP)
    final precision = _correctMatches > 0
        ? _correctMatches / (_correctMatches + _incorrectMatches)
        : 0.0;
    
    // Recall: TP / (TP + FN)
    final recall = _correctMatches > 0
        ? _correctMatches / (_correctMatches + _incorrectRejects)
        : 0.0;
    
    // F1 Score: 2 * (Precision * Recall) / (Precision + Recall)
    final f1Score = (precision + recall) > 0
        ? 2 * (precision * recall) / (precision + recall)
        : 0.0;
    
    // FAR: False Accept Rate = FP / (FP + TN)
    final far = (_correctRejects + _incorrectMatches) > 0
        ? _incorrectMatches / (_correctRejects + _incorrectMatches)
        : 0.0;
    
    // FRR: False Reject Rate = FN / (TP + FN)
    final frr = (_correctMatches + _incorrectRejects) > 0
        ? _incorrectRejects / (_correctMatches + _incorrectRejects)
        : 0.0;
    
    return {
      'accuracy': accuracy,
      'precision': precision,
      'recall': recall,
      'f1_score': f1Score,
      'far': far,
      'frr': frr,
      'samples': _totalAttempts,
      'threshold': _currentThreshold,
      'truePositives': _correctMatches,
      'falsePositives': _incorrectMatches,
      'trueNegatives': _correctRejects,
      'falseNegatives': _incorrectRejects,
    };
  }
  
  double getFalseAcceptanceRate() {
    if (_correctRejects + _incorrectMatches <= 0) return 0.0;
    return _incorrectMatches / (_correctRejects + _incorrectMatches);
  }
  
  double getFalseRejectionRate() {
    if (_correctMatches + _incorrectRejects <= 0) return 0.0;
    return _incorrectRejects / (_correctMatches + _incorrectRejects);
  }
  
  Future<List<Map<String, dynamic>>> calculateROCCurve() async {
    if (_rocPoints.isEmpty) return [];
    
    List<Map<String, dynamic>> rocCurve = [];
    List<double> thresholds = [];
    
    // Generate threshold values from 0.0 to 1.0 with small steps
    for (double t = 0.0; t <= 1.0; t += 0.01) {
      thresholds.add(t);
    }
    
    for (double threshold in thresholds) {
      int tp = 0, fp = 0, tn = 0, fn = 0;
      
      for (var point in _rocPoints) {
        bool isMatch = point['isMatch'];
        double distance = point['distance'];
        bool predictedMatch = distance < threshold;
        
        if (isMatch && predictedMatch) tp++;
        if (!isMatch && predictedMatch) fp++;
        if (!isMatch && !predictedMatch) tn++;
        if (isMatch && !predictedMatch) fn++;
      }
      
      double tpr = tp > 0 ? tp / (tp + fn) : 0.0; // True Positive Rate (Recall)
      double fpr = (fp + tn) > 0 ? fp / (fp + tn) : 0.0; // False Positive Rate
      
      rocCurve.add({
        'threshold': threshold,
        'tpr': tpr,
        'fpr': fpr,
        'far': fpr,
        'frr': fn > 0 ? fn / (tp + fn) : 0.0,
      });
    }
    
    // Find optimal threshold (best trade-off point)
    double bestDistance = double.infinity;
    double optimalThreshold = 0.48; // Default
    
    for (var point in rocCurve) {
      // Distance to perfect classifier (0,1)
      double fpr = point['fpr'];
      double tpr = point['tpr'];
      double distance = math.sqrt(fpr * fpr + (1 - tpr) * (1 - tpr));
      if (distance < bestDistance) {
        bestDistance = distance;
        optimalThreshold = point['threshold'];
      }
    }
    
    _logger.i('🎯 Optimal threshold calculated: $optimalThreshold');
    _currentThreshold = optimalThreshold;
    _calculateMetrics();
    
    return rocCurve;
  }
  
  // Export ROC data as CSV - needed by ROCChart widget
  Future<String> exportROCDataAsCSV() async {
    try {
      if (_rocPoints.isEmpty) {
        return "Error: No data available to generate ROC curve";
      }
      
      // Generate CSV content
      StringBuffer buffer = StringBuffer();
      buffer.writeln("distance,isMatch,qualityScore");
      
      for (var point in _rocPoints) {
        double distance = point['distance'];
        bool isMatch = point['isMatch'];
        double quality = point['qualityScore'];
        
        buffer.writeln("${distance.toStringAsFixed(6)},${isMatch ? 1 : 0},${quality.toStringAsFixed(4)}");
      }
      
      return buffer.toString();
    } catch (e) {
      _logger.e('Error exporting ROC data as CSV: $e');
      return "Error: $e";
    }
  }
  
  Future<void> clearLogs() async {
    _recognitionLog.clear();
    _rocPoints.clear();
    _calculateMetrics();
    await _saveLog();
    await _saveMetrics();
  }
  
  double pow(double x, double exponent) {
    return x * x;
  }
  
  double sqrt(double x) {
    return math.sqrt(x);
  }
} 