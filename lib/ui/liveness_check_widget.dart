import 'package:flutter/material.dart';
import 'package:realtime_face_recognition/src/services/liveness_detection_service.dart';
import 'package:realtime_face_recognition/core/app/ui/app_fonts.dart';

class LivenessCheckWidget extends StatelessWidget {
  final LivenessDetectionService livenessService;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  const LivenessCheckWidget({
    Key? key,
    required this.livenessService,
    required this.onStart,
    required this.onCancel,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Progress indicator
          StreamBuilder<LivenessState>(
            stream: livenessService.stateStream,
            builder: (context, snapshot) {
              final state = snapshot.data ?? LivenessState.notStarted;

              // Determine color based on state
              Color stateColor;
              if (state == LivenessState.completed) {
                stateColor = Colors.green;
              } else if (state == LivenessState.failed) {
                stateColor = Colors.red;
              } else if (state == LivenessState.inProgress) {
                stateColor = Colors.blue;
              } else {
                stateColor = Colors.grey;
              }

              return Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    // Display current check type
                    if (state == LivenessState.inProgress)
                      LinearProgressIndicator(
                        value: livenessService.currentCheckIndex / 
                               livenessService.checkSequence.length,
                        backgroundColor: Colors.grey[700],
                        valueColor: AlwaysStoppedAnimation<Color>(stateColor),
                      ),
                    
                    const SizedBox(height: 12),
                    
                    // Instruction text
                    StreamBuilder<String>(
                      stream: livenessService.instructionStream,
                      builder: (context, snapshot) {
                        final instruction = snapshot.data ?? "Подготовка...";
                        return Text(
                          instruction,
                          textAlign: TextAlign.center,
                          style: AppFonts.w500s18.copyWith(color: Colors.white),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
          
          const SizedBox(height: 16),
          
          // Action buttons
          StreamBuilder<LivenessState>(
            stream: livenessService.stateStream,
            builder: (context, snapshot) {
              final state = snapshot.data ?? LivenessState.notStarted;
              
              if (state == LivenessState.notStarted) {
                return ElevatedButton(
                  onPressed: onStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Начать проверку', style: TextStyle(fontSize: 16)),
                );
              } else if (state == LivenessState.completed || state == LivenessState.failed) {
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        livenessService.reset();
                        onStart();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30),
                        ),
                      ),
                      child: const Text('Повторить', style: TextStyle(fontSize: 16)),
                    ),
                    const SizedBox(width: 16),
                    if (state == LivenessState.completed)
                      ElevatedButton(
                        onPressed: onCancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: const Text('Продолжить', style: TextStyle(fontSize: 16)),
                      ),
                  ],
                );
              } else {
                return ElevatedButton(
                  onPressed: onCancel,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
                  ),
                  child: const Text('Отмена', style: TextStyle(fontSize: 16)),
                );
              }
            },
          ),
        ],
      ),
    );
  }
} 