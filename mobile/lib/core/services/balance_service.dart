import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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

  /// To'lov usullari — SERVERDAN.
  ///
  /// Ilovada yozib qo'yilmaydi: yig'ilgan APK'da qotib qolgan ro'yxat
  /// sozlama o'zgarganda yolg'on bo'lib qolardi. Xato bo'lsa bo'sh
  /// ro'yxat qaytadi va ekran standart usulni ko'rsatadi — to'ldirish
  /// imkoniyati butunlay yo'qolmasligi kerak.
  Future<List<PaymentMethodModel>> getPaymentMethods() async {
    try {
      final response = await _dio.get('/balance/methods');
      final List<dynamic> data = response.data as List<dynamic>;
      return data
          .map((e) => PaymentMethodModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      // debugPrint, print emas: yangi `print` flutter analyze sonini
      // oshiradi, va u loyihada nazorat ostida turadi.
      debugPrint('Get payment methods error: $e');
      return const <PaymentMethodModel>[];
    }
  }

  /// Hisob to'ldirish — chekaut sahifasiga havola bilan
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

  /// Tranzaksiya holatini tekshirish.
  ///
  /// Server holatni TO'LOV TIZIMIDAN so'rab aniqlaydi, bazadagi qiymatni
  /// shunchaki qaytarmaydi. Kerak, chunki callback yo'lda kechikishi yoki
  /// tunnel uzilib umuman kelmasligi mumkin: bunda odam pulini to'lagan,
  /// ekranda esa "kutilmoqda" turardi.
  Future<String> checkTransactionStatus(int transactionId) async {
    try {
      final response = await _dio.post('/balance/transactions/$transactionId/sync');
      return BalanceTransactionModel.fromJson(response.data).status;
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

