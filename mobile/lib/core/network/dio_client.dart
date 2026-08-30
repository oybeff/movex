import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../main.dart';

class DioClient {
  static Dio create() {
    final dio = Dio(
      BaseOptions(
        baseUrl: "http://192.168.1.101:8000",
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

          // Debug: Token mavjudligini tekshirish
          print("🔑 Request to: ${options.path}");
          print("🔑 Token exists: ${token != null}");
          if (token != null) {
            print("🔑 Token: ${token.substring(0, 20)}...");
            options.headers["Authorization"] = "Bearer $token";
          } else {
            print("⚠️ No token found in SharedPreferences");
          }

          return handler.next(options);
        },
        onError: (DioException e, handler) async {
          print("❌ API Error: ${e.response?.statusCode} - ${e.message}");
          print("❌ Request path: ${e.requestOptions.path}");
          print("❌ Response data: ${e.response?.data}");

          // Agar 401 (Unauthorized) xatosi kelsa
          if (e.response?.statusCode == 401) {
            print("401 Unauthorized - Redirecting to login page");

              // Token va role ma'lumotlarini o'chirish
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              await prefs.remove('role');
              await prefs.remove('user_id');

            // Login sahifasiga yo'naltirish
            // Global appRouter orqali login sahifasiga o'tamiz
            appRouter.go('/login');
          }

          return handler.next(e);
        },
      ),
    );
    dio.interceptors.add(LogInterceptor(
      request: true,
      requestBody: true,
      responseBody: true,
      responseHeader: false,
    ));

    return dio;
  }
}
