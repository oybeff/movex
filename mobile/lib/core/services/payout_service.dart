import 'package:dio/dio.dart';

import '../models/payout_model.dart';
import '../network/dio_client.dart';

/// Pul yechish arizalari.
///
/// Eng kam summa serverda tekshiriladi (50 000 so'm) — bu yerda takrorlamaymiz,
/// aks holda ikki joyda ikki xil qoida paydo bo'lardi.
class PayoutService {
  final Dio _dio = DioClient.create();

  Future<List<PayoutRequestModel>> getMyRequests() async {
    final response = await _dio.get('/payouts/');
    final List<dynamic> data = response.data as List<dynamic>;
    return data
        .map((e) => PayoutRequestModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<PayoutRequestModel> createRequest({
    required double amount,
    required String cardNumber,
    String? cardHolder,
    String? comment,
  }) async {
    final response = await _dio.post('/payouts/', data: {
      'amount': amount,
      'card_number': cardNumber,
      if (cardHolder != null && cardHolder.isNotEmpty) 'card_holder': cardHolder,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
    return PayoutRequestModel.fromJson(response.data as Map<String, dynamic>);
  }
}
