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
  Future<void> arrive(int id) => _dio.post('/orders/$id/arrive');

  /// «Rad etish» с причиной (макет H4): far | low_price | busy | not_my_job | other.
  Future<void> decline(int requestId, String? reason) => _dio.post(
        '/requests/$requestId/quick-decline',
        data: {if (reason != null) 'reason': reason},
      );

  /// Чат заказа — тот же, что у клиента (/chats/), создаётся при первом открытии.
  Future<int> chatFor(int orderId) async {
    final r = await _dio.get('/chats/');
    for (final c in (r.data as List)) {
      final m = c as Map<String, dynamic>;
      if (m['order_id'] == orderId) return m['id'] as int;
    }
    final created = await _dio.post('/chats/', data: {'order_id': orderId});
    return (created.data as Map<String, dynamic>)['id'] as int;
  }

  /// Последние движения денег — «Tranzaksiyalar» на «Daromad».
  Future<List<Map<String, dynamic>>> transactions() async {
    final r = await _dio.get('/balance/transactions', queryParameters: {'limit': 20});
    return (r.data as List).cast<Map<String, dynamic>>();
  }

  /// Моя техника: id → тип, модель, номер. Заказ знает только equipment_id.
  Future<Map<int, DriverEquipment>> myEquipment() async {
    final r = await _dio.get('/equipment/', queryParameters: {'owner_only': true});
    return {
      for (final e in (r.data as List).cast<Map<String, dynamic>>())
        e['id'] as int: DriverEquipment(e),
    };
  }

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
  DateTime? get arrivedAt => _at('arrived_at');
  DateTime? get startedAt => _at('started_at');
  DateTime? get finishedAt => _at('finished_at');
  DateTime get createdAt => _at('created_at') ?? DateTime.now();
  DateTime get updatedAt => _at('updated_at') ?? createdAt;
  int? get extendRequested => j['extend_requested_hours'] as int?;
  int? get delayMinutes => j['delay_minutes'] as int?;

  DateTime? get startDate => j['start_date'] == null ? null : DateTime.tryParse('${j['start_date']}');
  String? get startTime => (j['start_time'] as String?)?.substring(0, 5);
  int get equipmentId => j['equipment_id'] as int;
  String? get cancelledBy => j['cancelled_by'] as String?;

  /// Живой заказ — его водитель видит на главной.
  bool get active => status == 'confirmed';

  /// Подтверждён, но ещё не выехал и начало не сегодня — «Rejalashtirilgan».
  bool get scheduled {
    final d = startDate;
    if (!active || departedAt != null || d == null) return false;
    final now = DateTime.now();
    return DateTime(d.year, d.month, d.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  /// Цена часа для расчёта продления (D4): сумма ÷ часы.
  double? get pricePerHour => (hours == null || hours == 0) ? null : total / hours!;
}

/// Техника владельца — для заголовков «Ekskavator · Ekonom» и карточки на главной.
class DriverEquipment {
  DriverEquipment(this.j);

  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get type => (j['type'] as String?) ?? 'other';
  String? get model => j['model'] as String?;
  String? get plate => j['plate_number'] as String?;
}
