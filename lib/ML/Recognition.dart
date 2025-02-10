import 'dart:ui';

class Recognition {
  String name;
  Rect location;
  List<double> embeddings;
  double distance;
  Recognition(this.name, this.location,this.embeddings,this.distance);
}
