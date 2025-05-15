import 'dart:math';
import 'package:uuid/uuid.dart';

class CreateUserDTO {
  final String name;
  final List<double> embeddings;
  final String id;

  CreateUserDTO._(
      {required this.name, required this.embeddings, required this.id});

  Map<String, dynamic> toData() => {
    'name': name, 
    'embeddings': embeddings, 
    'id': id,
    'entryTime': DateTime.now().toIso8601String(),
    'exitTime': null,
    'deviceId': 0,
  };

  static String _generateId() => const Uuid().v4();

  factory CreateUserDTO({
    required String name,
    required List<double> embeddings,
    String? id,
  }) {
    return CreateUserDTO._(
      name: name,
      embeddings: embeddings,
      id: id ?? _generateId()
    );
  }
}
