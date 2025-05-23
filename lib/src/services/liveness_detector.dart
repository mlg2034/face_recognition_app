import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

enum LivenessChallenge {
  blink,
  slightTurn,  // Much smaller movement
  verify       // Just hold still
}

class LivenessDetector {
  int _blinkCount = 0;
  bool _wasLeftEyeOpen = true;
  bool _wasRightEyeOpen = true;
  bool _eyesClosed = false;
  
  // Minimal movement tracking
  double _baselineYaw = 0;
  bool _baselineSet = false;
  bool _movementDetected = false;
  int _steadyFrameCount = 0;
  
  // Simplified challenge state
  int _currentStep = 0;
  final List<String> _instructions = [
    "Look directly at the camera",
    "Blink twice slowly", 
    "Turn head slightly left or right",
    "Hold still for verification"
  ];
  
  bool _isCompleted = false;
  int _lastUpdateTime = 0;
  
  bool get livenessConfirmed => _isCompleted;
  
  LivenessDetector() {
    reset();
  }
  
  // Much simpler liveness check focused on frontal detection
  bool processFace(Face face) {
    int currentTime = DateTime.now().millisecondsSinceEpoch;
    
    // If already completed, stay completed for a while
    if (_isCompleted) {
      return true;
    }
    
    switch (_currentStep) {
      case 0: // Initial setup
        _establishBaseline(face);
        if (_baselineSet) {
          _currentStep = 1;
          _lastUpdateTime = currentTime;
        }
        break;
        
      case 1: // Blink detection
        if (_checkSimpleBlink(face)) {
          print('✅ Blink detected! Moving to next step.');
          _currentStep = 2;
          _lastUpdateTime = currentTime;
        }
        break;
        
      case 2: // Minimal movement
        if (_checkMinimalMovement(face)) {
          print('✅ Slight movement detected! Moving to verification.');
          _currentStep = 3;
          _lastUpdateTime = currentTime;
          _steadyFrameCount = 0;
        }
        break;
        
      case 3: // Hold steady for verification
        if (_checkSteadiness(face)) {
          _steadyFrameCount++;
          if (_steadyFrameCount > 30) { // About 1 second at 30fps
            print('✅ Liveness verification completed!');
            _isCompleted = true;
            return true;
          }
        } else {
          _steadyFrameCount = 0; // Reset if not steady
        }
        break;
    }
    
    return false;
  }
  
  void _establishBaseline(Face face) {
    if (face.headEulerAngleY != null) {
      _baselineYaw = face.headEulerAngleY!;
      _baselineSet = true;
      print('📐 Baseline established: Yaw ${_baselineYaw.toStringAsFixed(1)}°');
    }
  }
  
  // Much more lenient blink detection
  bool _checkSimpleBlink(Face face) {
    if (face.leftEyeOpenProbability == null || face.rightEyeOpenProbability == null) {
      return false;
    }
    
    // More lenient eye open thresholds
    bool isLeftEyeOpen = face.leftEyeOpenProbability! > 0.5;  // Was 0.7
    bool isRightEyeOpen = face.rightEyeOpenProbability! > 0.5; // Was 0.7
    
    // Detect blink (both eyes closed, then both open)
    if (!_eyesClosed && _wasLeftEyeOpen && _wasRightEyeOpen && !isLeftEyeOpen && !isRightEyeOpen) {
      _eyesClosed = true;
      print('👁️ Eyes closed');
    } else if (_eyesClosed && !_wasLeftEyeOpen && !_wasRightEyeOpen && isLeftEyeOpen && isRightEyeOpen) {
      _blinkCount++;
      _eyesClosed = false;
      print('👁️ Blink #$_blinkCount detected');
    }
    
    _wasLeftEyeOpen = isLeftEyeOpen;
    _wasRightEyeOpen = isRightEyeOpen;
    
    return _blinkCount >= 1; // Only need 1 blink instead of 2
  }
  
  // Very minimal movement detection - just need to show the face can move
  bool _checkMinimalMovement(Face face) {
    if (!_baselineSet || face.headEulerAngleY == null) {
      return false;
    }
    
    double currentYaw = face.headEulerAngleY!;
    double yawDifference = (currentYaw - _baselineYaw).abs();
    
    // Very small movement requirement - just 8 degrees
    if (yawDifference > 8.0 && !_movementDetected) {
      _movementDetected = true;
      print('🔄 Minimal movement detected: ${yawDifference.toStringAsFixed(1)}° difference');
      return true;
    }
    
    return _movementDetected;
  }
  
  // Check if face is steady (not moving much)
  bool _checkSteadiness(Face face) {
    if (!_baselineSet || face.headEulerAngleY == null) {
      return false;
    }
    
    double currentYaw = face.headEulerAngleY!;
    double yawDifference = (currentYaw - _baselineYaw).abs();
    
    // Face should be relatively steady (within 10 degrees of baseline)
    return yawDifference < 10.0;
  }
  
  // Get current instruction for user
  String getLivenessInstruction() {
    if (_isCompleted) {
      return "✅ Verification complete!";
    }
    
    if (_currentStep < _instructions.length) {
      return _instructions[_currentStep];
    }
    
    return "Processing...";
  }
  
  // Get progress as percentage
  double getProgress() {
    if (_isCompleted) return 1.0;
    return _currentStep / 4.0;
  }
  
  // Reset everything
  void reset() {
    _blinkCount = 0;
    _wasLeftEyeOpen = true;
    _wasRightEyeOpen = true;
    _eyesClosed = false;
    _baselineYaw = 0;
    _baselineSet = false;
    _movementDetected = false;
    _steadyFrameCount = 0;
    _currentStep = 0;
    _isCompleted = false;
    _lastUpdateTime = DateTime.now().millisecondsSinceEpoch;
    print('🔄 Liveness detector reset');
  }
  
  // Simple check if face is looking roughly forward
  bool isFacingForward(Face face) {
    if (face.headEulerAngleY == null || face.headEulerAngleX == null) {
      return true; // Assume yes if we can't detect angles
    }
    
    // Very lenient forward-facing check
    bool facingForward = face.headEulerAngleY!.abs() < 30 && 
                        face.headEulerAngleX!.abs() < 30;
    
    return facingForward;
  }
} 