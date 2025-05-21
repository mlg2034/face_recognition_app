import 'package:realtime_face_recognition/src/network/response_dto.dart';

import 'network_service.dart';

class TurnstileNetworkService {
  final _networkService = BaseNetworkService();

  Future<ResponseDTO> callTurnstile() async {
    try {
      final response = await _networkService.dio.post('/open');
      return ResponseDTO.fromJson(response.data);
    } catch (exception) {
      throw Exception('failed to get status of turnstile: $exception');
    }
  }
}
