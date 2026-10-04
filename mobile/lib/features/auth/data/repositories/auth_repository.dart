import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/phone_input_field.dart';

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
  /// Kirish ham, ro'yxatdan o'tish ham shu yerga keladi: javob tanasi
  /// bir xil (OTPVerifyResponse). Ikki nusxa bo'lsa, biri rolni yoki
  /// tilni saqlashni unutib qoladi.
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

  /// Register new user (phone must be verified first)
  /// No password needed - authentication is done via OTP only
  /// Ro'yxatdan o'tish. Javobda DARHOL kirish tokeni keladi.
  ///
  /// Ilgari bu yer foydalanuvchini qaytarardi va ilova odamni qaytadan
  /// kirish ekraniga olib borardi — SMS ikki marta so'ralardi. Endi kod
  /// bir marta keladi, token esa shu javobdan saqlanadi.
  Future<Map<String, dynamic>> register({
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
    return _saveSession(response.data);
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
