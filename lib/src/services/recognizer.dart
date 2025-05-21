import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:realtime_face_recognition/core/app/database_helper.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:logger/logger.dart';
import 'recognition.dart';

class Recognizer {
  late Interpreter interpreter;
  late InterpreterOptions _interpreterOptions;
  static const int WIDTH = 112;
  static const int HEIGHT = 112;
  final dbHelper = DatabaseHelper();
  Map<String, Recognition> registered = Map();
  
  // Adjusted threshold based on ROC analysis
  static const double RECOGNITION_THRESHOLD = 0.48;
  
  static const int MAX_EMBEDDINGS_PER_PERSON = 5;
  
  // Store a rolling window of recent embeddings for consistency checks
  final Map<String, List<List<double>>> _recentEmbeddings = {};
  
  final logger = Logger(
    filter: ProductionFilter(),
    printer: PrettyPrinter(
      methodCount: 0,
      errorMethodCount: 8,
      lineLength: 120,
      colors: true,
      printEmojis: true,
      printTime: true,
    ),
  );
  
  @override
  String get modelName => 'assets/mobile_face_net.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    
    loadModel();
    _initializeDatabase();
  }
  
  Future<void> _initializeDatabase() async {
    try {
      await dbHelper.database;
      await loadRegisteredFaces();
    } catch (e) {
      print('Error initializing database: $e');
    }
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        modelName,
        options: _interpreterOptions,
      );
      print('*** Loaded model: $modelName ***');
    } catch (e) {
      print('Error loading model: $e');
    }
  }
  
  Future<void> initDB() async {
    registered = await dbHelper.queryAllUsers();
  }

  Future<void> loadRegisteredFaces() async {
    registered = await dbHelper.queryAllUsers();
  }
  
  // Normalize a single embedding vector to unit length
  List<double> _normalizeEmbedding(List<double> embedding) {
    // Calculate L2 norm (Euclidean length)
    double squaredSum = 0.0;
    for (double value in embedding) {
      squaredSum += value * value;
    }
    
    // Avoid division by zero
    double norm = sqrt(squaredSum);
    if (norm < 1e-10) {
      return List<double>.filled(embedding.length, 0.0);
    }
    
    // Divide each element by the norm to get unit vector
    List<double> normalized = List<double>.filled(embedding.length, 0.0);
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }
    
    return normalized;
  }

  // Calculate improved distance between two face embeddings
  double _calculateDistance(List<double> embedding1, List<double> embedding2) {
    // First, ensure both embeddings are normalized to unit length
    final normalized1 = _normalizeEmbedding(embedding1);
    final normalized2 = _normalizeEmbedding(embedding2);
    
    // Calculate cosine similarity (dot product of normalized vectors)
    double dotProduct = 0.0;
    for (int i = 0; i < normalized1.length; i++) {
      dotProduct += normalized1[i] * normalized2[i];
    }
    
    // Clamp dot product to range [-1, 1] to handle numerical errors
    dotProduct = dotProduct.clamp(-1.0, 1.0);
    
    // Convert cosine similarity to distance in range [0, 1]
    // where 0 = identical, 1 = completely different
    double distance = (1.0 - dotProduct) / 2.0;
    
    logger.d('Distance calculated: $distance (cos_sim: $dotProduct)');
    
    return distance;
  }
  
  Float32List _imageToByteList(img.Image image) {
    var convertedBytes = Float32List(1 * WIDTH * HEIGHT * 3);
    var buffer = Float32List.view(convertedBytes.buffer);
    int pixelIndex = 0;

    for (var y = 0; y < HEIGHT; y++) {
      for (var x = 0; x < WIDTH; x++) {
        var pixel = image.getPixel(x, y);
        
        // Normalize pixel values to [-1, 1]
        buffer[pixelIndex++] = (pixel.r - 127.5) / 127.5;
        buffer[pixelIndex++] = (pixel.g - 127.5) / 127.5;
        buffer[pixelIndex++] = (pixel.b - 127.5) / 127.5;
      }
    }
    return convertedBytes;
  }

  List<double> _runInference(img.Image image) {
    if (image.width != WIDTH || image.height != HEIGHT) {
      image = img.copyResize(image, width: WIDTH, height: HEIGHT);
    }
    
    // Preprocess the image
    Float32List inputs = _imageToByteList(image);
    
    // Output tensor shape [1, 512]
    var outputs = List<List<double>>.filled(
        1, List<double>.filled(512, 0.0));
    
    // Run inference
    Stopwatch stopwatch = Stopwatch()..start();
    interpreter.run(inputs.buffer.asUint8List(), outputs);
    stopwatch.stop();
    print('Time to run inference: ${stopwatch.elapsedMilliseconds} ms');
    
    // Normalize the output embedding
    return _normalizeEmbedding(outputs[0]);
  }

  Recognition recognize(img.Image image, Rect location) {
    // Extract face embedding
    List<double> embeddings = _runInference(image);
    
    // No faces registered yet
    if (registered.isEmpty) {
      return Recognition("No faces registered", location, embeddings, 1.0);
    }
    
    // Find best match
    String bestMatch = "Unknown";
    double lowestDistance = double.infinity;
    
    registered.forEach((name, recognition) {
      // First normalize registered embedding
      final normalizedStored = _normalizeEmbedding(recognition.embeddings);
      
      // Calculate distance with proper normalization
      double distance = _calculateDistance(embeddings, normalizedStored);
      
      print('distance= $distance');
      
      if (distance < lowestDistance) {
        lowestDistance = distance;
        bestMatch = name;
      }
    });
    
    logger.i('Best match: $bestMatch, Distance: ${lowestDistance.toStringAsFixed(4)}');
    
    // Create recognition with proper distance
    Recognition recognition = Recognition(lowestDistance < RECOGNITION_THRESHOLD ? bestMatch : "Unknown", 
                                         location, embeddings, lowestDistance);
    
    // If this is a verified match, add to recent embeddings for this person
    if (lowestDistance < RECOGNITION_THRESHOLD) {
      _addToRecentEmbeddings(bestMatch, embeddings);
    }
    
    // Log detailed match report
    logger.i('🔍 FACE RECOGNITION: ${lowestDistance < RECOGNITION_THRESHOLD ? '✅' : '❌'} Person: $bestMatch, Distance: ${lowestDistance.toStringAsFixed(4)}');
    
    return recognition;
  }
  
  // Add embedding to recent embeddings for a person
  void _addToRecentEmbeddings(String personId, List<double> embedding) {
    if (!_recentEmbeddings.containsKey(personId)) {
      _recentEmbeddings[personId] = [];
    }
    
    _recentEmbeddings[personId]!.add(embedding);
    
    // Keep only the most recent 10 embeddings
    if (_recentEmbeddings[personId]!.length > 10) {
      _recentEmbeddings[personId]!.removeAt(0);
    }
  }
  
  // Get a consolidated embedding for a person by averaging recent embeddings
  List<double> _getConsolidatedEmbedding(String personId) {
    if (!_recentEmbeddings.containsKey(personId) || 
        _recentEmbeddings[personId]!.isEmpty) {
      return [];
    }
    
    // Initialize sum array
    List<double> sum = List<double>.filled(512, 0.0);
    
    // Sum all embeddings
    for (var embedding in _recentEmbeddings[personId]!) {
      for (int i = 0; i < 512; i++) {
        sum[i] += embedding[i];
      }
    }
    
    // Divide by count to get average
    for (int i = 0; i < 512; i++) {
      sum[i] /= _recentEmbeddings[personId]!.length;
    }
    
    // Normalize the consolidated embedding
    return _normalizeEmbedding(sum);
  }

  Future<void> registerFaceInDB(String name, List<double> embeddings) async {
    // Normalize embedding before storing
    List<double> normalizedEmbedding = _normalizeEmbedding(embeddings);
    
    // Create a new recognition with dummy location
    Recognition rec = Recognition(name, Rect.zero, normalizedEmbedding, 0.0);
    
    // Register in memory map
    registered[name] = rec;
    
    // Save to database
    await dbHelper.insertUser(name, normalizedEmbedding);
    
    logger.i('✅ Registered new face: $name');
  }

  Future<List<String>> getRegisteredUsers() async {
    List<String> users = registered.keys.toList();
    return users;
  }

  Future<void> clearAllData() async {
    await dbHelper.deleteAllUsers();
    registered.clear();
  }

  Future<void> deleteUser(String name) async {
    await dbHelper.deleteUser(name);
    registered.remove(name);
  }

  void close() {
    interpreter.close();
  }
}

class Pair{
   String name;
   double distance;
   Pair(this.name,this.distance);
}


