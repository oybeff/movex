import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/dio_client.dart';
import '../models/user_model.dart';

class AuthService {
  final Dio _dio = DioClient.create();

  /// Register yangi foydalanuvchi
  Future<UserModel> register({
    required String fullName,
    required String role,
    required String password,
    String? email,
    String? phone,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/register',
        data: UserCreateModel(
          fullName: fullName,
          email: email,
          phone: phone,
          role: role,
          password: password,
        ).toJson(),
      );

      return UserModel.fromJson(response.data);
    } catch (e) {
      print('Register error: $e');
      rethrow;
    }
  }

  /// Login qilish
  Future<Map<String, dynamic>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        '/auth/login',
        data: {
          'username': username,
          'password': password,
        },
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final token = response.data['access_token'] as String;
      final tokenType = response.data['token_type'] as String;

      // Token'ni saqlash
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('token', token);
      await prefs.setString('token_type', tokenType);

      return response.data;
    } catch (e) {
      print('Login error: $e');
      rethrow;
    }
  }

  /// Logout qilish
  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('token_type');
    await prefs.remove('user_id');
    await prefs.remove('user_role');
  }

  /// Token mavjudligini tekshirish
  Future<bool> isAuthenticated() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    return token != null && token.isNotEmpty;
  }

  /// Joriy foydalanuvchi ma'lumotlarini olish
  Future<UserModel?> getCurrentUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getInt('user_id');
      
      if (userId == null) return null;

      final response = await _dio.get('/users/$userId');
      return UserModel.fromJson(response.data);
    } catch (e) {
      print('Get current user error: $e');
      return null;
    }
  }

  /// User ID ni saqlash
  Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
  }

  /// User role ni saqlash
  Future<void> saveUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_role', role);
  }

  /// User ID ni olish
  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  /// User role ni olish
  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_role');
  }
}

