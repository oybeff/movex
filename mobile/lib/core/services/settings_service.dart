import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/contact_method_model.dart';

class SettingsService {
  final Dio _dio = DioClient.create();

  /// Barcha contact methods'larni olish
  Future<List<ContactMethodModel>> getContactMethods() async {
    try {
      final response = await _dio.get('/settings/contact-methods/');
      
      final List<dynamic> methods = response.data['methods'] as List<dynamic>;
      return methods.map((e) => ContactMethodModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get contact methods error: $e');
      rethrow;
    }
  }

  /// Foydalanish shartlarini olish
  Future<String> getTerms(String lang) async {
    try {
      final response = await _dio.get('/settings/terms/$lang');
      // Backend {"content": {"content": "..."}} qaytaradi
      final data = response.data['content'];
      if (data is Map) {
        return data['content'] as String;
      }
      return data as String;
    } catch (e) {
      print('Get terms error: $e');
      rethrow;
    }
  }

  /// Maxfiylik siyosatini olish
  Future<String> getPrivacyPolicy(String lang) async {
    try {
      final response = await _dio.get('/settings/privacy/$lang');
      // Backend {"content": {"content": "..."}} qaytaradi
      final data = response.data['content'];
      if (data is Map) {
        return data['content'] as String;
      }
      return data as String;
    } catch (e) {
      print('Get privacy policy error: $e');
      rethrow;
    }
  }

  /// Terms va Privacy ni birga olish
  Future<Map<String, String>> getTermsAndPrivacy() async {
    try {
      final response = await _dio.get('/settings/terms-and-privacy/');
      return {
        'terms_uz': response.data['terms_uz'] as String? ?? '',
        'terms_ru': response.data['terms_ru'] as String? ?? '',
        'privacy_uz': response.data['privacy_uz'] as String? ?? '',
        'privacy_ru': response.data['privacy_ru'] as String? ?? '',
      };
    } catch (e) {
      print('Get terms and privacy error: $e');
      rethrow;
    }
  }
}

