import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/franchise_model.dart';
import '../models/equipment_model.dart';
import '../models/order_model.dart';
import '../models/payment_model.dart';

class FranchiseService {
  final Dio _dio = DioClient.create();

  /// Barcha franchiselarni olish
  Future<List<FranchiseModel>> getFranchises({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/franchises/',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => FranchiseModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get franchises error: $e');
      rethrow;
    }
  }

  /// Bitta franchise ma'lumotlarini olish
  Future<FranchiseModel> getFranchise(int franchiseId) async {
    try {
      final response = await _dio.get('/franchises/$franchiseId');
      return FranchiseModel.fromJson(response.data);
    } catch (e) {
      print('Get franchise error: $e');
      rethrow;
    }
  }

  /// Yangi franchise yaratish
  Future<FranchiseModel> createFranchise(FranchiseCreateModel franchise) async {
    try {
      final response = await _dio.post(
        '/franchises/',
        data: franchise.toJson(),
      );
      return FranchiseModel.fromJson(response.data);
    } catch (e) {
      print('Create franchise error: $e');
      rethrow;
    }
  }

  /// Franchise ma'lumotlarini yangilash
  Future<FranchiseModel> updateFranchise(int franchiseId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        '/franchises/$franchiseId',
        data: data,
      );
      return FranchiseModel.fromJson(response.data);
    } catch (e) {
      print('Update franchise error: $e');
      rethrow;
    }
  }

  /// Franchise o'chirish
  Future<void> deleteFranchise(int franchiseId) async {
    try {
      await _dio.delete('/franchises/$franchiseId');
    } catch (e) {
      print('Delete franchise error: $e');
      rethrow;
    }
  }

  /// Franchise statistikasini olish
  /// Hozircha equipment, orders va payments'dan hisoblangan statistikani qaytaramiz
  Future<FranchiseStatsModel> getFranchiseStats(int franchiseId) async {
    try {
      // Equipment, orders va payments'ni olamiz
      final equipmentResponse = await _dio.get('/equipment/', queryParameters: {'owner_only': true});
      final ordersResponse = await _dio.get('/orders/');
      final paymentsResponse = await _dio.get('/payments/');

      final equipmentList = equipmentResponse.data as List? ?? [];
      final ordersList = ordersResponse.data as List? ?? [];
      final paymentsList = paymentsResponse.data as List? ?? [];

      // Statistikani hisoblash
      int totalEquipment = equipmentList.length;
      int activeOrders = ordersList.where((o) => o['status'] == 'active' || o['status'] == 'pending').length;
      int completedOrders = ordersList.where((o) => o['status'] == 'completed').length;

      double totalRevenue = 0;
      double monthlyRevenue = 0;
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);

      for (var payment in paymentsList) {
        final amount = (payment['amount'] as num?)?.toDouble() ?? 0;
        totalRevenue += amount;

        final createdAt = DateTime.tryParse(payment['created_at'] ?? '');
        if (createdAt != null && createdAt.isAfter(currentMonth)) {
          monthlyRevenue += amount;
        }
      }

      return FranchiseStatsModel(
        franchiseId: franchiseId,
        totalEquipment: totalEquipment,
        activeOrders: activeOrders,
        completedOrders: completedOrders,
        totalRevenue: totalRevenue,
        totalRoyalty: totalRevenue * 0.1, // 10% royalty
        monthlyRevenue: monthlyRevenue,
        monthlyRoyalty: monthlyRevenue * 0.1,
      );
    } catch (e) {
      print('Get franchise stats error: $e');
      rethrow;
    }
  }

  /// Franchise texnikalarini olish
  /// Hozircha owner'ning barcha texnikalarini qaytaramiz
  Future<List<EquipmentModel>> getFranchiseEquipment(
    int franchiseId, {
    String? status,
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'owner_only': true,
        'page': 1,
        'limit': limit,
      };

      if (status != null) queryParams['status'] = status;

      final response = await _dio.get(
        '/equipment/',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => EquipmentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get franchise equipment error: $e');
      rethrow;
    }
  }

  /// Franchise buyurtmalarini olish
  /// Hozircha owner'ning barcha buyurtmalarini qaytaramiz
  Future<List<OrderModel>> getFranchiseOrders(
    int franchiseId, {
    String? status,
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'skip': skip,
        'limit': limit,
      };

      if (status != null) queryParams['status'] = status;

      final response = await _dio.get(
        '/orders/',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get franchise orders error: $e');
      rethrow;
    }
  }

  /// Franchise to'lovlarini olish
  /// Hozircha owner'ning barcha to'lovlarini qaytaramiz
  Future<List<PaymentModel>> getFranchisePayments(
    int franchiseId, {
    String? status,
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'skip': skip,
        'limit': limit,
      };

      if (status != null) queryParams['status'] = status;

      final response = await _dio.get(
        '/payments/',
        queryParameters: queryParams,
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => PaymentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get franchise payments error: $e');
      rethrow;
    }
  }

  /// Joriy foydalanuvchining franchise ma'lumotlarini olish
  /// Hozircha company ma'lumotlarini franchise sifatida qaytaramiz
  Future<FranchiseModel?> getMyFranchise() async {
    try {
      // Hozircha companies endpoint'idan foydalanib, birinchi company'ni olamiz
      final response = await _dio.get('/companies/');
      if (response.data == null || (response.data as List).isEmpty) {
        return null;
      }

      // Birinchi company'ni olamiz va uni franchise formatiga o'tkazamiz
      final companyData = (response.data as List).first;

      // Company ma'lumotlarini franchise formatiga moslashtirish
      return FranchiseModel(
        id: companyData['id'] ?? 0,
        name: companyData['name'] ?? 'Franchise',
        region: 'Toshkent', // Default qiymat
        address: companyData['description'] ?? '',
        phone: '',
        email: '',
        ownerId: companyData['owner_id'] ?? 0,
        status: 'active',
        royaltyPercentage: 10.0,
        createdAt: DateTime.tryParse(companyData['created_at'] ?? '') ?? DateTime.now(),
        updatedAt: DateTime.tryParse(companyData['updated_at'] ?? '') ?? DateTime.now(),
      );
    } catch (e) {
      print('Get my franchise error: $e');
      // Agar franchise topilmasa, null qaytaramiz
      if (e is DioException && e.response?.statusCode == 404) {
        return null;
      }
      return null; // Xatolik bo'lsa ham null qaytaramiz
    }
  }
}

