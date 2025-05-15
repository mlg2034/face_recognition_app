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
  Map<String, Recognition> registered = {};
  static const double RECOGNITION_THRESHOLD = 0.55;
  
  // Use Float32List for better performance with vector operations
  late Float32List _inputBuffer;
  late Float32List _outputBuffer;
  bool _modelLoaded = false;
  
  @override
  String get modelName => 'assets/mobile_face_net.tflite';

  Recognizer({int? numThreads}) {
    _interpreterOptions = InterpreterOptions();

    if (numThreads != null) {
      _interpreterOptions.threads = numThreads;
    }
    
    // Pre-allocate buffers
    _inputBuffer = Float32List(1 * HEIGHT * WIDTH * 3);
    _outputBuffer = Float32List(1 * 192);
    
    // Initialize database first, then load model and faces
    _initializeDbHelper().then((_) {
      loadModel();
      loadRegisteredFaces();
    });
  }

  Future<void> _initializeDbHelper() async {
    try {
      await dbHelper.init();
      print('Database initialized successfully');
    } catch (e) {
      print('Error initializing database: $e');
      // Rethrow to ensure caller knows initialization failed
      rethrow;
    }
  }

  Future<void> loadRegisteredFaces() async {
    registered.clear();
    try {
      // Ensure database is initialized
      if (!await _isDbInitialized()) {
        await _initializeDbHelper();
      }
      
      // Create map to track already loaded names
      Map<String, bool> loadedNames = {};
      
      // First load from local database for fast access
      final localRows = await dbHelper.queryAllRows();
      for (var row in localRows) {
        final String name = row[DatabaseHelper.columnName];
        final String embeddingStr = row[DatabaseHelper.columnEmbedding];
        try {
          final List<double> embeddings = embeddingStr.split(',').map((e) => double.parse(e)).toList();
          
          Recognition recognition = Recognition(
            name,
            Rect.zero,
            embeddings,
            0
          );
          registered[name] = recognition;
          loadedNames[name] = true;
        } catch (e) {
          // Молчаливая обработка ошибок для повышения производительности
          print('Ошибка парсинга локальных данных: $e');
        }
      }
      
      // Затем загружаем из Firebase и обновляем существующие записи или добавляем новые
      try {
        final users = await _firebaseDBService.getAllUsers();
        
        // Обновляем данные и добавляем недостающие
        for (final user in users) {
          if (user.embeddings.isNotEmpty) {
            Recognition recognition = Recognition(
              user.name, 
              Rect.zero, 
              user.embeddings, 
              0
            );
            registered[user.id] = recognition;
            
            // Также обновляем данные в локальной базе, если их там нет
            if (!loadedNames.containsKey(user.name)) {
              try {
                Map<String, dynamic> row = {
                  DatabaseHelper.columnName: user.name,
                  DatabaseHelper.columnEmbedding: user.embeddings.join(",")
                };
                await dbHelper.insert(row);
                print('Синхронизирован пользователь из Firebase: ${user.name}');
              } catch (e) {
                print('Ошибка синхронизации: $e');
              }
            }
          }
        }
      } catch (e) {
        print('Ошибка загрузки пользователей из Firebase: $e');
      }
    } catch (e) {
      print('Ошибка загрузки лиц: $e');
    }
  }

  Future<bool> _isDbInitialized() async {
    try {
      // Try a simple database operation to check if it's initialized
      await dbHelper.queryRowCount();
      return true;
    } catch (e) {
      print('Database not initialized: $e');
      return false;
    }
  }

  void registerFaceInDB(String name, List<double> embedding) async {
    try {
      // Ensure embedding is valid
      if (embedding.isEmpty) {
        print('Error: Cannot register face with empty embedding');
        return;
      }
      
      // Create a unique ID for each registration to avoid name conflicts
      String registrationId = DateTime.now().millisecondsSinceEpoch.toString() + '_' + name;
      
      // Always normalize the input embedding
      List<double> processedEmbedding = normalizeEmbedding(embedding);
      
      // Check if the face is already registered with a different name
      bool possibleDuplicate = false;
      String? existingName;
      
      // Scan existing faces to detect duplicates
      for (var entry in registered.entries) {
        List<double> existingEmb = entry.value.embeddings;
        if (existingEmb.isEmpty || existingEmb.length != processedEmbedding.length) continue;
        
        // Calculate similarity with existing face
        double similarity = calculateSimilarity(processedEmbedding, existingEmb);
        
        // If very similar to existing face, it might be a duplicate
        if (similarity > 0.8) {
          possibleDuplicate = true;
          existingName = entry.value.name;
          break;
        }
      }
      
      if (possibleDuplicate) {
        print('Warning: This face appears similar to existing user "$existingName"');
        // Continue anyway but log the warning
      }
      
      // Save to local DB for faster access
      Map<String, dynamic> row = {
        DatabaseHelper.columnName: name,
        DatabaseHelper.columnEmbedding: processedEmbedding.join(",")
      };
      await dbHelper.insert(row);
      
      // Save to Firebase
      final createUserDto = CreateUserDTO(
        name: name,
        embeddings: processedEmbedding,
      );
      
      await _firebaseDBService.addUser(createUserDto);
      
      // Update cache in memory with safe ID
      Recognition recognition = Recognition(
        name,
        Rect.zero,
        processedEmbedding,
        0
      );
      registered[createUserDto.id] = recognition;
      
      // Reload all faces to ensure consistency
      await loadRegisteredFaces();
      
      print('Successfully registered face for: $name');
    } catch (e) {
      print('Error registering face: $e');
    }
  }
  
  // Helper method to calculate similarity between two embeddings
  double calculateSimilarity(List<double> embA, List<double> embB) {
    if (embA.length != embB.length) return 0.0;
    
    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;
    
    for (int i = 0; i < embA.length; i++) {
      dotProduct += embA[i] * embB[i];
      normA += embA[i] * embA[i];
      normB += embB[i] * embB[i];
    }
    
    if (normA <= 0 || normB <= 0) return 0.0;
    
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  List<double> normalizeEmbedding(List<double> embedding) {
    double sumSquares = 0.0;
    List<double> normalized = List<double>.filled(embedding.length, 0.0);
    
    // Calculate norm in one pass
    for (int i = 0; i < embedding.length; i++) {
      double val = embedding[i];
      sumSquares += val * val;
    }
    double norm = sqrt(sumSquares);
    
    // Normalize in one pass
    for (int i = 0; i < embedding.length; i++) {
      normalized[i] = embedding[i] / norm;
    }
    
    return normalized;
  }

  Future<void> loadModel() async {
    try {
      interpreter = await Interpreter.fromAsset(
        modelName,
        options: _interpreterOptions,
      );
      
      // Check and print the expected input shape
      var inputTensor = interpreter.getInputTensor(0);
      var outputTensor = interpreter.getOutputTensor(0);
      
      print('Model loaded successfully.');
      print('Input shape: ${inputTensor.shape}');
      print('Output shape: ${outputTensor.shape}');
      
      // Reshape input and output tensors if needed
      if (inputTensor.shape.length != 4) {
        try {
          // Attempt to reshape the input tensor to [1, HEIGHT, WIDTH, 3]
          interpreter.resizeInputTensor(0, [1, HEIGHT, WIDTH, 3]);
          print('Input tensor reshaped to [1, HEIGHT, WIDTH, 3]');
          
          // Allocate tensors after reshaping
          interpreter.allocateTensors();
        } catch (e) {
          print('Failed to reshape input tensor: $e');
        }
      }
      
      _modelLoaded = true;
    } catch (e) {
      print('Error loading model: $e');
      _modelLoaded = false;
    }
  }

  List<dynamic> imageToArray(img.Image inputImage) {
    img.Image resizedImage = img.copyResize(inputImage, width: WIDTH, height: HEIGHT);
    
    // Create a 4D tensor with shape [1, HEIGHT, WIDTH, 3]
    var inputShape = [1, HEIGHT, WIDTH, 3];
    var reshapedInput = Float32List(1 * HEIGHT * WIDTH * 3);
    
    int pixelIndex = 0;
    for (int y = 0; y < HEIGHT; y++) {
      for (int x = 0; x < WIDTH; x++) {
        final pixel = resizedImage.getPixel(x, y);
        reshapedInput[pixelIndex++] = (pixel.r / 127.5) - 1.0;
        reshapedInput[pixelIndex++] = (pixel.g / 127.5) - 1.0;
        reshapedInput[pixelIndex++] = (pixel.b / 127.5) - 1.0;
      }
    }
    
    // Store in _inputBuffer for later reuse
    _inputBuffer = reshapedInput;
    
    // Return a list containing a single tensor with shape [1, HEIGHT, WIDTH, 3]
    return [reshapedInput];
  }

  Recognition recognize(img.Image image, Rect location) {
    if (!_modelLoaded) {
      return Recognition("Model not loaded", location, [], 1.0);
    }
    
    try {
      // Ensure image is the right size
      if (image.width != WIDTH || image.height != HEIGHT) {
        image = img.copyResize(image, width: WIDTH, height: HEIGHT);
      }
      
      // Create input tensor with proper shape [1, HEIGHT, WIDTH, 3]
      Float32List inputBuffer = Float32List(1 * HEIGHT * WIDTH * 3);
      
      int pixelIndex = 0;
      for (int y = 0; y < HEIGHT; y++) {
        for (int x = 0; x < WIDTH; x++) {
          final pixel = image.getPixel(x, y);
          inputBuffer[pixelIndex++] = (pixel.r / 127.5) - 1.0;
          inputBuffer[pixelIndex++] = (pixel.g / 127.5) - 1.0;
          inputBuffer[pixelIndex++] = (pixel.b / 127.5) - 1.0;
        }
      }
      
      // Create output buffer
      Float32List outputBuffer = Float32List(1 * 192);
      
      // Run inference with properly shaped inputs
      try {
        // Reshape input tensor to [1, HEIGHT, WIDTH, 3]
        var inputTensor = interpreter.getInputTensor(0);
        print('Original input shape: ${inputTensor.shape}');
        
        // Try reshaping if needed
        if (inputTensor.shape.length != 4) {
          try {
            interpreter.resizeInputTensor(0, [1, HEIGHT, WIDTH, 3]);
            interpreter.allocateTensors();
            print('Reshaped input tensor to [1, HEIGHT, WIDTH, 3]');
          } catch (e) {
            print('Failed to reshape tensor: $e');
          }
        }
        
        interpreter.run(inputBuffer, outputBuffer);
      } catch (e) {
        print('TFLite error: $e');
        return Recognition("TFLite Error", location, [], 1.0);
      }
      
      // Process the output
      List<double> embeddingsList = [];
      for (int i = 0; i < 192; i++) {
        embeddingsList.add(outputBuffer[i]);
      }
      
      // Normalize the embeddings
      embeddingsList = normalizeEmbedding(embeddingsList);
      
      // Find the nearest match
      Pair pair = findNearest(embeddingsList);
      return Recognition(pair.name, location, embeddingsList, pair.distance);
    } catch (e) {
      print('Error in recognition process: $e');
      return Recognition("Recognition error", location, [], 1.0);
    }
  }

  Pair findNearest(List<double> emb) {
    Pair pair = Pair("Unknown", 1.0);
    double minDistance = 1.0;
    
    // Use stricter threshold for more accurate identification
    double recognitionThreshold = 0.42;  // Lower means stricter matching
    
    // Skip processing if no faces registered
    if (registered.isEmpty) {
      return pair;
    }

    // Cache multiple possible matches to handle edge cases
    final Map<String, double> possibleMatches = {};
    
    for (MapEntry<String, Recognition> item in registered.entries) {
      List<double> knownEmb = item.value.embeddings;
      
      // Skip invalid embeddings
      if (knownEmb.isEmpty || knownEmb.length != emb.length) {
        continue;
      }
      
      // Compute L2 normalized cosine similarity
      double dotProduct = 0.0;
      double normA = 0.0;
      double normB = 0.0;
      
      for (int i = 0; i < emb.length; i++) {
        dotProduct += emb[i] * knownEmb[i];
        normA += emb[i] * emb[i];
        normB += knownEmb[i] * knownEmb[i];
      }
      
      // Avoid division by zero
      if (normA <= 0 || normB <= 0) continue;
      
      normA = sqrt(normA);
      normB = sqrt(normB);
      
      double similarity = dotProduct / (normA * normB);
      double distance = 1.0 - similarity;
      
      // Secondary verification using Euclidean distance
      double euclideanDistSquared = 0.0;
      for (int i = 0; i < emb.length; i++) {
        double diff = emb[i] - knownEmb[i];
        euclideanDistSquared += diff * diff;
      }
      
      // Add to possible matches if the score is reasonable
      if (distance < 0.6 && euclideanDistSquared < 1.2) {
        possibleMatches[item.value.name] = distance;
      }
      
      // Track the best match
      if (distance < minDistance && euclideanDistSquared < 1.0) {
        minDistance = distance;
        pair.distance = distance;
        pair.name = item.value.name;
      }
    }
    
    // If best match is close to threshold, ensure it's significantly better than others
    if (pair.distance > recognitionThreshold * 0.9 && possibleMatches.length > 1) {
      // Get second best match
      String bestName = pair.name;
      double secondBestDistance = 1.0;
      
      for (var entry in possibleMatches.entries) {
        if (entry.key != bestName && entry.value < secondBestDistance) {
          secondBestDistance = entry.value;
        }
      }
      
      // If the difference between best and second best is small, mark as unknown
      if (secondBestDistance - pair.distance < 0.07) {
        pair.name = "Unknown";
      }
    }
    
    // Final threshold check
    if (pair.distance > recognitionThreshold) {
      pair.name = "Unknown";
    }
    
    return pair;
  }

  void close() {
    if (_modelLoaded) {
      interpreter.close();
    }
  }

  Future<List<String>> getRegisteredUsers() async {
    return registered.values.map((recognition) => recognition.name).toList();
  }

  Future<void> deleteUser(String userName) async {
    try {
      // Проверяем, существует ли пользователь локально
      bool deletedFromLocal = false;
      try {
        deletedFromLocal = await dbHelper.deleteByName(userName) > 0;
        print('Удаление из локальной БД: ${deletedFromLocal ? "успешно" : "не найден"}');
      } catch (e) {
        print('Ошибка при удалении из локальной БД: $e');
      }
      
      // Ищем по имени в списке зарегистрированных пользователей
      List<String> userIdsToDelete = [];
      for (var entry in registered.entries) {
        if (entry.value.name == userName) {
          userIdsToDelete.add(entry.key);
        }
      }
      
      // Если нашли такого пользователя, удаляем из Firebase
      if (userIdsToDelete.isNotEmpty) {
        for (String userId in userIdsToDelete) {
          try {
            await _firebaseDBService.deleteUser(userId);
            registered.remove(userId);
            print('Удален пользователь из Firebase: $userId');
          } catch (e) {
            print('Ошибка при удалении из Firebase: $e');
          }
        }
      } else {
        print('Пользователь с именем $userName не найден в кэше');
        
        // Пробуем найти в Firebase по имени
        try {
          final users = await _firebaseDBService.getAllUsers();
          for (final user in users) {
            if (user.name == userName) {
              await _firebaseDBService.deleteUser(user.id);
              print('Удален пользователь из Firebase по имени: ${user.name}');
            }
          }
        } catch (e) {
          print('Ошибка при поиске в Firebase: $e');
        }
      }
      
      // Обновляем кэш данных
      await loadRegisteredFaces();
      
      print('Пользователь $userName успешно удален');
    } catch (e) {
      print('Ошибка при удалении пользователя: $e');
    }
  }

  Future<void> clearAllData() async {
    try {
      final users = await _firebaseDBService.getAllUsers();
      for (final user in users) {
        _firebaseDBService.deleteUser(user.id);
      }
      registered.clear();
    } catch (e) {
      // Silent error handling
    }
  }

  // Метод для проверки и исправления целостности базы данных
  Future<Map<String, dynamic>> validateAndFixDatabase() async {
    Map<String, dynamic> result = {
      'totalRecords': 0,
      'validRecords': 0,
      'invalidRecords': 0,
      'deletedRecords': 0,
      'errors': <String>[],
    };
    
    try {
      // Загружаем все записи из локальной базы данных
      final localRows = await dbHelper.queryAllRows();
      result['totalRecords'] = localRows.length;
      
      int validCount = 0;
      int invalidCount = 0;
      int deletedCount = 0;
      
      // Проверяем каждую запись
      for (var row in localRows) {
        try {
          final String name = row[DatabaseHelper.columnName];
          final String embeddingStr = row[DatabaseHelper.columnEmbedding];
          final int rowId = row[DatabaseHelper.columnId];
          
          // Проверяем, что имя не пустое
          if (name.isEmpty) {
            invalidCount++;
            await dbHelper.delete(rowId.toString());
            deletedCount++;
            continue;
          }
          
          // Проверяем, что эмбеддинг парсится корректно
          try {
            final List<double> embeddings = embeddingStr.split(',').map((e) => double.parse(e)).toList();
            
            // Проверяем размер эмбеддинга (должен быть 192 для MobileFaceNet)
            if (embeddings.length != 192) {
              invalidCount++;
              await dbHelper.delete(rowId.toString());
              deletedCount++;
              continue;
            }
            
            // Проверяем, что значения в эмбеддинге корректные
            bool hasInvalidValues = false;
            for (double value in embeddings) {
              if (value.isNaN || value.isInfinite) {
                hasInvalidValues = true;
                break;
              }
            }
            
            if (hasInvalidValues) {
              invalidCount++;
              await dbHelper.delete(rowId.toString());
              deletedCount++;
              continue;
            }
            
            validCount++;
          } catch (e) {
            // Если эмбеддинг не парсится, удаляем запись
            invalidCount++;
            await dbHelper.delete(rowId.toString());
            deletedCount++;
          }
        } catch (e) {
          result['errors'].add('Ошибка при проверке записи: $e');
        }
      }
      
      // Обновляем результаты
      result['validRecords'] = validCount;
      result['invalidRecords'] = invalidCount;
      result['deletedRecords'] = deletedCount;
      
      // Проверяем Firebase
      try {
        final users = await _firebaseDBService.getAllUsers();
        result['firebaseRecords'] = users.length;
        
        int invalidFirebaseRecords = 0;
        for (final user in users) {
          if (user.embeddings.isEmpty || user.name.isEmpty) {
            invalidFirebaseRecords++;
          }
        }
        result['invalidFirebaseRecords'] = invalidFirebaseRecords;
      } catch (e) {
        result['errors'].add('Ошибка при проверке Firebase: $e');
      }
      
      // Перезагружаем базу данных
      await loadRegisteredFaces();
      
    } catch (e) {
      result['errors'].add('Общая ошибка проверки: $e');
    }
    
    return result;
  }
}

class Pair {
   String name;
   double distance;
   Pair(this.name, this.distance);
}


