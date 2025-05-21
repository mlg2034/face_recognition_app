import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path_provider/path_provider.dart';
import 'package:realtime_face_recognition/src/services/recognition.dart';
import 'dart:ui';

class DatabaseHelper {
  static final _databaseName = "FaceDB.db";
  static final _databaseVersion = 1;

  static final table = 'users';
  static final columnId = 'id';
  static final columnName = 'name';
  static final columnEmbedding = 'embedding';

  // Singleton pattern
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  // Database reference
  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  // Initialize the database
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), _databaseName);
    return await openDatabase(
      path,
      version: _databaseVersion,
      onCreate: _onCreate,
    );
  }

  // Create the database table
  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE $table (
        $columnId INTEGER PRIMARY KEY AUTOINCREMENT,
        $columnName TEXT NOT NULL,
        $columnEmbedding TEXT NOT NULL
      )
    ''');
  }

  // Insert a user into the database
  Future<int> insertUser(String name, List<double> embedding) async {
    Database db = await database;
    
    // First check if user exists and delete if it does
    await db.delete(
      table,
      where: '$columnName = ?',
      whereArgs: [name],
    );
    
    // Now insert the new embedding
    Map<String, dynamic> row = {
      columnName: name,
      columnEmbedding: embedding.join(','),
    };
    
    return await db.insert(table, row);
  }

  // Retrieve all users with their embeddings
  Future<Map<String, Recognition>> queryAllUsers() async {
    Database db = await database;
    
    final List<Map<String, dynamic>> maps = await db.query(table);
    
    Map<String, Recognition> users = {};
    
    for (var map in maps) {
      String name = map[columnName];
      List<double> embedding = map[columnEmbedding]
          .split(',')
          .map<double>((e) => double.parse(e))
          .toList();
      
      // Create a Recognition object for each user
      Recognition recognition = Recognition(
        name,
        Rect.zero, // Dummy location since we're just storing embeddings
        embedding,
        0.0 // Default distance
      );
      
      users[name] = recognition;
    }
    
    return users;
  }

  // Delete a user by name
  Future<int> deleteUser(String name) async {
    Database db = await database;
    
    return await db.delete(
      table,
      where: '$columnName = ?',
      whereArgs: [name],
    );
  }

  // Delete all users
  Future<int> deleteAllUsers() async {
    Database db = await database;
    return await db.delete(table);
  }

  // Query all rows in the database (old method kept for compatibility)
  Future<List<Map<String, dynamic>>> queryAllRows() async {
    Database db = await database;
    return await db.query(table);
  }

  // Insert a row (old method kept for compatibility)
  Future<int> insert(Map<String, dynamic> row) async {
    Database db = await database;
    return await db.insert(table, row);
  }

  // Delete by name (old method kept for compatibility)
  Future<int> delete(String name) async {
    Database db = await database;
    return await db.delete(
      table,
      where: '$columnName = ?',
      whereArgs: [name],
    );
  }

  // Delete all rows (old method kept for compatibility)
  Future<int> deleteAll() async {
    Database db = await database;
    return await db.delete(table);
  }
}