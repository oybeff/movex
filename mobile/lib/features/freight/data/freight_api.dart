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
  /// Картинка модели из админки; null — общий грузовик.
  String? get iconUrl => j['icon_url'] as String?;
  int get capacityKg => (j['capacity_kg'] ?? 0) as int;
  double get tonnes => capacityKg / 1000;
  bool get bodyChoice => j['has_body_choice'] == true;
  bool get hourly => j['price_mode'] == 'hour';
  int? get hours => j['hours'] as int?;
  int get minHours => (j['min_hours'] ?? 1) as int;
  double? get price => _dn(j['price']);

  // Шаги Y1–Y8
  String get brand => (j['brand'] ?? name) as String;
  String get sizeClass => (j['size_class'] ?? 'medium') as String;
  double? get bodyL => _dn(j['body_length_m']);
  double? get bodyW => _dn(j['body_width_m']);
  double? get bodyH => _dn(j['body_height_m']);
  List<String> get bodyTypes => [for (final b in (j['body_types'] as List? ?? const [])) b as String];
  double? get pricePerKm => _dn(j['price_per_km']);
  double get baseFee => _d(j['base_fee']);
  double? get minPrice => _dn(j['min_price']);
  int get freeDrivers => (j['free_drivers'] ?? 0) as int;
  double? get nearestKm => _dn(j['nearest_km']);
  bool get fits => j['fits'] != false;
  String? get fitProblem => j['fit_problem'] as String?;

  /// «2.8 × 1.6 × 1.6 m» — размеры кузова для карточек Y2/Y7/Y8.
  String? get dims => bodyL == null || bodyW == null
      ? null
      : [bodyL, bodyW, if (bodyH != null) bodyH].map((x) => x == x!.roundToDouble() ? x.toStringAsFixed(0) : '$x').join(' × ');

  /// Влезет ли груз — та же проверка, что на сервере (fit_problem): длину
  /// и ширину можно развернуть, высоту — нет.
  bool fitsCargo({double? kg, double? l, double? w, double? h, double? m3}) {
    if (kg != null && kg > capacityKg) return false;
    if (m3 != null && bodyL != null && bodyW != null && bodyH != null && m3 > bodyL! * bodyW! * bodyH!) return false;
    if (l != null && w != null && bodyL != null && bodyW != null) {
      final a = l > w ? l : w, b = l > w ? w : l;
      final bl = bodyL! > bodyW! ? bodyL! : bodyW!, bw = bodyL! > bodyW! ? bodyW! : bodyL!;
      if (a > bl || b > bw) return false;
    }
    if (h != null && bodyH != null && h > bodyH!) return false;
    return true;
  }
}

class FreightQuote {
  FreightQuote(this.j);
  final Map<String, dynamic> j;

  double get distanceKm => _d(j['distance_km']);
  String? get suggested => j['suggested'] as String?;
  double get loaderFee => _d(j['loader_fee']);
  double get loaderHourFee => _d(j['loader_hour_fee']);
  double get loaderDayFee => _d(j['loader_day_fee']);
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
  String? get cargoType => j['cargo_type'] as String?;
  bool get needsLoader => j['needs_loader'] == true;
  DateTime? get scheduledAt => j['scheduled_at'] == null ? null : DateTime.tryParse('${j['scheduled_at']}')?.toLocal();
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
  String? get cargoType => j['cargo_type'] as String?;
  bool get needsLoader => j['needs_loader'] == true;
  DateTime? get scheduledAt => j['scheduled_at'] == null ? null : DateTime.tryParse('${j['scheduled_at']}')?.toLocal();
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
    String? body,
    double? weightKg,
    double? length,
    double? width,
    double? height,
    bool loader = false,
    String? loaderMode,
    int? loaderHours,
  }) async {
    final r = await _dio.get('/freight/quote', queryParameters: {
      if (body != null) 'body': body,
      if (weightKg != null && weightKg > 0) 'weight_kg': weightKg,
      if (length != null && length > 0) 'length': length,
      if (width != null && width > 0) 'width': width,
      if (height != null && height > 0) 'height': height,
      if (loader) 'loader': true,
      if (loader && loaderMode != null) 'loader_mode': loaderMode,
      if (loader && loaderHours != null) 'loader_hours': loaderHours,
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
