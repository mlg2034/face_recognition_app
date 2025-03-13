import 'dart:ui';

class Recognition {
  String name;
  Rect location;
  List<double> embeddings;
  double distance;
  double qualityScore; // Face quality score (0-100)
  
  Recognition(
    this.name, 
    this.location,
    this.embeddings,
    this.distance,
    {this.qualityScore = 0.0}
  );
}
