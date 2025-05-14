import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessCheckType {
  blink,
  headTurn,
  mouthOpen
}

enum LivenessState {
  notStarted,
  inProgress,
  completed,
  failed
}

class LivenessDetectionService {
  LivenessState state = LivenessState.notStarted;
  LivenessCheckType currentCheck = LivenessCheckType.blink;
  List<LivenessCheckType> checkSequence = [
    LivenessCheckType.blink,
    LivenessCheckType.headTurn,
    LivenessCheckType.mouthOpen
  ];
  
  int currentCheckIndex = 0;
  bool leftEyeClosed = false;
  bool rightEyeClosed = false;
  bool headTurnedLeft = false;
  bool headTurnedRight = false;
  bool mouthOpened = false;
  
  int framesWithoutFace = 0;
  int maxFramesWithoutFace = 10; // Max frames allowed without face detection
  
  final StreamController<String> _instructionController = StreamController<String>.broadcast();
  Stream<String> get instructionStream => _instructionController.stream;
  
  final StreamController<LivenessState> _stateController = StreamController<LivenessState>.broadcast();
  Stream<LivenessState> get stateStream => _stateController.stream;
  
  LivenessDetectionService() {
    reset();
  }
  
  void reset() {
    state = LivenessState.notStarted;
    currentCheckIndex = 0;
    currentCheck = checkSequence[currentCheckIndex];
    leftEyeClosed = false;
    rightEyeClosed = false;
    headTurnedLeft = false;
    headTurnedRight = false;
    mouthOpened = false;
    framesWithoutFace = 0;
    _stateController.add(state);
    _instructionController.add("Подготовьтесь к проверке живости");
  }
  
  void start() {
    state = LivenessState.inProgress;
    _stateController.add(state);
    _updateInstructions();
  }
  
  void _updateInstructions() {
    switch (currentCheck) {
      case LivenessCheckType.blink:
        _instructionController.add("Моргните, пожалуйста");
        break;
      case LivenessCheckType.headTurn:
        _instructionController.add("Поверните голову влево, затем вправо");
        break;
      case LivenessCheckType.mouthOpen:
        _instructionController.add("Откройте рот, затем закройте");
        break;
    }
  }
  
  bool processFrame(List<Face> faces) {
    if (state != LivenessState.inProgress) {
      return false;
    }
    
    if (faces.isEmpty) {
      framesWithoutFace++;
      if (framesWithoutFace > maxFramesWithoutFace) {
        _failCheck("Лицо не обнаружено");
      }
      return false;
    }
    
    framesWithoutFace = 0;
    Face face = faces.first;
    
    switch (currentCheck) {
      case LivenessCheckType.blink:
        _processBlink(face);
        break;
      case LivenessCheckType.headTurn:
        _processHeadTurn(face);
        break;
      case LivenessCheckType.mouthOpen:
        _processMouthOpen(face);
        break;
    }
    
    return state == LivenessState.completed;
  }
  
  void _processBlink(Face face) {
    if (face.leftEyeOpenProbability != null && 
        face.rightEyeOpenProbability != null) {
      
      // Check if eyes are closed (probability less than 0.2)
      if (face.leftEyeOpenProbability! < 0.2) {
        leftEyeClosed = true;
      }
      
      if (face.rightEyeOpenProbability! < 0.2) {
        rightEyeClosed = true;
      }
      
      // If both eyes were closed and now they're open again
      if (leftEyeClosed && rightEyeClosed && 
          face.leftEyeOpenProbability! > 0.8 && 
          face.rightEyeOpenProbability! > 0.8) {
        _nextCheck("Моргание обнаружено");
      }
    }
  }
  
  void _processHeadTurn(Face face) {
    if (face.headEulerAngleY != null) {
      // Head turned left (threshold: 25 degrees)
      if (face.headEulerAngleY! < -25) {
        headTurnedLeft = true;
      }
      
      // Head turned right (threshold: 25 degrees)
      if (face.headEulerAngleY! > 25) {
        headTurnedRight = true;
      }
      
      // Once both left and right turns are detected
      if (headTurnedLeft && headTurnedRight) {
        _nextCheck("Поворот головы обнаружен");
      }
    }
  }
  
  void _processMouthOpen(Face face) {
    if (face.smilingProbability != null) {
      // Using smiling probability as a proxy for mouth open
      // A very high smiling probability often means the mouth is open
      if (face.smilingProbability! > 0.8) {
        mouthOpened = true;
      }
      
      // If mouth was opened and now it's closed
      if (mouthOpened && face.smilingProbability! < 0.2) {
        _nextCheck("Движение рта обнаружено");
      }
    }
  }
  
  void _nextCheck(String message) {
    currentCheckIndex++;
    
    if (currentCheckIndex >= checkSequence.length) {
      state = LivenessState.completed;
      _stateController.add(state);
      _instructionController.add("Проверка пройдена успешно!");
    } else {
      currentCheck = checkSequence[currentCheckIndex];
      _instructionController.add(message);
      Future.delayed(const Duration(milliseconds: 1500), () {
        _updateInstructions();
      });
    }
  }
  
  void _failCheck(String reason) {
    state = LivenessState.failed;
    _stateController.add(state);
    _instructionController.add("Проверка не пройдена: $reason");
  }
  
  void dispose() {
    _instructionController.close();
    _stateController.close();
  }
} 