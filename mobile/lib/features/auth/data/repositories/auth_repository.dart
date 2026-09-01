import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/dio_client.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../../core/models/user_model.dart';

class AuthRepository {
  final Dio _dio = DioClient.create();

  /// Send OTP to phone number
  Future<Map<String, dynamic>> sendOTP({required String phone}) async {
    final cleanPhone = getCleanPhoneNumber(phone);

    final response = await _dio.post(
      "/auth/send-otp",
      data: {
        "phone": cleanPhone,
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

    // If verification successful and user exists, save token
    if (response.data["success"] == true && response.data["access_token"] != null) {
      final token = response.data["access_token"];
      final role = response.data["role"];
      final userId = response.data["user_id"];

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
      "success": response.data["success"] ?? true,
      "message": response.data["message"] ?? "Tasdiqlandi",
    };
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
