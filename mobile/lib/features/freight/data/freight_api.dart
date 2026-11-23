import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

double _d(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _dn(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// Грузовик в расчёте «Yuk tashish»: цена на этот маршрут (null — админ
/// цену не поставил, машину не показываем как доступную).
class FreightVehicle {
  FreightVehicle(this.j);
  final Map<String, dynamic> j;

  String get code => j['code'] as String;
  String get name => (j['name'] ?? code) as String;
  int get capacityKg => (j['capacity_kg'] ?? 0) as int;
  double get tonnes => capacityKg / 1000;
  bool get bodyChoice => j['has_body_choice'] == true;
  bool get hourly => j['price_mode'] == 'hour';
  int? get hours => j['hours'] as int?;
  int get minHours => (j['min_hours'] ?? 1) as int;
  double? get price => _dn(j['price']);
}

class FreightQuote {
  FreightQuote(this.j);
  final Map<String, dynamic> j;

  double get distanceKm => _d(j['distance_km']);
  String? get suggested => j['suggested'] as String?;
  List<FreightVehicle> get vehicles =>
      [for (final v in (j['vehicles'] as List? ?? const [])) FreightVehicle((v as Map).cast<String, dynamic>())];
}

/// Заказ «Yuk tashish» — у клиента и у водителя одна и та же модель.
class FreightOrder {
  FreightOrder(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get status => (j['status'] ?? '') as String;
  String get vehicleName => (j['vehicle_name'] ?? j['vehicle_code'] ?? '') as String;
  String? get bodyType => j['body_type'] as String?;
  double? get tonnes => _dn(j['cargo_tonnes']);
  String? get note => j['cargo_note'] as String?;
  String? get fromAddress => j['from_address'] as String?;
  String? get toAddress => j['to_address'] as String?;
  double get fromLat => _d(j['from_latitude']);
  double get fromLon => _d(j['from_longitude']);
  double get toLat => _d(j['to_latitude']);
  double get toLon => _d(j['to_longitude']);
  double get distanceKm => _d(j['distance_km']);
  int? get hours => j['hours'] as int?;
  double get price => _d(j['price']);
  bool get cash => j['payment_method'] == 'cash';
  double get driverFee => _d(j['driver_fee'] ?? j['price']);
  double get commission => _d(j['driver_commission']);
  String? get driverName => j['driver_name'] as String?;
  String? get driverPhone => j['driver_phone'] as String?;
  String? get driverPlate => j['driver_plate'] as String?;
  String? get clientName => j['client_name'] as String?;
  String? get clientPhone => j['client_phone'] as String?;
  DateTime get createdAt => DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now();

  bool get active => const {'searching', 'accepted', 'loaded', 'arrived'}.contains(status);

  /// Водитель уже взял и ещё не закончил — держит водителя.
  bool get busyForDriver => const {'accepted', 'loaded', 'arrived'}.contains(status);
}

/// Входящий «Yuk tashish» для водителя.
class FreightIncoming {
  FreightIncoming(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String? get bodyType => j['body_type'] as String?;
  double? get tonnes => _dn(j['cargo_tonnes']);
  String? get note => j['cargo_note'] as String?;
  String? get fromAddress => j['from_address'] as String?;
  String? get toAddress => j['to_address'] as String?;
  double get distanceKm => _d(j['distance_km']);
  double? get toPickupKm => _dn(j['to_pickup_km']);
  int? get hours => j['hours'] as int?;
  bool get cash => j['payment_method'] == 'cash';
  double get fee => _d(j['driver_fee']);
  double get commission => _d(j['commission']);
  double get youReceive => _d(j['you_receive']);
}

class FreightApi {
  final Dio _dio = DioClient.create();

  Future<FreightQuote> quote({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    double? tonnes,
    int? hours,
  }) async {
    final r = await _dio.get('/freight/quote', queryParameters: {
      'from_lat': fromLat,
      'from_lon': fromLon,
      'to_lat': toLat,
      'to_lon': toLon,
      if (tonnes != null && tonnes > 0) 'tonnes': tonnes,
      if (hours != null) 'hours': hours,
    });
    return FreightQuote((r.data as Map).cast<String, dynamic>());
  }

  Future<FreightOrder> create(Map<String, dynamic> body) async {
    final r = await _dio.post('/freight/orders', data: body);
    return FreightOrder((r.data as Map).cast<String, dynamic>());
  }

  Future<List<FreightOrder>> myOrders() async {
    final r = await _dio.get('/freight/orders');
    return [for (final e in (r.data as List)) FreightOrder((e as Map).cast<String, dynamic>())];
  }

  Future<FreightOrder> cancel(int id) async =>
      FreightOrder(((await _dio.post('/freight/orders/$id/cancel')).data as Map).cast<String, dynamic>());

  Future<FreightOrder> finish(int id) async =>
      FreightOrder(((await _dio.post('/freight/orders/$id/finish')).data as Map).cast<String, dynamic>());

  // --------------------------------------------------------- водитель

  Future<List<FreightIncoming>> incoming() async {
    final r = await _dio.get('/drivers/freight/incoming');
    return [for (final e in (r.data as List)) FreightIncoming((e as Map).cast<String, dynamic>())];
  }

  Future<List<FreightOrder>> driverOrders() async {
    final r = await _dio.get('/drivers/freight/orders');
    return [for (final e in (r.data as List)) FreightOrder((e as Map).cast<String, dynamic>())];
  }

  Future<FreightOrder> step(int id, String step) async =>
      FreightOrder(((await _dio.post('/drivers/freight/orders/$id/$step')).data as Map).cast<String, dynamic>());
}
