import 'dart:ui';

class Recognition {
  String name;
  Rect location;
  List<double> embeddings;
  double distance;
  double qualityScore;
  
  Recognition(
    this.name, 
    this.location,
    this.embeddings,
    this.distance,
    {this.qualityScore = 0.0}
  );
}
