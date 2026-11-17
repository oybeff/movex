import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// Привязанная карта (K1–K6). Токен карты приложению не отдаётся.
class BankCard {
  BankCard({required this.id, required this.pan, this.ps, this.holder, this.isDefault = false});

  factory BankCard.fromJson(Map<String, dynamic> j) => BankCard(
        id: j['id'] as int,
        pan: (j['pan'] ?? '') as String,
        ps: j['ps'] as String?,
        holder: j['holder_name'] as String?,
        isDefault: j['is_default'] == true,
      );

  final int id;
  final String pan;
  final String? ps;
  final String? holder;
  final bool isDefault;

  String get last4 => pan.length >= 4 ? pan.substring(pan.length - 4) : pan;

  /// «Uzcard •• 9012»
  String get label {
    final p = switch (ps) {
      'uzcard' => 'Uzcard',
      'humo' => 'Humo',
      'visa' => 'Visa',
      'mastercard' => 'Mastercard',
      'unionpay' => 'UnionPay',
      _ => 'Karta',
    };
    return '$p •• $last4';
  }
}

/// Ошибка сервера с кодом из detail: card_payment_failed и т. п.
String? apiDetail(Object e) {
  if (e is DioException) {
    final d = e.response?.data;
    if (d is Map && d['detail'] is String) return d['detail'] as String;
  }
  return null;
}

int? apiStatus(Object e) => e is DioException ? e.response?.statusCode : null;

class CardApi {
  final Dio _dio = DioClient.create();

  Future<List<BankCard>> list() async {
    final r = await _dio.get('/cards/');
    return [for (final j in r.data as List) BankCard.fromJson(j as Map<String, dynamic>)];
  }

  /// K2: ссылка на форму Multicard.
  Future<({String sessionId, String formUrl})> bind() async {
    final r = await _dio.post('/cards/bind');
    final d = r.data as Map<String, dynamic>;
    return (sessionId: d['session_id'] as String, formUrl: d['form_url'] as String);
  }

  /// null — карта ещё не добавлена. 409 — карта уже у другого аккаунта.
  Future<BankCard?> status(String sessionId) async {
    final r = await _dio.get('/cards/bind/$sessionId');
    final c = (r.data as Map<String, dynamic>)['card'];
    return c == null ? null : BankCard.fromJson(c as Map<String, dynamic>);
  }

  Future<void> delete(int id) => _dio.delete('/cards/$id');

  Future<void> makeDefault(int id) => _dio.put('/cards/$id/default');

  /// Код из SMS для заморозки суммы на карте.
  Future<void> confirmOtp(int requestId, String otp) =>
      _dio.post('/requests/$requestId/card-otp', data: {'otp': otp});

  /// E7: списать сразу с карты.
  Future<Map<String, dynamic>> payCard(int orderId, int cardId) async {
    final r = await _dio.post('/orders/$orderId/pay-card', data: {'card_id': cardId});
    return r.data as Map<String, dynamic>;
  }

  /// E7: «Naqd to'lash».
  Future<Map<String, dynamic>> payCash(int orderId) async {
    final r = await _dio.post('/orders/$orderId/pay-cash');
    return r.data as Map<String, dynamic>;
  }
}
