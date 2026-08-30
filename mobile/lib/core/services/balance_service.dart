import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/balance_model.dart';

class BalanceService {
  final Dio _dio = DioClient.create();

  /// Joriy foydalanuvchi balansini olish
  Future<BalanceModel> getBalance() async {
    try {
      final response = await _dio.get('/balance/me');
      return BalanceModel.fromJson(response.data);
    } catch (e) {
      print('Get balance error: $e');
      rethrow;
    }
  }

  /// Hisob to'ldirish - Click to'lov URL'i bilan
  Future<BalanceTopUpResponse> topUpBalance({
    required double amount,
    required String paymentMethod,
    String? phoneNumber,
  }) async {
    try {
      final data = {
        'amount': amount,
        'payment_method': paymentMethod,
      };

      // Telefon raqam qo'shish (agar mavjud bo'lsa)
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        data['phone_number'] = phoneNumber;
      }

      final response = await _dio.post(
        '/balance/topup',
        data: data,
      );
      return BalanceTopUpResponse.fromJson(response.data);
    } catch (e) {
      print('Top up balance error: $e');
      rethrow;
    }
  }

  /// Transaction statusini tekshirish
  Future<String> checkTransactionStatus(int transactionId) async {
    try {
      final transaction = await getTransaction(transactionId);
      return transaction.status;
    } catch (e) {
      print('Check transaction status error: $e');
      rethrow;
    }
  }

  /// Hisob to'ldirish tarixini olish
  Future<List<BalanceTransactionModel>> getTransactionHistory({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/balance/transactions',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      return data.map((e) => BalanceTransactionModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get transaction history error: $e');
      rethrow;
    }
  }

  /// Bitta tranzaksiyani olish
  Future<BalanceTransactionModel> getTransaction(int transactionId) async {
    try {
      final response = await _dio.get('/balance/transactions/$transactionId');
      return BalanceTransactionModel.fromJson(response.data);
    } catch (e) {
      print('Get transaction error: $e');
      rethrow;
    }
  }
}

