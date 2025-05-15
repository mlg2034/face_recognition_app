class UserModel {
  final String name;
  final String id;
  final DateTime? entryTime;
  final DateTime? exitTime;
  final List<double> embeddings;
  final int deviceId;

  UserModel(
      {required this.name,
      required this.id,
      required this.embeddings,
      required this.entryTime,
      required this.exitTime,
      required this.deviceId});

  factory UserModel.fromJson(Map<String, dynamic> json) {
    // Преобразование поля embeddings из JSON в List<double>
    List<double> embeddings = [];
    if (json['embeddings'] != null) {
      // Если это уже список
      if (json['embeddings'] is List) {
        embeddings = (json['embeddings'] as List)
            .map((item) => item is double ? item : double.parse(item.toString()))
            .toList();
      } 
      // Если это Map (часто Firebase возвращает списки как Map с числовыми ключами)
      else if (json['embeddings'] is Map) {
        final Map<dynamic, dynamic> embMap = json['embeddings'] as Map;
        embeddings = embMap.values
            .map((item) => item is double ? item : double.parse(item.toString()))
            .toList();
      }
    }

    return UserModel(
      name: json['name'] ?? '',
      id: json['id'] ?? '',
      embeddings: embeddings,
      entryTime: json['entryTime'] != null 
          ? DateTime.parse(json['entryTime']) 
          : null,
      exitTime: json['exitTime'] != null 
          ? DateTime.parse(json['exitTime']) 
          : null,
      deviceId: json['deviceId'] ?? 0,
    );
  }

  Map<String, dynamic> toData() => {
        'name': name,
        'id': id,
        'entryTime': entryTime?.toIso8601String(),
        'exitTime': exitTime?.toIso8601String(),
        'embeddings': embeddings,
        'deviceId': deviceId,
      };
}
