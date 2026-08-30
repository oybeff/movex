import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/payment_model.dart';

class PaymentService {
  final Dio _dio = DioClient.create();

  /// Barcha to'lovlarni olish
  Future<List<PaymentModel>> getPayments({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/payments/',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => PaymentModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get payments error: $e');
      rethrow;
    }
  }

  /// Bitta to'lovni olish
  Future<PaymentModel> getPayment(int paymentId) async {
    try {
      final response = await _dio.get('/payments/$paymentId');
      return PaymentModel.fromJson(response.data);
    } catch (e) {
      print('Get payment error: $e');
      rethrow;
    }
  }

  /// Yangi to'lov yaratish
  Future<PaymentModel> createPayment(Map<String, dynamic> data) async {
    try {
      final response = await _dio.post(
        '/payments/',
        data: data,
      );
      return PaymentModel.fromJson(response.data);
    } catch (e) {
      print('Create payment error: $e');
      rethrow;
    }
  }

  /// To'lovni yangilash
  Future<PaymentModel> updatePayment(int paymentId, Map<String, dynamic> data) async {
    try {
      final response = await _dio.put(
        '/payments/$paymentId',
        data: data,
      );
      return PaymentModel.fromJson(response.data);
    } catch (e) {
      print('Update payment error: $e');
      rethrow;
    }
  }

  /// To'lovni o'chirish
  Future<void> deletePayment(int paymentId) async {
    try {
      await _dio.delete('/payments/$paymentId');
    } catch (e) {
      print('Delete payment error: $e');
      rethrow;
    }
  }
}

