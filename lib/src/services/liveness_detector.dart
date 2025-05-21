import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'dart:math';

enum LivenessChallenge {
  blink,
  turnLeft,
  turnRight,
  nod,
  smile
}

class LivenessDetector {
  int _blinkCount = 0;
  bool _wasLeftEyeOpen = true;
  bool _wasRightEyeOpen = true;
  bool _eyesClosed = false;
  
  // Tracking for smile
  bool _wasSmiling = false;
  bool _smileDetected = false;
  
  // Head movement tracking
  double _startYaw = 0;
  double _startPitch = 0;
  double _startRoll = 0;
  double _minYaw = 0;
  double _maxYaw = 0;
  double _minPitch = 0;
  double _maxPitch = 0;
  bool _headBaselineSet = false;
  
  // Challenge state tracking
  final List<LivenessChallenge> _challengeSequence = [];
  int _currentChallengeIndex = 0;
  bool _isInitialized = false;
  final Map<LivenessChallenge, bool> _completedChallenges = {};
  
  // Timestamps for security
  int _lastChallengeTimestamp = 0;
  static const int CHALLENGE_TIMEOUT_MS = 10000; // 10 seconds
  
  bool get livenessConfirmed => _completedChallenges.values.every((completed) => completed);
  
  LivenessDetector() {
    _initializeSequence();
  }
  
  void _initializeSequence() {
    // Reset
    _isInitialized = true;
    _challengeSequence.clear();
    _completedChallenges.clear();
    
    // Generate random sequence of 2-3 challenges
    final random = Random();
    final availableChallenges = LivenessChallenge.values.toList();
    availableChallenges.shuffle(random);
    
    // Always include blink as the first challenge for security
    _challengeSequence.add(LivenessChallenge.blink);
    
    // Add 1-2 more random challenges
    _challengeSequence.add(availableChallenges[0]);
    if (random.nextBool()) {
      _challengeSequence.add(availableChallenges[1 % availableChallenges.length]);
    }
    
    // Initialize completion status
    for (var challenge in _challengeSequence) {
      _completedChallenges[challenge] = false;
    }
    
    _currentChallengeIndex = 0;
    _lastChallengeTimestamp = DateTime.now().millisecondsSinceEpoch;
  }
  
  // Process face for liveness checks
  bool processFace(Face face) {
    if (!_isInitialized) {
      _initializeSequence();
    }
    
    // Check for timeout and reset if needed
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    if (currentTime - _lastChallengeTimestamp > CHALLENGE_TIMEOUT_MS) {
      print('Challenge timeout, resetting sequence');
      reset();
      return false;
    }
    
    // If all challenges completed, return true
    if (livenessConfirmed) return true;
    
    // Get current challenge
    LivenessChallenge currentChallenge = _challengeSequence[_currentChallengeIndex];
    
    // Process based on current challenge
    bool completed = false;
    switch (currentChallenge) {
      case LivenessChallenge.blink:
        completed = _checkBlinking(face);
        break;
      case LivenessChallenge.turnLeft:
      case LivenessChallenge.turnRight:
        completed = _checkHeadTurn(face, currentChallenge);
        break;
      case LivenessChallenge.nod:
        completed = _checkNod(face);
        break;
      case LivenessChallenge.smile:
        completed = _checkSmile(face);
        break;
    }
    
    // If current challenge completed, move to next
    if (completed && !_completedChallenges[currentChallenge]!) {
      _completedChallenges[currentChallenge] = true;
      _currentChallengeIndex = (_currentChallengeIndex + 1) % _challengeSequence.length;
      _lastChallengeTimestamp = currentTime;
      print('Challenge completed: $currentChallenge');
    }
    
    return livenessConfirmed;
  }
  
  // Improved blinking detection
  bool _checkBlinking(Face face) {
    if (face.leftEyeOpenProbability == null || face.rightEyeOpenProbability == null) {
      return false;
    }
    
    bool isLeftEyeOpen = face.leftEyeOpenProbability! > 0.7;
    bool isRightEyeOpen = face.rightEyeOpenProbability! > 0.7;
    bool eyesOpen = isLeftEyeOpen && isRightEyeOpen;
                     
    // Detect complete blink sequence (open -> closed -> open)
    if (!_eyesClosed && _wasLeftEyeOpen && _wasRightEyeOpen && !isLeftEyeOpen && !isRightEyeOpen) {
      _eyesClosed = true;
    } else if (_eyesClosed && !_wasLeftEyeOpen && !_wasRightEyeOpen && isLeftEyeOpen && isRightEyeOpen) {
      _blinkCount++;
      _eyesClosed = false;
    }
    
    _wasLeftEyeOpen = isLeftEyeOpen;
    _wasRightEyeOpen = isRightEyeOpen;
    
    return _blinkCount >= 2;
  }
  
  // Head turn detection (left or right)
  bool _checkHeadTurn(Face face, LivenessChallenge direction) {
    if (face.headEulerAngleY == null) return false;
    
    double yaw = face.headEulerAngleY!;
    
    if (!_headBaselineSet) {
      _startYaw = yaw;
      _minYaw = yaw;
      _maxYaw = yaw;
      _headBaselineSet = true;
      return false;
  }
  
    // Update min/max values
    if (yaw < _minYaw) _minYaw = yaw;
    if (yaw > _maxYaw) _maxYaw = yaw;
    
    // For turn left, need negative yaw change
    if (direction == LivenessChallenge.turnLeft) {
      return (_startYaw - _minYaw) > 20.0; // At least 20 degrees left
    } 
    // For turn right, need positive yaw change
    else {
      return (_maxYaw - _startYaw) > 20.0; // At least 20 degrees right
    }
  }
  
  // Head nod detection (up and down)
  bool _checkNod(Face face) {
    if (face.headEulerAngleX == null) return false;
    
    double pitch = face.headEulerAngleX!;
    
    if (!_headBaselineSet) {
      _startPitch = pitch;
      _minPitch = pitch;
      _maxPitch = pitch;
      _headBaselineSet = true;
      return false;
    }
    
    // Update min/max values
    if (pitch < _minPitch) _minPitch = pitch;
    if (pitch > _maxPitch) _maxPitch = pitch;
    
    // Need significant change in both directions
    double upwardRange = _maxPitch - _startPitch;
    double downwardRange = _startPitch - _minPitch;
    
    return (upwardRange > 15.0 && downwardRange > 15.0);
  }
  
  // Smile detection
  bool _checkSmile(Face face) {
    if (face.smilingProbability == null) return false;
    
    bool isSmiling = face.smilingProbability! > 0.7;
    
    // Detect transition from not smiling to smiling
    if (!_wasSmiling && isSmiling) {
      _smileDetected = true;
    }
    
    _wasSmiling = isSmiling;
    return _smileDetected;
  }
  
  // Получение текущей инструкции для пользователя
  String getLivenessInstruction() {
    if (!_isInitialized || _challengeSequence.isEmpty) {
      return "Preparing face verification...";
    }
    
    if (livenessConfirmed) {
      return "Liveness confirmed!";
    }
    
    LivenessChallenge currentChallenge = _challengeSequence[_currentChallengeIndex];
    
    switch (currentChallenge) {
      case LivenessChallenge.blink:
        return "Please blink twice";
      case LivenessChallenge.turnLeft:
        return "Turn your head left";
      case LivenessChallenge.turnRight:
        return "Turn your head right";
      case LivenessChallenge.nod:
        return "Nod your head up and down";
      case LivenessChallenge.smile:
        return "Smile for the camera";
      default:
        return "Follow instructions on screen";
    }
  }
  
  // Сброс состояния
  void reset() {
    _blinkCount = 0;
    _wasLeftEyeOpen = true;
    _wasRightEyeOpen = true;
    _eyesClosed = false;
    _wasSmiling = false;
    _smileDetected = false;
    _startYaw = 0;
    _startPitch = 0;
    _startRoll = 0;
    _minYaw = 0;
    _maxYaw = 0;
    _minPitch = 0;
    _maxPitch = 0;
    _headBaselineSet = false;
    _isInitialized = false;
    _initializeSequence();
  }
} 