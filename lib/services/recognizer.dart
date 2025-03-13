import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import '../core/app/database_helper.dart';
import 'recognition.dart';

class Recognizer {
  late Interpreter interpreter;
  late InterpreterOptions _interpreterOptions;
  static const int WIDTH = 112;
  static const int HEIGHT = 112;
  final dbHelper = DatabaseHelper();
  Map<String,Recognition> registered = Map();
  
  // Threshold for face recognition - lower value means stricter matching
  static const double RECOGNITION_THRESHOLD = 0.55;
  
  // Number of embeddings to average for each person
  static const int MAX_EMBEDDINGS_PER_PERSON = 5;
  
  @override
  String get modelName => 'assets/mobile_face_net.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    
    // Set additional options for better performance if needed
    // Note: Some options might not be available in all versions of tflite_flutter
    
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
      
      // Improved embedding averaging for better recognition
      List<double> averagedEmbedding = [];
      
      // If we have existing embeddings, average them with the new one
      if (existing.isNotEmpty) {
        // Normalize both embeddings before averaging
        List<double> normalizedNew = normalizeEmbedding(embedding);
        List<double> normalizedExisting = normalizeEmbedding(existing);
        
        // Calculate weighted average (giving more weight to existing embeddings)
        for (int i = 0; i < normalizedNew.length; i++) {
          double weightedAvg = (normalizedExisting[i] * 0.7) + (normalizedNew[i] * 0.3);
          averagedEmbedding.add(weightedAvg);
        }
        
        // Re-normalize the averaged embedding
        averagedEmbedding = normalizeEmbedding(averagedEmbedding);
      } else {
        // If no existing embedding, just use the new one (normalized)
        averagedEmbedding = normalizeEmbedding(embedding);
      }
      
      embedding = averagedEmbedding;
    } else {
      // For new faces, normalize the embedding
      embedding = normalizeEmbedding(embedding);
    }
    
    Map<String, dynamic> row = {
      DatabaseHelper.columnName: name,
      DatabaseHelper.columnEmbedding: embedding.join(",")
    };
    final id = await dbHelper.insert(row);
    print('inserted row id: $id');
    loadRegisteredFaces();
  }

  // Helper method to normalize an embedding vector
  List<double> normalizeEmbedding(List<double> embedding) {
    // Calculate the L2 norm (Euclidean length) of the embedding
    double sumSquares = 0.0;
    for (double val in embedding) {
      sumSquares += val * val;
    }
    double norm = sqrt(sumSquares);
    
    // Normalize the embedding by dividing each element by the norm
    List<double> normalized = [];
    for (double val in embedding) {
      normalized.add(val / norm);
    }
    
    return normalized;
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        modelName,
        options: _interpreterOptions,
      );
      print('MobileFaceNet model loaded successfully');
    } catch (e) {
      print('Unable to create interpreter, Caught Exception: ${e.toString()}');
    }
  }

  List<dynamic> imageToArray(img.Image inputImage){
    // Resize image to model input size
    img.Image resizedImage = img.copyResize(inputImage, width: WIDTH, height: HEIGHT);
    
    // Convert to float array with proper normalization
    List<double> flattenedList = [];
    
    // Improved normalization for better model performance
    for (int y = 0; y < HEIGHT; y++) {
      for (int x = 0; x < WIDTH; x++) {
        final pixel = resizedImage.getPixel(x, y);
        // Normalize to [-1, 1] range as expected by MobileFaceNet
        flattenedList.add((pixel.r / 127.5) - 1.0);
        flattenedList.add((pixel.g / 127.5) - 1.0);
        flattenedList.add((pixel.b / 127.5) - 1.0);
      }
    }
    
    Float32List float32Array = Float32List.fromList(flattenedList);
    return float32Array.reshape([1, HEIGHT, WIDTH, 3]);
  }

  Recognition recognize(img.Image image, Rect location) {
    var input = imageToArray(image);
    
    // Prepare output tensor
    List output = List.filled(1*192, 0).reshape([1,192]);

    // Run inference
    final runs = DateTime.now().millisecondsSinceEpoch;
    interpreter.run(input, output);
    final run = DateTime.now().millisecondsSinceEpoch - runs;
    print('Time to run inference: $run ms');
    
    // Get output embedding
    List<double> outputArray = output.first.cast<double>();
    
    // Normalize the output embedding for better matching
    outputArray = normalizeEmbedding(outputArray);

    // Find the nearest match
    Pair pair = findNearest(outputArray);
    print("distance= ${pair.distance}");

    return Recognition(pair.name, location, outputArray, pair.distance);
  }

  findNearest(List<double> emb) {
    Pair pair = Pair("Unknown", -5);
    double minDistance = double.infinity;
    
    for (MapEntry<String, Recognition> item in registered.entries) {
      final String name = item.key;
      List<double> knownEmb = item.value.embeddings;
      
      // Calculate cosine similarity
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
      
      if (pair.distance == -5 || distance < pair.distance) {
        pair.distance = distance;
        pair.name = name;
      }
    }
    
    // Apply threshold for unknown faces
    if (pair.distance > RECOGNITION_THRESHOLD) {
      pair.name = "Unknown";
    }
    
    return pair;
  }

  void close() {
    interpreter.close();
  }

  Future<List<String>> getRegisteredUsers() async {
    // Return list of registered users from your database
    return registered.keys.toList();
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


