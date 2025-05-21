import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

class MetricsCard extends StatefulWidget {
  final RecognitionLogger logger;
  
  const MetricsCard({
    Key? key,
    required this.logger,
  }) : super(key: key);

  @override
  State<MetricsCard> createState() => _MetricsCardState();
}

class _MetricsCardState extends State<MetricsCard> {
  Map<String, dynamic> _metrics = {};
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _updateMetrics();
  }
  
  void _updateMetrics() {
    setState(() {
      _metrics = widget.logger.getAccuracyMetrics();
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _expanded = !_expanded;
        });
      },
      child: Container(
        margin: const EdgeInsets.all(8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Face Recognition Metrics',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _expanded ? Icons.arrow_drop_up : Icons.arrow_drop_down,
                    color: Colors.white,
                  ),
                  onPressed: () {
                    setState(() {
                      _expanded = !_expanded;
                      _updateMetrics();
                    });
                  },
                ),
              ],
            ),
            if (!_expanded)
              _buildBasicMetrics()
            else
              _buildDetailedMetrics(),
            
            // Update button at the bottom
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                icon: const Icon(Icons.refresh, color: Colors.white70),
                label: const Text(
                  'Refresh', 
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                  ),
                ),
                onPressed: _updateMetrics,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBasicMetrics() {
    final accuracy = (_metrics['accuracy'] ?? 0.0) * 100;
    final far = (_metrics['far'] ?? 0.0) * 100;
    final frr = (_metrics['frr'] ?? 0.0) * 100;
    
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _buildMetricItem('Accuracy', '${accuracy.toStringAsFixed(1)}%', 
            accuracy > 90 ? Colors.green : accuracy > 75 ? Colors.orange : Colors.red),
        _buildMetricItem('FAR', '${far.toStringAsFixed(1)}%', 
            far < 5 ? Colors.green : far < 10 ? Colors.orange : Colors.red),
        _buildMetricItem('FRR', '${frr.toStringAsFixed(1)}%', 
            frr < 5 ? Colors.green : frr < 10 ? Colors.orange : Colors.red),
      ],
    );
  }

  Widget _buildDetailedMetrics() {
    final accuracy = (_metrics['accuracy'] ?? 0.0) * 100;
    final precision = (_metrics['precision'] ?? 0.0) * 100;
    final recall = (_metrics['recall'] ?? 0.0) * 100;
    final f1Score = (_metrics['f1_score'] ?? 0.0) * 100;
    final far = (_metrics['far'] ?? 0.0) * 100;
    final frr = (_metrics['frr'] ?? 0.0) * 100;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Details
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem('Accuracy', '${accuracy.toStringAsFixed(1)}%', 
                  accuracy > 90 ? Colors.green : accuracy > 75 ? Colors.orange : Colors.red),
              _buildMetricItem('Precision', '${precision.toStringAsFixed(1)}%', 
                  precision > 90 ? Colors.green : precision > 75 ? Colors.orange : Colors.red),
              _buildMetricItem('Recall', '${recall.toStringAsFixed(1)}%', 
                  recall > 90 ? Colors.green : recall > 75 ? Colors.orange : Colors.red),
            ],
          ),
        ),
        
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildMetricItem('F1 Score', '${f1Score.toStringAsFixed(1)}%', 
                  f1Score > 90 ? Colors.green : f1Score > 75 ? Colors.orange : Colors.red),
              _buildMetricItem('FAR', '${far.toStringAsFixed(1)}%', 
                  far < 5 ? Colors.green : far < 10 ? Colors.orange : Colors.red),
              _buildMetricItem('FRR', '${frr.toStringAsFixed(1)}%', 
                  frr < 5 ? Colors.green : frr < 10 ? Colors.orange : Colors.red),
            ],
          ),
        ),
        
        // Counts
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Total: ${_metrics['total_attempts'] ?? 0} | ' +
            'TP: ${_metrics['true_positives'] ?? 0} | ' +
            'TN: ${_metrics['true_negatives'] ?? 0} | ' +
            'FP: ${_metrics['false_positives'] ?? 0} | ' +
            'FN: ${_metrics['false_negatives'] ?? 0}',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w400,
              color: Colors.white70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.white70,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
} 