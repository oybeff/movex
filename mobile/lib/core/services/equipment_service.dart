import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/equipment_model.dart';

class EquipmentService {
  final Dio _dio = DioClient.create();

  /// Barcha texnikalarni olish
  Future<List<EquipmentModel>> getEquipmentList({
    bool ownerOnly = false,
    String? type,
    String? status,
    String? search,
    int page = 1,
    int limit = 20,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'owner_only': ownerOnly,
        'page': page,
        'limit': limit,
      };

      if (type != null) queryParams['type'] = type;
      if (status != null) queryParams['status'] = status;
      if (search != null) queryParams['search'] = search;

      final response = await _dio.get(
        '/equipment/',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => EquipmentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get equipment list error: $e');
      rethrow;
    }
  }

  /// Bitta texnikani olish
  Future<EquipmentModel> getEquipment(int equipmentId) async {
    try {
      final response = await _dio.get('/equipment/$equipmentId');
      return EquipmentModel.fromJson(response.data);
    } catch (e) {
      print('Get equipment error: $e');
      rethrow;
    }
  }

  /// Yangi texnika qo'shish
  Future<EquipmentModel> createEquipment(EquipmentCreateModel equipment) async {
    try {
      final response = await _dio.post(
        '/equipment/',
        data: equipment.toJson(),
      );
      return EquipmentModel.fromJson(response.data);
    } catch (e) {
      print('Create equipment error: $e');
      rethrow;
    }
  }

  /// Texnikani yangilash
  Future<EquipmentModel> updateEquipment(int equipmentId, EquipmentUpdateModel equipment) async {
    try {
      final response = await _dio.put(
        '/equipment/$equipmentId',
        data: equipment.toJson(),
      );
      return EquipmentModel.fromJson(response.data);
    } catch (e) {
      print('Update equipment error: $e');
      rethrow;
    }
  }

  /// Texnikani o'chirish
  Future<void> deleteEquipment(int equipmentId) async {
    try {
      await _dio.delete('/equipment/$equipmentId');
    } catch (e) {
      print('Delete equipment error: $e');
      rethrow;
    }
  }

  /// Texnika rasmini yuklash
  /// Texnika rasmini yuklash.
  ///
  /// Webda faylning yo'li yo'q — faqat mazmuni bor, shuning uchun `bytes`
  /// ham qabul qilinadi (e'lonlardagi uploadPhoto shunday ishlaydi).
  Future<void> uploadEquipmentPhoto({
    required int equipmentId,
    String? filePath,
    List<int>? bytes,
    String fileName = 'photo.jpg',
    bool isPrimary = false,
  }) async {
    try {
      final MultipartFile part;
      if (bytes != null) {
        part = MultipartFile.fromBytes(bytes, filename: fileName);
      } else if (filePath != null) {
        part = await MultipartFile.fromFile(filePath, filename: fileName);
      } else {
        throw ArgumentError('kerak: filePath yoki bytes');
      }

      final formData = FormData.fromMap({
        'file': part,
        'is_primary': isPrimary,
      });

      await _dio.post(
        '/equipment/$equipmentId/photos',
        data: formData,
      );
    } catch (e) {
      print('Upload equipment photo error: $e');
      rethrow;
    }
  }

  /// Texnika rasmlarini olish
  Future<List<EquipmentPhotoModel>> getEquipmentPhotos(int equipmentId) async {
    try {
      final response = await _dio.get('/equipment/$equipmentId/photos');
      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => EquipmentPhotoModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get equipment photos error: $e');
      rethrow;
    }
  }

  /// Texnika rasmini o'chirish
  Future<void> deleteEquipmentPhoto(int photoId) async {
    try {
      await _dio.delete('/equipment/photos/$photoId');
    } catch (e) {
      print('Delete equipment photo error: $e');
      rethrow;
    }
  }

  /// Texnikaning faol buyurtmasini olish
  Future<Map<String, dynamic>?> getActiveOrder(int equipmentId) async {
    try {
      final response = await _dio.get('/equipment/$equipmentId/active_order');
      return response.data;
    } catch (e) {
      print('Get active order error: $e');
      return null;
    }
  }

  /// Texnika holatini o'zgartirish
  Future<Map<String, dynamic>> updateEquipmentStatus(int equipmentId, String status) async {
    try {
      final response = await _dio.patch(
        '/equipment/$equipmentId/status',
        queryParameters: {'status': status},
      );
      return response.data;
    } catch (e) {
      print('Update equipment status error: $e');
      rethrow;
    }
  }

  /// Texnikaning barcha band sanalarini olish
  Future<Map<String, dynamic>> getBookedDates(int equipmentId) async {
    try {
      final response = await _dio.get('/equipment/$equipmentId/booked-dates');
      return response.data;
    } catch (e) {
      print('Get booked dates error: $e');
      rethrow;
    }
  }

  /// Texnikaning ma'lum sana oralig'ida bo'shligini tekshirish
  Future<Map<String, dynamic>> checkAvailability({
    required int equipmentId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    try {
      final response = await _dio.get(
        '/equipment/$equipmentId/availability',
        queryParameters: {
          'start_date': startDate.toIso8601String().split('T')[0],
          'end_date': endDate.toIso8601String().split('T')[0],
        },
      );
      return response.data;
    } catch (e) {
      print('Check equipment availability error: $e');
      rethrow;
    }
  }
}

