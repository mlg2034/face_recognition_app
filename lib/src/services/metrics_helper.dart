import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

/// Helper class for metrics and statistics related to face recognition
class MetricsHelper {
  /// Get a formatted accuracy report string
  static String getAccuracyReport() {
    final RecognitionLogger logger = RecognitionLogger();
    final metrics = logger.getAccuracyMetrics();
    
    double accuracy = metrics['accuracy'] ?? 0.0;
    double far = metrics['far'] ?? 0.0;
    double frr = metrics['frr'] ?? 0.0;
    int samples = metrics['samples'] ?? 0;
    
    if (samples == 0) {
      return "No recognition data available yet";
    }
    
    return "Accuracy: ${(accuracy * 100).toStringAsFixed(1)}% | FAR: ${(far * 100).toStringAsFixed(1)}% | FRR: ${(frr * 100).toStringAsFixed(1)}% | Samples: $samples";
  }
  
  /// Display face recognition statistics in the console
  static Future<void> showFaceRecognitionStats() async {
    try {
      final RecognitionLogger logger = RecognitionLogger();
      final metrics = logger.getAccuracyMetrics();
      
      double accuracy = metrics['accuracy'] ?? 0.0;
      double precision = metrics['precision'] ?? 0.0;
      double recall = metrics['recall'] ?? 0.0;
      double f1Score = metrics['f1_score'] ?? 0.0;
      double far = metrics['far'] ?? 0.0;
      double frr = metrics['frr'] ?? 0.0;
      int samples = metrics['samples'] ?? 0;
      double threshold = metrics['threshold'] ?? 0.48;
      
      // Print statistics to console in a formatted way
      print('\n----------------------------------------');
      print('📊 FACE RECOGNITION STATISTICS 📊');
      print('----------------------------------------');
      print('✅ Accuracy: ${(accuracy * 100).toStringAsFixed(2)}%');
      print('🎯 Precision: ${(precision * 100).toStringAsFixed(2)}%');
      print('📥 Recall: ${(recall * 100).toStringAsFixed(2)}%');
      print('⚖️ F1 Score: ${(f1Score * 100).toStringAsFixed(2)}%');
      print('❌ False Accept Rate: ${(far * 100).toStringAsFixed(2)}%');
      print('🚫 False Reject Rate: ${(frr * 100).toStringAsFixed(2)}%');
      print('📝 Total Samples: $samples');
      print('🔍 Current Threshold: ${threshold.toStringAsFixed(4)}');
      print('----------------------------------------\n');
      
      // Note about ROC curve
      print('Note: ROC curve data is available via exportROCData()');
      
      // Add a small delay to make it feel like it's doing something
      await Future.delayed(Duration(milliseconds: 100));
    } catch (e) {
      print('Error showing face recognition stats: $e');
    }
  }
  
  /// Export ROC data to a CSV file
  static Future<String> exportROCData() async {
    try {
      final RecognitionLogger logger = RecognitionLogger();
      final csvData = await logger.exportROCDataAsCSV();
      
      // Save to file
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${appDocDir.path}/roc_data_$timestamp.csv');
      
      await file.writeAsString(csvData);
      
      print('ROC data exported to: ${file.path}');
      return file.path;
    } catch (e) {
      print('Error exporting ROC data: $e');
      return '';
    }
  }
  
  /// Generate a metrics log file
  static Future<String> generateMetricsLog() async {
    try {
      final RecognitionLogger logger = RecognitionLogger();
      final metrics = logger.getAccuracyMetrics();
      
      // Format metrics as JSON with nice indentation
      String metricsJson = '''
{
  "accuracy": ${metrics['accuracy']},
  "precision": ${metrics['precision']},
  "recall": ${metrics['recall']},
  "f1_score": ${metrics['f1_score']},
  "false_accept_rate": ${metrics['far']},
  "false_reject_rate": ${metrics['frr']},
  "samples": ${metrics['samples']},
  "threshold": ${metrics['threshold']},
  "true_positives": ${metrics['truePositives']},
  "false_positives": ${metrics['falsePositives']},
  "true_negatives": ${metrics['trueNegatives']},
  "false_negatives": ${metrics['falseNegatives']},
  "timestamp": "${DateTime.now().toIso8601String()}"
}
''';
      
      // Save to file
      final Directory appDocDir = await getApplicationDocumentsDirectory();
      final String timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final File file = File('${appDocDir.path}/face_metrics_$timestamp.json');
      
      await file.writeAsString(metricsJson);
      
      print('Metrics log saved to: ${file.path}');
      return file.path;
    } catch (e) {
      print('Error generating metrics log: $e');
      return '';
    }
  }
} 