import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/order_model.dart';
import '../models/order_statistics_model.dart';

class OrderService {
  final Dio _dio = DioClient.create();

  /// Barcha buyurtmalarni olish
  Future<List<OrderModel>> getOrders({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/orders/',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => OrderModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get orders error: $e');
      rethrow;
    }
  }

  /// Bitta buyurtmani olish
  Future<OrderModel> getOrder(int orderId) async {
    try {
      final response = await _dio.get('/orders/$orderId');
      return OrderModel.fromJson(response.data);
    } catch (e) {
      print('Get order error: $e');
      rethrow;
    }
  }

  /// Yangi buyurtma yaratish
  Future<OrderModel> createOrder(OrderCreateModel order) async {
    try {
      final response = await _dio.post(
        '/orders/',
        data: order.toJson(),
      );
      return OrderModel.fromJson(response.data);
    } catch (e) {
      print('Create order error: $e');
      rethrow;
    }
  }

  /// Buyurtmani yangilash
  Future<OrderModel> updateOrder(int orderId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        '/orders/$orderId',
        data: data,
      );
      return OrderModel.fromJson(response.data);
    } catch (e) {
      print('Update order error: $e');
      rethrow;
    }
  }

  /// Buyurtmani o'chirish
  Future<void> deleteOrder(int orderId) async {
    try {
      await _dio.delete('/orders/$orderId');
    } catch (e) {
      print('Delete order error: $e');
      rethrow;
    }
  }

  /// Buyurtma statusini o'zgartirish
  Future<OrderModel> updateOrderStatus(int orderId, String status) async {
    try {
      final response = await _dio.put(
        '/orders/$orderId',
        data: {'status': status},
      );
      return OrderModel.fromJson(response.data);
    } catch (e) {
      print('Update order status error: $e');
      rethrow;
    }
  }

  /// Buyurtmalar statistikasini olish
  Future<OrderStatisticsModel> getOrderStatistics({
    String? startDate,
    String? endDate,
    String? status,
    int? equipmentId,
  }) async {
    try {
      final queryParams = <String, dynamic>{};
      if (startDate != null) queryParams['start_date'] = startDate;
      if (endDate != null) queryParams['end_date'] = endDate;
      if (status != null) queryParams['status'] = status;
      if (equipmentId != null) queryParams['equipment_id'] = equipmentId;

      final response = await _dio.get(
        '/orders/statistics/summary',
        queryParameters: queryParams,
      );

      return OrderStatisticsModel.fromJson(response.data);
    } catch (e) {
      print('Get order statistics error: $e');
      rethrow;
    }
  }
}

