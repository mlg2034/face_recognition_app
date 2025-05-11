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
    return UserModel(
      name: json['name'],
      id: json['id'],
      embeddings: json['embeddings'],
      entryTime: json['entryTime'],
      exitTime: json['exitTime'],
      deviceId: json['deviceId'],
    );
  }

  Map<String, dynamic> toData() => {
        'name': name,
        'id': id,
        'entryTime': entryTime,
        'exitTime': exitTime,
        'embeddings': embeddings
      };
}
