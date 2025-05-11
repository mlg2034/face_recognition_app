import 'package:firebase_database/firebase_database.dart';
import 'package:realtime_face_recognition/src/dto/create_user_dto.dart';
import 'package:realtime_face_recognition/src/model/user_model.dart';

class FirebaseDBService {
  final DatabaseReference _database = FirebaseDatabase.instance.ref();
  final String _usersPath = 'users';

  Future<void> addUser(CreateUserDTO createUserDto) async {
    try {
      await _database.child(_usersPath).child(createUserDto.id.toString()).set(createUserDto.toData());
    } catch (e) {
      throw Exception('Failed to add user: $e');
    }
  }

  Future<UserModel?> getUser(String userId) async {
    try {
      final snapshot = await _database.child(_usersPath).child(userId).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<String, dynamic>;
        return UserModel.fromJson(data);
      }
      return null;
    } catch (e) {
      throw Exception('Failed to get user: $e');
    }
  }

  Future<List<UserModel>> getAllUsers() async {
    try {
      final snapshot = await _database.child(_usersPath).get();
      if (snapshot.exists) {
        final data = snapshot.value as Map<String, dynamic>;
        return data.entries.map((entry) {
          final userData = entry.value as Map<String, dynamic>;
          return UserModel.fromJson(userData);
        }).toList();
      }
      return [];
    } catch (e) {
      throw Exception('Failed to get users: $e');
    }
  }

  Future<void> updateUser(UserModel user) async {
    try {
      await _database.child(_usersPath).child(user.id).update(user.toData());
    } catch (e) {
      throw Exception('Failed to update user: $e');
    }
  }

  Future<void> deleteUser(String userId) async {
    try {
      await _database.child(_usersPath).child(userId).remove();
    } catch (e) {
      throw Exception('Failed to delete user: $e');
    }
  }

  Stream<List<UserModel>> usersStream() {
    return _database.child(_usersPath).onValue.map((event) {
      if (event.snapshot.exists) {
        final data = event.snapshot.value as Map<String, dynamic>;
        return data.entries.map((entry) {
          final userData = entry.value as Map<String, dynamic>;
          return UserModel.fromJson(userData);
        }).toList();
      }
      return [];
    });
  }
}
