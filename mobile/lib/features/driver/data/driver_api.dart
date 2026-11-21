import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// Запросы приложения водителя (MoveX GO Driver). Все эндпоинты — уже
/// существующие серверные: заказ водителя — это обычный заказ владельца
/// (`/orders/*`), входящие — быстрые заявки (`/requests/quick/*`).
class DriverApi {
  final Dio _dio = DioClient.create();

  /// Заказы, где я владелец техники (клиентские мои — отфильтрованы).
  Future<List<DriverOrder>> myOrders(int myId) async {
    final r = await _dio.get('/orders/', queryParameters: {'limit': 200});
    return (r.data as List)
        .map((e) => DriverOrder(e as Map<String, dynamic>))
        .where((o) => o.clientId != myId)
        .toList();
  }

  Future<DriverOrder> order(int id) async {
    final r = await _dio.get('/orders/$id');
    return DriverOrder(r.data as Map<String, dynamic>);
  }

  Future<void> depart(int id) => _dio.post('/orders/$id/depart');
  Future<void> start(int id) => _dio.post('/orders/$id/start');
  Future<void> finish(int id) => _dio.post('/orders/$id/finish');
  Future<void> delay(int id, int minutes) =>
      _dio.post('/orders/$id/delay', data: {'minutes': minutes});
  Future<void> approveExtend(int id) => _dio.post('/orders/$id/extend/approve');
  Future<void> declineExtend(int id) => _dio.post('/orders/$id/extend/decline');
  Future<void> cancel(int id) => _dio.put('/orders/$id', data: {'status': 'cancelled'});

  /// Имя и телефон клиента — участникам заказа сервер их отдаёт (access.py).
  Future<Map<String, dynamic>?> client(int userId) async {
    try {
      final r = await _dio.get('/users/$userId');
      return r.data as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> balance() async {
    final r = await _dio.get('/balance/me');
    return r.data as Map<String, dynamic>;
  }
}

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

/// Заказ глазами владельца. Поля — как у OrderRead на сервере.
class DriverOrder {
  DriverOrder(this.j);

  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  int get clientId => j['user_id'] as int;
  String get status => j['status'] as String;
  double get total => _num(j['total_amount']);
  double get commission => _num(j['commission']);

  /// Сколько получит владелец: сумма заказа минус комиссия платформы.
  double get earning => total - commission;
  String get payment => (j['payment_method'] as String?) ?? 'balance';
  bool get cash => payment == 'cash';
  String? get address => j['delivery_address'] as String?;
  double get lat => _num(j['delivery_latitude']);
  double get lon => _num(j['delivery_longitude']);
  int? get hours => j['hours'] as int?;
  String? get tariff => j['tariff'] as String?;
  DateTime? _at(String k) => j[k] == null ? null : DateTime.tryParse('${j[k]}')?.toLocal();
  DateTime? get departedAt => _at('departed_at');
  DateTime? get startedAt => _at('started_at');
  DateTime? get finishedAt => _at('finished_at');
  DateTime get createdAt => _at('created_at') ?? DateTime.now();
  DateTime get updatedAt => _at('updated_at') ?? createdAt;
  int? get extendRequested => j['extend_requested_hours'] as int?;
  int? get delayMinutes => j['delay_minutes'] as int?;

  /// Живой заказ — его водитель видит на главной.
  bool get active => status == 'confirmed';
}
