import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../../core/models/user_model.dart';

class AuthRepository {
  final Dio _dio = DioClient.create();

  /// Send OTP to phone number.
  ///
  /// [language] — ilova tili ('uz'/'ru'). RO'YXATDAN O'TISHDA kerak:
  /// foydalanuvchi hali serverda yo'q, va SMS tilini faqat ilova biladi.
  /// Berilmasa — server o'zbekchani tanlaydi.
  Future<Map<String, dynamic>> sendOTP({
    required String phone,
    String? language,
  }) async {
    final cleanPhone = getCleanPhoneNumber(phone);

    final response = await _dio.post(
      "/auth/send-otp",
      data: {
        "phone": cleanPhone,
        if (language != null) "language": language,
      },
    );

    return {
      "success": response.data["success"] ?? true,
      "message": response.data["message"] ?? "OTP yuborildi",
      "expires_in": response.data["expires_in"] ?? 300,
    };
  }

  /// Verify OTP code
  Future<Map<String, dynamic>> verifyOTP({
    required String phone,
    required String otpCode,
  }) async {
    final cleanPhone = getCleanPhoneNumber(phone);

    final response = await _dio.post(
      "/auth/verify-otp",
      data: {
        "phone": cleanPhone,
        "otp_code": otpCode,
      },
    );

    return _saveSession(response.data);
  }

  /// Kirish tugagach sessiyani saqlaydi.
  ///
  /// SMS kodi ham, Telegram ham shu yerga keladi: javob tanasi bir xil
  /// (OTPVerifyResponse). Ikki nusxa bo'lsa, biri til yuborishni yoki
  /// rolni saqlashni unutib qoladi — shundan keyin ruscha interfeysdagi
  /// odam o'zbekcha xabarnoma olardi.
  Future<Map<String, dynamic>> _saveSession(dynamic data) async {
    if (data["success"] == true && data["access_token"] != null) {
      final token = data["access_token"];
      final role = data["role"];
      final userId = data["user_id"];

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString("token", token);
      await prefs.setString("role", role);
      await prefs.setInt("user_id", userId);

      // Tanlangan tilni profilga yuboramiz.
      //
      // Til ilova ochilishida, KIRISHDAN OLDIN tanlanadi — o'sha paytda token
      // yo'q, shuning uchun serverga aytib bo'lmaydi. Ilgari til faqat
      // sozlamalardan almashtirilganda yuborilardi, va ruscha interfeysdagi
      // odamning users.language da "uz" bo'lib qolaverardi. Server esa
      // xabarnoma, push va pul harakati izohlarini shu maydonga qarab yozadi
      // — natijada ruscha interfeysda o'zbekcha matn chiqardi.
      //
      // Xato bo'lsa jim o'tamiz: kirish shu sababli buzilmasligi kerak.
      final selectedLanguage = prefs.getString("selected_language");
      if (selectedLanguage != null) {
        try {
          await _dio.put("/users/me", data: {"language": selectedLanguage});
        } catch (_) {
          // til keyingi safar sinxronlanadi
        }
      }

      return {
        "success": true,
        "token": token,
        "role": role,
        "user_id": userId,
      };
    }

    return {
      "success": data["success"] ?? true,
      "message": data["message"] ?? "Tasdiqlandi",
    };
  }

  // ------------------------------------------------ Telegram orqali kirish

  /// Kirishni boshlaydi: t.me havolasi va kuzatish uchun token qaytadi.
  ///
  /// Nega havola. Bot odamga BIRINCHI bo'lib yoza olmaydi va uni telefon
  /// raqami bo'yicha topa olmaydi — bunday API yo'q. Shuning uchun birinchi
  /// qadamni doim odamning o'zi bosadi.
  Future<Map<String, dynamic>> telegramStart() async {
    final response = await _dio.post("/auth/telegram/start");
    return {
      "token": response.data["token"] as String,
      "url": response.data["url"] as String,
      "expires_in": response.data["expires_in"] as int? ?? 600,
    };
  }

  /// Tasdiqlandimi — ilova shu yerni so'rab turadi.
  ///
  /// Tasdiqlangan bo'lsa raqam ham keladi: hisob hali yo'q bo'lsa,
  /// ro'yxatdan o'tish oynasiga aynan shu raqam bilan o'tiladi.
  Future<Map<String, dynamic>> telegramStatus(String token) async {
    final response = await _dio.get(
      "/auth/telegram/status",
      queryParameters: {"token": token},
    );
    return {
      "status": response.data["status"] as String? ?? "not_found",
      "phone": response.data["phone"] as String?,
    };
  }

  /// Tasdiqlangan so'rov bo'yicha kirish.
  ///
  /// Raqam Telegramning O'ZIDAN kelgan, ya'ni tasdiqlangan — SMS kodidan
  /// kam ishonchli emas. Token bir martalik: ikkinchi chaqiriq 400 beradi.
  Future<Map<String, dynamic>> telegramComplete(String token) async {
    final response = await _dio.post(
      "/auth/telegram/complete",
      queryParameters: {"token": token},
    );
    return _saveSession(response.data);
  }

  /// Register new user (phone must be verified first)
  /// No password needed - authentication is done via OTP only
  Future<UserModel> register({
    required String fullName,
    required String phone,
    required String role,
  }) async {
    final cleanPhone = getCleanPhoneNumber(phone);

    final response = await _dio.post(
      "/auth/register",
      data: {
        "full_name": fullName,
        "phone": cleanPhone,
        "password": "dummy", // Backend generates random password
        "role": role,
      },
    );
    return UserModel.fromJson(response.data);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
