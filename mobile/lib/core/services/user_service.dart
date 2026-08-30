import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/dio_client.dart';
import '../models/user_model.dart';

class UserService {
  final Dio _dio = DioClient.create();

  /// Joriy foydalanuvchi ma'lumotlarini olish
  Future<UserModel> getCurrentUser() async {
    try {
      final response = await _dio.get('/users/me');
      return UserModel.fromJson(response.data);
    } catch (e) {
      print('Get current user error: $e');
      rethrow;
    }
  }

  /// Foydalanuvchi ma'lumotlarini yangilash
  /// Serverga tilni bildirish.
  ///
  /// Xabarnoma va push matnini SERVER yozadi, shuning uchun u
  /// foydalanuvchining tilini bilishi kerak. Xato bo'lsa jim o'tamiz:
  /// til almashtirish shu sababli buzilmasligi kerak — interfeys baribir
  /// almashadi, faqat xabarnomalar eski tilda qoladi.
  Future<void> setLanguage(String code) async {
    try {
      await updateCurrentUser(language: code);
    } catch (e) {
      print('Set language error: $e');
    }
  }

  Future<UserModel> updateCurrentUser({
    String? fullName,
    String? email,
    String? phone,
    String? language,
  }) async {
    try {
      final Map<String, dynamic> data = {};

      if (fullName != null) data['full_name'] = fullName;
      if (email != null) data['email'] = email;
      if (phone != null) data['phone'] = phone;
      if (language != null) data['language'] = language;

      final response = await _dio.put('/users/me', data: data);
      return UserModel.fromJson(response.data);
    } catch (e) {
      print('Update current user error: $e');
      rethrow;
    }
  }

  /// Bitta foydalanuvchini olish (ID bo'yicha)
  Future<UserModel> getUser(int userId) async {
    try {
      final response = await _dio.get('/users/$userId');
      return UserModel.fromJson(response.data);
    } catch (e) {
      print('Get user error: $e');
      rethrow;
    }
  }

  /// Barcha foydalanuvchilarni olish
  Future<List<UserModel>> getAllUsers() async {
    try {
      final response = await _dio.get('/users/');
      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => UserModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get all users error: $e');
      rethrow;
    }
  }

  /// User ID ni saqlash
  Future<void> saveUserId(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('user_id', userId);
  }

  /// User ID ni olish
  Future<int?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('user_id');
  }

  /// User role ni saqlash
  Future<void> saveUserRole(String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role', role);
  }

  /// User role ni olish
  Future<String?> getUserRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }
}

