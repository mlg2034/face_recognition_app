class ResponseDTO {
  final String status;

  ResponseDTO({required this.status});

  factory ResponseDTO.fromJson(Map<String, dynamic> json) =>
      ResponseDTO(status: json['status']);
}
