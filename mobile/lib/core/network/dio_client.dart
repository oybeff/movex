import '../widgets/session_expired_dialog.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../constants/app_config.dart';
import '../../main.dart';

bool _sessionDialogShown = false;

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

          // 403 с X-Account-Blocked — администратор заблокировал аккаунт.
          // Раньше приложение молча показывало «?» и прочерки.
          final blocked = e.response?.statusCode == 403 &&
              e.response?.headers.value('x-account-blocked') == '1';
          String? reason;
          if (blocked) {
            final data = e.response?.data;
            reason = data is Map ? data['detail']?.toString() : null;
          }

          // 401 — token yaroqsiz: seansni tozalab, kirish sahifasiga
          if (e.response?.statusCode == 401 || blocked) {
            final prefs = await SharedPreferences.getInstance();
            final hadSession = prefs.getString('token') != null;
            await prefs.remove('token');
            await prefs.remove('role');
            await prefs.remove('user_id');

            // U1 «Qayta kirish kerak»: человек должен понять, почему его
            // выкинуло, а не оказаться на входе молча. Окно одно, даже если
            // разом упали несколько запросов.
            final ctx = appRouter.routerDelegate.navigatorKey.currentContext;
            if (hadSession && ctx != null && ctx.mounted && !_sessionDialogShown) {
              _sessionDialogShown = true;
              // ignore: use_build_context_synchronously
              await showSessionExpiredDialog(ctx, blockedReason: blocked ? (reason ?? '') : null);
              _sessionDialogShown = false;
            }
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
