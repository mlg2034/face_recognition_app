import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class BaseNetworkService {
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: _AppConstant.baseUrl,
      receiveTimeout: const Duration(seconds: 20),
      contentType: "application/json",
      headers: {
        "Accept": "application/json",
        "Authorization": "Bearer ${_AppConstant.token}"
      },
      connectTimeout: const Duration(seconds: 40),
    ),
  );

  Future<void> setup() async {
    final Interceptors interceptors = dio.interceptors;

    interceptors.clear();

    final LogInterceptor logInterceptor = LogInterceptor(
      requestBody: true,
      responseBody: true,
    );

    final QueuedInterceptorsWrapper headerInterceptors =
    QueuedInterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) =>
          handler.next(options),
      onError: (DioException error, ErrorInterceptorHandler handler) {
        handler.next(error);
      },
      onResponse: (Response response, ResponseInterceptorHandler handler) =>
          handler.next(response),
    );
    interceptors.addAll([if (kDebugMode) logInterceptor, headerInterceptors]);
  }
}

class _AppConstant {
  static const baseUrl = 'http://192.168.1.72:5000';
  static const token = 'TURNSTILE_TOKEN';
}
