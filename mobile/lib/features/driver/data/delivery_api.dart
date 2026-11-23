import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);
double? _numOrNull(dynamic v) => v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

/// Категория стройматериала из ТЗ: что водитель возит.
class DeliveryCategory {
  DeliveryCategory(this.code, this.name, this.unit);
  final String code;
  final String name;

  /// piece | bag | tonne | m3 — в чём водитель пишет минимум.
  final String unit;
}

/// Машина водителя доставки и что он возит (`/drivers/delivery/profile`).
class DeliveryProfile {
  DeliveryProfile(this.j);
  final Map<String, dynamic> j;

  bool get registered => j['registered'] == true;
  String? get vehicleCode => j['vehicle_code'] as String?;
  String? get vehicleName => (j['vehicle'] as Map?)?['name'] as String?;
  int? get capacityKg => (j['vehicle'] as Map?)?['capacity_kg'] as int?;
  String? get plate => j['plate'] as String?;
  double? get pricePerKm => _numOrNull(j['price_per_km']);
  double? get baseFee => _numOrNull(j['base_fee']);
  Map<String, double> get categories => {
        for (final c in (j['categories'] as List? ?? const []))
          (c as Map)['code'] as String: _num(c['min_quantity']),
      };
}

/// Карточка входящего заказа на доставку.
class DeliveryIncoming {
  DeliveryIncoming(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String? get materialType => j['material_type'] as String?;
  String get title => (j['title'] ?? '') as String;
  double get quantity => _num(j['quantity']);
  String get unit => (j['unit'] ?? 'piece') as String;
  int get trips => (j['trips'] ?? 1) as int;
  String? get pickupAddress => j['pickup_address'] as String?;
  String? get deliveryAddress => j['delivery_address'] as String?;
  double? get distanceKm => _numOrNull(j['distance_km']);
  double? get toPickupKm => _numOrNull(j['to_pickup_km']);
  bool get cash => j['delivery_payment'] == 'cash';
  double get fee => _num(j['driver_fee']);
  double get commission => _num(j['commission']);
  double get youReceive => _num(j['you_receive']);
}

/// Заказ на доставку, который водитель принял.
class DeliveryOrder {
  DeliveryOrder(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get status => (j['status'] ?? '') as String;
  String? get deliveryStatus => j['delivery_status'] as String?;
  String? get materialType => j['material_type'] as String?;
  String get title => (j['product_title'] ?? '') as String;
  double get quantity => _num(j['quantity']);
  String get unit => (j['unit'] ?? 'piece') as String;
  int get trips => (j['trips'] ?? 1) as int;
  bool get cash => j['delivery_payment'] == 'cash';
  double get fee => _num(j['driver_fee']);
  double get commission => _num(j['driver_commission']);
  double get goods => _num(j['goods_amount']);
  String? get pickupAddress => j['pickup_address'] as String?;
  double? get pickupLat => _numOrNull(j['pickup_latitude']);
  double? get pickupLon => _numOrNull(j['pickup_longitude']);
  String? get deliveryAddress => j['delivery_address'] as String?;
  double? get deliveryLat => _numOrNull(j['delivery_latitude']);
  double? get deliveryLon => _numOrNull(j['delivery_longitude']);
  String? get buyerName => j['buyer_name'] as String?;
  String? get buyerPhone => j['buyer_phone'] as String?;
  String? get sellerName => j['seller_name'] as String?;
  String? get sellerPhone => j['seller_phone'] as String?;
  String? get comment => j['comment'] as String?;
  DateTime get createdAt => DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now();

  /// Едет или везёт: держит водителя, новые доставки не показываются.
  bool get active =>
      status == 'confirmed' && const {'accepted', 'picked_up', 'arrived'}.contains(deliveryStatus);
}

class DeliveryApi {
  final Dio _dio = DioClient.create();

  Future<List<DeliveryCategory>> categories(String lang) async {
    final r = await _dio.get('/drivers/delivery/categories', queryParameters: {'lang': lang});
    return [
      for (final c in (r.data as List))
        DeliveryCategory(c['code'] as String, c['name'] as String, c['unit'] as String),
    ];
  }

  Future<DeliveryProfile> profile() async {
    final r = await _dio.get('/drivers/delivery/profile');
    return DeliveryProfile(r.data as Map<String, dynamic>);
  }

  Future<DeliveryProfile> saveProfile({
    required String vehicleCode,
    String? plate,
    double? pricePerKm,
    double? baseFee,
    required Map<String, double> categories,
  }) async {
    final r = await _dio.put('/drivers/delivery/profile', data: {
      'vehicle_code': vehicleCode,
      'plate': plate,
      'price_per_km': pricePerKm,
      'base_fee': baseFee,
      'categories': [
        for (final e in categories.entries) {'code': e.key, 'min_quantity': e.value},
      ],
    });
    return DeliveryProfile(r.data as Map<String, dynamic>);
  }

  /// Раз в опрос, пока онлайн: где водитель. online=false — ушёл с линии.
  Future<void> heartbeat({required bool online, double? lat, double? lon}) =>
      _dio.post('/drivers/delivery/heartbeat', data: {
        'online': online,
        if (lat != null) 'latitude': lat,
        if (lon != null) 'longitude': lon,
      });

  Future<List<DeliveryIncoming>> incoming() async {
    final r = await _dio.get('/drivers/delivery/incoming');
    return [for (final e in (r.data as List)) DeliveryIncoming((e as Map).cast<String, dynamic>())];
  }

  Future<List<DeliveryOrder>> orders() async {
    final r = await _dio.get('/drivers/delivery/orders');
    return [for (final e in (r.data as List)) DeliveryOrder((e as Map).cast<String, dynamic>())];
  }

  Future<DeliveryOrder> _step(int id, String step) async {
    final r = await _dio.post('/drivers/delivery/orders/$id/$step');
    return DeliveryOrder((r.data as Map).cast<String, dynamic>());
  }

  Future<DeliveryOrder> accept(int id) => _step(id, 'accept');
  Future<DeliveryOrder> pickedUp(int id) => _step(id, 'picked-up');
  Future<DeliveryOrder> arrived(int id) => _step(id, 'arrived');
  Future<DeliveryOrder> cancel(int id) => _step(id, 'cancel');
}
