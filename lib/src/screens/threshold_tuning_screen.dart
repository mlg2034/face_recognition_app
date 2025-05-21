import 'dart:math';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/recognizer.dart';

class ThresholdTuningScreen extends StatefulWidget {
  final Recognizer recognizer;
  
  const ThresholdTuningScreen({Key? key, required this.recognizer}) : super(key: key);
  
  @override
  _ThresholdTuningScreenState createState() => _ThresholdTuningScreenState();
}

class _ThresholdTuningScreenState extends State<ThresholdTuningScreen> {
  double currentThreshold = 0.5;
  double farRate = 0.0; // False acceptance rate
  double frrRate = 0.0; // False rejection rate
  
  @override
  void initState() {
    super.initState();
//    currentThreshold = widget.recognizer.widgetrecognitionThreshold;
    calculateRates(currentThreshold);
  }
  
  Future<void> calculateRates(double threshold) async {
    // In a real implementation, this would run a test dataset
    // For now, using simplified estimation formulas
    
    // Example calculation - in practice these would be computed from real data
    // Lower threshold = more matches = higher FAR, lower FRR
    // Higher threshold = fewer matches = lower FAR, higher FRR
    setState(() {
      // These are just example formulas for visualization
      farRate = 0.8 * pow((1.0 - threshold), 2);
      frrRate = 0.9 * pow(threshold, 2);
    });
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recognition Threshold Tuning'),
        backgroundColor: Colors.blue,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Adjust recognition threshold',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Higher values = stricter matching (fewer false accepts, more false rejects)',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            Text(
              'Current threshold: ${currentThreshold.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 16),
            ),
            Slider(
              value: currentThreshold,
              min: 0.1,
              max: 0.9,
              divisions: 40,
              label: currentThreshold.toStringAsFixed(2),
              onChanged: (value) async {
                setState(() {
                  currentThreshold = value;
                });
                calculateRates(value);
              },
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Estimated Performance Metrics:',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricCard(
                          'False Acceptance Rate (FAR)',
                          '${(farRate * 100).toStringAsFixed(1)}%',
                          'Different people recognized as same',
                          Colors.red.shade100,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildMetricCard(
                          'False Rejection Rate (FRR)',
                          '${(frrRate * 100).toStringAsFixed(1)}%',
                          'Same person not recognized',
                          Colors.blue.shade100,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 30),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ElevatedButton(
                  onPressed: () async {
                //    await widget.recognizer.setRecognitionThreshold(currentThreshold);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Threshold updated successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Apply Threshold', style: TextStyle(fontSize: 16)),
                ),
                const SizedBox(width: 20),
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.blue),
                    padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 16)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildMetricCard(String title, String value, String description, Color color) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 5),
          Text(
            description,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }
} 