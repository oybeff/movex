import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_config.dart';
import '../../main.dart';

class DioClient {
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        // Manzil yig'ish vaqtida beriladi (--dart-define=API_BASE_URL=...).
        // Ilgari bu yerda dasturchining uy IP si turardi.
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          "Content-Type": "application/json",
          "accept": "application/json",
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final prefs = await SharedPreferences.getInstance();
          final token = prefs.getString("token");

          if (token != null) {
            options.headers["Authorization"] = "Bearer $token";
          }

          // Tokenning bir qismini ham jurnalga yozmaymiz: qurilma
          // jurnallari boshqa ilovalar va crash-hisobotlarga tushadi.
          if (kDebugMode) {
            debugPrint('→ ${options.method} ${options.path}');
          }

          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          if (kDebugMode) {
            debugPrint('✕ ${e.response?.statusCode} ${e.requestOptions.path}');
          }

          // 401 — token yaroqsiz: seansni tozalab, kirish sahifasiga
          if (e.response?.statusCode == 401) {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('token');
            await prefs.remove('role');
            await prefs.remove('user_id');

            appRouter.go('/login');
          }

          return handler.next(e);
        },
      ),
    );

    // To'liq jurnal — so'rov va javob tanasi bilan. Faqat qo'lda yoqilganda
    // va faqat debug yig'ilmada: reliz ilovada bu foydalanuvchi ma'lumotlarini
    // qurilma jurnaliga chiqarib yuboradi.
    if (kDebugMode && AppConfig.verboseNetworkLog) {
      dio.interceptors.add(
        LogInterceptor(
          request: true,
          requestBody: true,
          responseBody: true,
          responseHeader: false,
        ),
      );
    }

    return dio;
  }
}
