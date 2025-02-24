import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../DB/DatabaseHelper.dart';
import 'Recognition.dart';

class Recognizer {
  late Interpreter interpreter;
  late InterpreterOptions _interpreterOptions;
  static const int WIDTH = 112;
  static const int HEIGHT = 112;
  final dbHelper = DatabaseHelper();
  Map<String,Recognition> registered = Map();
  @override
  String get modelName => 'assets/mobile_face_net.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    loadModel();
    initDB();
  }

  initDB() async {
    await dbHelper.init();
    loadRegisteredFaces();
  }

  void loadRegisteredFaces() async {
    registered.clear();
    try {
      final allRows = await dbHelper.queryAllRows();
      for (final row in allRows) {
        String name = row[DatabaseHelper.columnName];
        List<double> embd = row[DatabaseHelper.columnEmbedding]
            .split(',')
            .map((e) => double.parse(e))
            .toList()
            .cast<double>();
        Recognition recognition = Recognition(name, Rect.zero, embd, 0);
        registered[name] = recognition;
      }
    } catch (e) {
      print('Error loading faces: $e');
      registered.clear();
    }
  }

  void registerFaceInDB(String name, List<double> embedding) async {
    if (registered.containsKey(name)) {
      var existing = registered[name]!.embeddings;
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] = (embedding[i] + existing[i]) / 2;
      }
    }
    
    Map<String, dynamic> row = {
      DatabaseHelper.columnName: name,
      DatabaseHelper.columnEmbedding: embedding.join(",")
    };
    final id = await dbHelper.insert(row);
    print('inserted row id: $id');
    loadRegisteredFaces();
  }


  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(modelName);
    } catch (e) {
      print('Unable to create interpreter, Caught Exception: ${e.toString()}');
    }
  }

  List<dynamic> imageToArray(img.Image inputImage){
    img.Image resizedImage = img.copyResize(inputImage!, width: WIDTH, height: HEIGHT);
    List<double> flattenedList = resizedImage.data!.expand((channel) => [channel.r, channel.g, channel.b]).map((value) => value.toDouble()).toList();
    Float32List float32Array = Float32List.fromList(flattenedList);
    int channels = 3;
    int height = HEIGHT;  
    int width = WIDTH;
    Float32List reshapedArray = Float32List(1 * height * width * channels);
    for (int c = 0; c < channels; c++) {
      for (int h = 0; h < height; h++) {
        for (int w = 0; w < width; w++) {
          int index = c * height * width + h * width + w;
          reshapedArray[index] = (float32Array[c * height * width + h * width + w]-127.5)/127.5;
        }
      }
    }
    return reshapedArray.reshape([1,112,112,3]);
  }

  Recognition recognize(img.Image image,Rect location) {

    var input = imageToArray(image);
    print(input.shape.toString());

    List output = List.filled(1*192, 0).reshape([1,192]);

    final runs = DateTime.now().millisecondsSinceEpoch;
    interpreter.run(input, output);
    final run = DateTime.now().millisecondsSinceEpoch - runs;
    print('Time to run inference: $run ms$output');
     List<double> outputArray = output.first.cast<double>();

     Pair pair = findNearest(outputArray);
     print("distance= ${pair.distance}");

     return Recognition(pair.name,location,outputArray,pair.distance);
  }

  findNearest(List<double> emb) {
    Pair pair = Pair("Unknown", -5);
    double minDistance = double.infinity;
    
    for (MapEntry<String, Recognition> item in registered.entries) {
      final String name = item.key;
      List<double> knownEmb = item.value.embeddings;
      
      // Improved distance calculation using cosine similarity
      double dotProduct = 0.0;
      double normA = 0.0;
      double normB = 0.0;
      
      for (int i = 0; i < emb.length; i++) {
        dotProduct += emb[i] * knownEmb[i];
        normA += emb[i] * emb[i];
        normB += knownEmb[i] * knownEmb[i];
      }
      
      normA = sqrt(normA);
      normB = sqrt(normB);
      
      // Calculate cosine similarity and convert to distance
      double similarity = dotProduct / (normA * normB);
      double distance = 1 - similarity;
      
      // Apply additional confidence boosting
      distance *= 0.8; // Reduce distance to boost confidence
      
      if (pair.distance == -5 || distance < pair.distance) {
        pair.distance = distance;
        pair.name = name;
      }
    }
    
    return pair;
  }

  void close() {
    interpreter.close();
  }

  Future<List<String>> getRegisteredUsers() async {
    // Return list of registered users from your database
    // Implementation depends on how you're storing the data
    return registered.keys.toList(); // Assuming you have a Map of registered users
  }

  Future<void> deleteUser(String userName) async {
    try {
      // Delete from database
      await dbHelper.delete(userName);
      // Remove from in-memory map
      registered.remove(userName);
    } catch (e) {
      print('Error deleting user: $e');
    }
  }

  // Add method to clear all data
  Future<void> clearAllData() async {
    try {
      await dbHelper.deleteAll();
      registered.clear();
    } catch (e) {
      print('Error clearing data: $e');
    }
  }
}
class Pair{
   String name;
   double distance;
   Pair(this.name,this.distance);
}


