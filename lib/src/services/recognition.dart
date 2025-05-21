import 'dart:ui';
import 'dart:math' as math;

class Recognition {
  // Default threshold for face recognition
  static const double DEFAULT_THRESHOLD = 0.48; // Adjusted threshold from ROC analysis
  
  String _label;
  final Rect _location;
  final List<double> _embeddings;
  late double _confidence; // Using late to initialize in constructor
  double _distance;
  double _quality = 0.0;
  
  Recognition(this._label, this._location, this._embeddings, this._distance) {
    // Calculate confidence as inverse of distance (1.0 = perfect match, 0.0 = no match)
    _confidence = (1.0 - _distance) * 100;
    
    // Clamp confidence to 0-100% range
    if (_confidence < 0) _confidence = 0;
    if (_confidence > 100) _confidence = 100;
  }
  
  String get label => _label;
  
  set label(String newLabel) {
    _label = newLabel;
  }
  
  Rect get location => _location;
  
  List<double> get embeddings => _embeddings;
  
  double get confidence => _confidence;
  
  double get distance => _distance;
  
  set distance(double newDistance) {
    _distance = newDistance;
    // Update confidence when distance changes
    _confidence = (1.0 - _distance) * 100;
    // Clamp confidence to 0-100% range
    if (_confidence < 0) _confidence = 0;
    if (_confidence > 100) _confidence = 100;
  }
  
  double get quality => _quality;
  
  set quality(double value) {
    _quality = value;
  }
  
  @override
  String toString() {
    return 'Recognition(label: $_label, confidence: ${_confidence.toStringAsFixed(2)}%, distance: ${_distance.toStringAsFixed(4)}, quality: ${_quality.toStringAsFixed(2)})';
  }
  
  // Calculate cosine distance between two embeddings
  static double calculateCosineDistance(List<double> emb1, List<double> emb2) {
    if (emb1.isEmpty || emb2.isEmpty || emb1.length != emb2.length) {
      return 1.0; // Maximum distance for invalid inputs
    }
    
    double dotProduct = 0.0;
    double norm1 = 0.0;
    double norm2 = 0.0;
    
    for (int i = 0; i < emb1.length; i++) {
      dotProduct += emb1[i] * emb2[i];
      norm1 += emb1[i] * emb1[i];
      norm2 += emb2[i] * emb2[i];
    }
    
    // Avoid division by zero
    if (norm1 <= 0.0 || norm2 <= 0.0) return 1.0;
    
    // Cosine similarity is dot product divided by magnitudes
    double cosineSimilarity = dotProduct / (math.sqrt(norm1) * math.sqrt(norm2));
    
    // Convert to distance (1 - similarity)
    return 1.0 - cosineSimilarity;
  }
}
