import 'dart:convert';
import 'dart:io';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

class ROCChart extends StatefulWidget {
  final RecognitionLogger logger;
  final double height;
  final double width;
  
  const ROCChart({
    Key? key,
    required this.logger,
    this.height = 300,
    this.width = double.infinity,
  }) : super(key: key);

  @override
  State<ROCChart> createState() => _ROCChartState();
}

class _ROCChartState extends State<ROCChart> {
  List<FlSpot> _rocPoints = [];
  double _auc = 0.0;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadROCData();
  }

  Future<void> _loadROCData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      String csvData = await widget.logger.exportROCDataAsCSV();
      if (csvData.startsWith("Error")) {
        setState(() {
          _errorMessage = "Not enough data to generate ROC curve";
          _isLoading = false;
        });
        return;
      }

      List<FlSpot> tprFprPairs = [];
      List<String> lines = csvData.split('\n');
      
      // Skip header line
      if (lines.length > 1) {
        // First we need to parse all the data points
        List<Map<String, dynamic>> dataPoints = [];
        
        for (int i = 1; i < lines.length; i++) {
          String line = lines[i].trim();
          if (line.isEmpty) continue;
          
          List<String> values = line.split(',');
          if (values.length >= 2) {
            try {
              double distance = double.parse(values[0]);
              int isMatch = int.parse(values[1]);
              
              dataPoints.add({
                'distance': distance,
                'is_match': isMatch,
              });
            } catch (e) {
              print('Error parsing line: $line - $e');
            }
          }
        }
        
        // Now we need to calculate the ROC curve points
        if (dataPoints.isNotEmpty) {
          // Sort by distance for threshold analysis
          dataPoints.sort((a, b) => a['distance'].compareTo(b['distance']));
          
          int positives = dataPoints.where((p) => p['is_match'] == 1).length;
          int negatives = dataPoints.where((p) => p['is_match'] == 0).length;
          
          if (positives > 0 && negatives > 0) {
            // Generate ROC curve points at different thresholds
            List<Map<String, dynamic>> rocPoints = [];
            
            // Start with 0,0 point
            rocPoints.add({
              'threshold': -1.0,
              'tpr': 0.0,
              'fpr': 0.0,
            });
            
            // Calculate all the intermediate points
            for (int i = 0; i < dataPoints.length; i++) {
              double threshold = dataPoints[i]['distance'];
              
              int tp = 0; // matches correctly identified as matches
              int fp = 0; // non-matches incorrectly identified as matches
              
              for (var point in dataPoints) {
                bool predictedMatch = point['distance'] <= threshold;
                bool actualMatch = point['is_match'] == 1;
                
                if (actualMatch && predictedMatch) tp++;
                if (!actualMatch && predictedMatch) fp++;
              }
              
              double tpr = positives > 0 ? tp / positives : 0;
              double fpr = negatives > 0 ? fp / negatives : 0;
              
              rocPoints.add({
                'threshold': threshold,
                'tpr': tpr,
                'fpr': fpr,
              });
            }
            
            // Add 1,1 point
            rocPoints.add({
              'threshold': double.infinity,
              'tpr': 1.0,
              'fpr': 1.0,
            });
            
            // Sort by FPR for proper curve drawing
            rocPoints.sort((a, b) => a['fpr'].compareTo(b['fpr']));
            
            // Remove duplicate FPR points, keeping the highest TPR
            Map<double, double> bestTprByFpr = {};
            for (var point in rocPoints) {
              double fpr = (point['fpr'] * 100).roundToDouble() / 100; // Round to 2 decimal places
              double tpr = point['tpr'];
              
              if (!bestTprByFpr.containsKey(fpr) || bestTprByFpr[fpr]! < tpr) {
                bestTprByFpr[fpr] = tpr;
              }
            }
            
            // Convert to FlSpot for the chart
            List<FlSpot> spots = [];
            List<double> fprs = bestTprByFpr.keys.toList()..sort();
            for (double fpr in fprs) {
              spots.add(FlSpot(fpr, bestTprByFpr[fpr]!));
            }
            
            // Calculate AUC using the trapezoidal rule
            double auc = 0.0;
            for (int i = 1; i < spots.length; i++) {
              double width = spots[i].x - spots[i-1].x;
              double avgHeight = (spots[i].y + spots[i-1].y) / 2;
              auc += width * avgHeight;
            }
            
            setState(() {
              _rocPoints = spots;
              _auc = auc;
              _isLoading = false;
            });
            return;
          }
        }
      }
      
      setState(() {
        _errorMessage = "Not enough data points to generate ROC curve";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = "Error generating ROC curve: $e";
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      width: widget.width,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? Center(
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                )
              : Column(
                  children: [
                    Text(
                      'ROC Curve (AUC: ${_auc.toStringAsFixed(3)})',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: true),
                          titlesData: FlTitlesData(
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                    ),
                                  );
                                },
                                reservedSize: 30,
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                getTitlesWidget: (value, meta) {
                                  return Text(
                                    value.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white60,
                                      fontSize: 10,
                                    ),
                                  );
                                },
                                reservedSize: 30,
                              ),
                            ),
                            rightTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                            topTitles: const AxisTitles(
                              sideTitles: SideTitles(showTitles: false),
                            ),
                          ),
                          borderData: FlBorderData(show: true),
                          lineBarsData: [
                            // ROC curve
                            LineChartBarData(
                              spots: _rocPoints,
                              isCurved: true,
                              color: Colors.blue,
                              barWidth: 3,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(
                                show: true,
                                color: Colors.blue.withOpacity(0.2),
                              ),
                            ),
                            // Random classifier line (y=x)
                            LineChartBarData(
                              spots: const [
                                FlSpot(0, 0),
                                FlSpot(1, 1),
                              ],
                              color: Colors.grey.withOpacity(0.5),
                              barWidth: 1,
                              isStrokeCapRound: true,
                              dotData: const FlDotData(show: false),
                              dashArray: [5, 5],
                            ),
                          ],
                          minX: 0,
                          maxX: 1,
                          minY: 0,
                          maxY: 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'False Positive Rate (FPR)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                        TextButton.icon(
                          icon: const Icon(Icons.refresh, size: 16, color: Colors.white70),
                          label: const Text('Refresh', style: TextStyle(color: Colors.white70, fontSize: 12)),
                          onPressed: _loadROCData,
                        ),
                      ],
                    ),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: RotatedBox(
                        quarterTurns: 3,
                        child: Text(
                          'True Positive Rate (TPR)',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
} 