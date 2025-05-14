import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:realtime_face_recognition/src/dto/create_user_dto.dart';
import 'package:realtime_face_recognition/src/model/user_model.dart';
import 'package:realtime_face_recognition/src/services/firebase_db_service.dart';
import 'package:realtime_face_recognition/core/app/database_helper.dart';
import 'recognition.dart';

class Recognizer {
  late Interpreter interpreter;
  late InterpreterOptions _interpreterOptions;
  static const int WIDTH = 112;
  static const int HEIGHT = 112;
  final FirebaseDBService _firebaseDBService = FirebaseDBService();
  final DatabaseHelper dbHelper = DatabaseHelper();
  Map<String, Recognition> registered = Map();
  static const double RECOGNITION_THRESHOLD = 0.55;
  
  static const int MAX_EMBEDDINGS_PER_PERSON = 5;
  
  @override
  String get modelName => 'assets/mobile_face_net.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    
    loadModel();
    _initializeDbHelper();
    loadRegisteredFaces();
  }

  Future<void> _initializeDbHelper() async {
    await dbHelper.init();
  }

  Future<void> loadRegisteredFaces() async {
    registered.clear();
    try {
      // Load from local database
      final localRows = await dbHelper.queryAllRows();
      for (var row in localRows) {
        final String name = row[DatabaseHelper.columnName];
        final String embeddingStr = row[DatabaseHelper.columnEmbedding];
        final List<double> embeddings = embeddingStr.split(',').map((e) => double.parse(e)).toList();
        
        Recognition recognition = Recognition(
          name,
          Rect.zero,
          embeddings,
          0
        );
        registered[name] = recognition;
      }
      
      // Also refresh from Firebase
      final users = await _firebaseDBService.getAllUsers();
      for (final user in users) {
        Recognition recognition = Recognition(
          user.name, 
          Rect.zero, 
          user.embeddings, 
          0
        );
        registered[user.id] = recognition;
      }
    } catch (e) {
      print('Error loading faces: $e');
      registered.clear();
    }
  }

  void registerFaceInDB(String name, List<double> embedding) async {
    try {
      // Process embedding for local DB
      List<double> processedEmbedding;
      if (registered.containsKey(name)) {
        var existing = registered[name]!.embeddings;
        
        List<double> averagedEmbedding = [];
        
        if (existing.isNotEmpty) {
          List<double> normalizedNew = normalizeEmbedding(embedding);
          List<double> normalizedExisting = normalizeEmbedding(existing);
          
          for (int i = 0; i < normalizedNew.length; i++) {
            double weightedAvg = (normalizedExisting[i] * 0.7) + (normalizedNew[i] * 0.3);
            averagedEmbedding.add(weightedAvg);
          }
          
          averagedEmbedding = normalizeEmbedding(averagedEmbedding);
        } else {
          averagedEmbedding = normalizeEmbedding(embedding);
        }
        
        processedEmbedding = averagedEmbedding;
      } else {
        processedEmbedding = normalizeEmbedding(embedding);
      }
      
      // Save to local SQLite database
      Map<String, dynamic> row = {
        DatabaseHelper.columnName: name,
        DatabaseHelper.columnEmbedding: processedEmbedding.join(",")
      };
      final localId = await dbHelper.insert(row);
      print('Inserted row id in local DB: $localId');
      
      // Create user DTO for Firebase
      final createUserDto = CreateUserDTO(
        name: name,
        embeddings: processedEmbedding,
      );
      
      // Save to Firebase
      await _firebaseDBService.addUser(createUserDto);
      print('User registered in Firebase with ID: ${createUserDto.id}');
      
      // Update local cache
      await loadRegisteredFaces();
    } catch (e) {
      print('Error registering face: $e');
    }
  }

  List<double> normalizeEmbedding(List<double> embedding) {
    double sumSquares = 0.0;
    for (double val in embedding) {
      sumSquares += val * val;
    }
    double norm = sqrt(sumSquares);
    
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
    img.Image resizedImage = img.copyResize(inputImage, width: WIDTH, height: HEIGHT);
    
    List<double> flattenedList = [];
    
    for (int y = 0; y < HEIGHT; y++) {
      for (int x = 0; x < WIDTH; x++) {
        final pixel = resizedImage.getPixel(x, y);
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
    
    List output = List.filled(1*192, 0).reshape([1,192]);

    final runs = DateTime.now().millisecondsSinceEpoch;
    interpreter.run(input, output);
    final run = DateTime.now().millisecondsSinceEpoch - runs;
    print('Time to run inference: $run ms');
    
    List<double> outputArray = output.first.cast<double>();
    
    outputArray = normalizeEmbedding(outputArray);

    Pair pair = findNearest(outputArray);
    print("distance= ${pair.distance}");

    return Recognition(pair.name, location, outputArray, pair.distance);
  }

  findNearest(List<double> emb) {
    Pair pair = Pair("Unknown", -5);

    for (MapEntry<String, Recognition> item in registered.entries) {
      final String id = item.key;
      List<double> knownEmb = item.value.embeddings;
      
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
      
      double similarity = dotProduct / (normA * normB);
      double distance = 1 - similarity;
      
      if (pair.distance == -5 || distance < pair.distance) {
        pair.distance = distance;
        pair.name = item.value.name; // Use the name from Recognition
      }
    }
    
    if (pair.distance > RECOGNITION_THRESHOLD) {
      pair.name = "Unknown";
    }
    
    return pair;
  }

  void close() {
    interpreter.close();
  }

  Future<List<String>> getRegisteredUsers() async {
    await loadRegisteredFaces(); // Refresh from Firebase
    return registered.values.map((recognition) => recognition.name).toList();
  }

  Future<void> deleteUser(String userName) async {
    try {
      // Find user ID by name
      String? userId;
      for (var entry in registered.entries) {
        if (entry.value.name == userName) {
          userId = entry.key;
          break;
        }
      }
      
      if (userId != null) {
        await _firebaseDBService.deleteUser(userId);
        registered.remove(userId);
      }
    } catch (e) {
      print('Error deleting user: $e');
    }
  }

  Future<void> clearAllData() async {
    try {
      // Get all users and delete them one by one
      final users = await _firebaseDBService.getAllUsers();
      for (final user in users) {
        await _firebaseDBService.deleteUser(user.id);
      }
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


