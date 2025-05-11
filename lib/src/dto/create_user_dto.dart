import 'dart:math';

class CreateUserDTO {
  final String name;
  final List<double> embeddings;
  final int id;

  CreateUserDTO._(
      {required this.name, required this.embeddings, required this.id});

  Map<String, dynamic> toData() => {'name': name, 'embeddings': embeddings , 'id':id};

  static int _generateId() =>
      DateTime.now().microsecondsSinceEpoch ^ Random().nextInt(1 << 16);


  factory CreateUserDTO({
    required String name,
    required List<double>embeddings,
    int?id,
}){
    return CreateUserDTO._(
      name: name,
      embeddings: embeddings,
      id: _generateId()
    );
  }
}
