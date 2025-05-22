import 'dart:async';
import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/recognition_logger.dart';

class LogsDisplayWidget extends StatefulWidget {
  const LogsDisplayWidget({Key? key}) : super(key: key);

  @override
  _LogsDisplayWidgetState createState() => _LogsDisplayWidgetState();
}

class _LogsDisplayWidgetState extends State<LogsDisplayWidget> {
  final ScrollController _scrollController = ScrollController();
  String _logText = '';
  Timer? _refreshTimer;
  bool _autoScroll = true;
  
  @override
  void initState() {
    super.initState();
    _loadLogs();
    
    // Refresh logs every 2 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      _loadLogs();
    });
  }
  
  @override
  void dispose() {
    _refreshTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }
  
  Future<void> _loadLogs() async {
    final logs = await RecognitionLogger().getLogsAsString();
    
    if (mounted) {
      setState(() {
        _logText = logs;
      });
      
      // Auto-scroll to bottom if enabled
      if (_autoScroll && _scrollController.hasClients) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withOpacity(0.8),
      child: Column(
        children: [
          // Header with controls
          Container(
            color: Colors.black.withOpacity(0.9),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recognition Logs',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Row(
                  children: [
                    // Auto-scroll toggle
                    Row(
                      children: [
                        const Text(
                          'Auto-scroll',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        Switch(
                          value: _autoScroll,
                          onChanged: (value) {
                            setState(() {
                              _autoScroll = value;
                            });
                          },
                          activeColor: Colors.blue,
                        ),
                      ],
                    ),
                    // Clear logs button
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.white),
                      onPressed: () async {
                        await RecognitionLogger().clearLogs();
                        _loadLogs();
                      },
                      tooltip: 'Clear logs',
                    ),
                    // Refresh button
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      onPressed: _loadLogs,
                      tooltip: 'Refresh logs',
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Log content
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(8),
              child: SelectableText(
                _logText,
                style: const TextStyle(
                  color: Colors.lightGreenAccent,
                  fontFamily: 'monospace',
                  fontSize: 11,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
} 