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
      List<UserModel> users = [];
      
      if (snapshot.exists && snapshot.value != null) {
        final data = snapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((key, value) {
          if (value is Map<dynamic, dynamic>) {
            // Преобразуем Map<dynamic, dynamic> в Map<String, dynamic>
            final Map<String, dynamic> userData = {};
            value.forEach((k, v) {
              userData[k.toString()] = v;
            });
            
            try {
              users.add(UserModel.fromJson(userData));
            } catch (e) {
              print('Error converting user data: $e');
            }
          }
        });
      }
      
      return users;
    } catch (e) {
      print('Failed to get users: $e');
      return [];
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
      List<UserModel> users = [];
      
      if (event.snapshot.exists && event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        
        data.forEach((key, value) {
          if (value is Map<dynamic, dynamic>) {
            // Преобразуем Map<dynamic, dynamic> в Map<String, dynamic>
            final Map<String, dynamic> userData = {};
            value.forEach((k, v) {
              userData[k.toString()] = v;
            });
            
            try {
              users.add(UserModel.fromJson(userData));
            } catch (e) {
              print('Error converting user data in stream: $e');
            }
          }
        });
      }
      
      return users;
    });
  }
}
