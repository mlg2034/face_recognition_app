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
  
  // Dynamic embedding size - will be set based on model output
  int EMBEDDING_SIZE = 192;  // Changed from 512 to 192 for mobile_face_net
  
  // Adjusted threshold based on ROC analysis - made much more strict to prevent false positives
  static const double RECOGNITION_THRESHOLD = 0.15;  // Changed from 0.55 to 0.15 for stricter matching
  
  // Additional confidence threshold for extra security
  static const double HIGH_CONFIDENCE_THRESHOLD = 0.10;  // Very confident match
  static const double MEDIUM_CONFIDENCE_THRESHOLD = 0.15; // Medium confidence match
  
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
    initDB();
  }
  
  initDB() async {
    await dbHelper.database;
    loadRegisteredFaces();
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        modelName,
        options: _interpreterOptions,
      );
      
      // Get the actual output shape from the model
      var outputShape = interpreter.getOutputTensor(0).shape;
      EMBEDDING_SIZE = outputShape[1]; // Should be 192 for mobile_face_net
      
      print('✅ Model loaded successfully');
      print('📐 Model output shape: $outputShape');
      print('📊 Embedding size: $EMBEDDING_SIZE');
    } catch (e) {
      print('Unable to create interpreter, Caught Exception: ${e.toString()}');
    }
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
            
        // Check if embedding dimensions match current model
        if (embd.length != EMBEDDING_SIZE) {
          print('⚠️ Warning: Stored embedding for $name has ${embd.length} dimensions, but model expects $EMBEDDING_SIZE');
          print('🗑️ Clearing incompatible stored embeddings...');
          await clearAllData();
          break; // Exit the loop since we cleared all data
        }
            
        Recognition recognition = Recognition(name, Rect.zero, embd, 0);
        registered[name] = recognition;
      }
      print('✅ Loaded ${registered.length} registered faces');
    } catch (e) {
      print('❌ Error loading faces: $e');
      print('🗑️ Clearing potentially corrupted data...');
      await clearAllData();
      registered.clear();
    }
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
    
    // Dynamic output tensor shape based on actual model - now [1, 192] for mobile_face_net
    var outputs = List<List<double>>.filled(
        1, List<double>.filled(EMBEDDING_SIZE, 0.0));
    
    // Run inference
    Stopwatch stopwatch = Stopwatch()..start();
    interpreter.run(inputs.buffer.asUint8List(), outputs);
    stopwatch.stop();
    print('⚡ Inference time: ${stopwatch.elapsedMilliseconds} ms');
    print('📊 Output embedding size: ${outputs[0].length}');
    
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
    
    // Much more strict recognition logic
    String finalLabel;
    if (lowestDistance <= HIGH_CONFIDENCE_THRESHOLD) {
      // Very confident match
      double confidence = (1 - lowestDistance) * 100;
      finalLabel = "$bestMatch (${confidence.toStringAsFixed(1)}%)";
      logger.i('🔍 FACE RECOGNITION: ✅ HIGH CONFIDENCE - Person: $bestMatch, Distance: ${lowestDistance.toStringAsFixed(4)}');
    } else if (lowestDistance <= MEDIUM_CONFIDENCE_THRESHOLD) {
      // Medium confidence match - be more cautious
      double confidence = (1 - lowestDistance) * 100;
      finalLabel = "$bestMatch (${confidence.toStringAsFixed(1)}%)";
      logger.i('🔍 FACE RECOGNITION: ⚠️ MEDIUM CONFIDENCE - Person: $bestMatch, Distance: ${lowestDistance.toStringAsFixed(4)}');
    } else {
      // Unknown person - distance too high
      finalLabel = "Unknown";
      logger.i('🔍 FACE RECOGNITION: ❌ UNKNOWN - Closest match: $bestMatch, Distance: ${lowestDistance.toStringAsFixed(4)} (threshold: ${RECOGNITION_THRESHOLD})');
    }
    
    // Create recognition with proper distance
    Recognition recognition = Recognition(finalLabel, location, embeddings, lowestDistance);
    
    // Only add to recent embeddings if it's a confident match
    if (lowestDistance <= RECOGNITION_THRESHOLD) {
      _addToRecentEmbeddings(bestMatch, embeddings);
    }
    
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
    
    // Initialize sum array with dynamic size
    List<double> sum = List<double>.filled(EMBEDDING_SIZE, 0.0);
    
    // Sum all embeddings
    for (var embedding in _recentEmbeddings[personId]!) {
      for (int i = 0; i < EMBEDDING_SIZE && i < embedding.length; i++) {
        sum[i] += embedding[i];
      }
    }
    
    // Divide by count to get average
    for (int i = 0; i < EMBEDDING_SIZE; i++) {
      sum[i] /= _recentEmbeddings[personId]!.length;
    }
    
    // Normalize the consolidated embedding
    return _normalizeEmbedding(sum);
  }

  // Check if a user with the given name is already registered
  bool isUserRegistered(String name) {
    return registered.containsKey(name.trim());
  }

  void registerFaceInDB(String name, List<double> embedding) async {
    if (registered.containsKey(name)) {
      var existing = registered[name]!.embeddings;
      
      List<double> averagedEmbedding = [];
      
      if (existing.isNotEmpty) {
        List<double> normalizedNew = _normalizeEmbedding(embedding);
        List<double> normalizedExisting = _normalizeEmbedding(existing);
        
        for (int i = 0; i < normalizedNew.length; i++) {
          double weightedAvg = (normalizedExisting[i] * 0.7) + (normalizedNew[i] * 0.3);
          averagedEmbedding.add(weightedAvg);
        }
        
        averagedEmbedding = _normalizeEmbedding(averagedEmbedding);
      } else {
        averagedEmbedding = _normalizeEmbedding(embedding);
      }
      
      embedding = averagedEmbedding;
    } else {
      embedding = _normalizeEmbedding(embedding);
    }
    
    Map<String, dynamic> row = {
      DatabaseHelper.columnName: name,
      DatabaseHelper.columnEmbedding: embedding.join(",")
    };
    final id = await dbHelper.insert(row);
    print('inserted row id: $id');
    loadRegisteredFaces();
  }

  Future<List<String>> getRegisteredUsers() async {
    return registered.keys.toList();
  }

  Future<void> deleteUser(String userName) async {
    try {
      await dbHelper.delete(userName);
      registered.remove(userName);
    } catch (e) {
      print('Error deleting user: $e');
    }
  }

  Future<void> clearAllData() async {
    try {
      await dbHelper.deleteAll();
      registered.clear();
    } catch (e) {
      print('Error clearing data: $e');
    }
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


