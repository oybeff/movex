import 'package:dio/dio.dart';

import '../../../core/network/dio_client.dart';

/// Тарифный заказ «как такси» (второй макет, 12.11.2026).
///
/// Здесь нет ни одного расчёта денег. Цену тарифа, итог за часы и
/// навесное считает сервер (GET /requests/tariffs), и тот же код
/// пересчитывает сумму при создании заказа. Приложение только показывает.
class TaxiService {
  final Dio _dio = DioClient.create();

  /// Типы техники, для которых админ задал тарифы.
  Future<List<String>> tariffTypes() async {
    final r = await _dio.get('/requests/tariffs/types');
    return (r.data as List).map((e) => e.toString()).toList();
  }

  Future<List<TariffQuote>> tariffs(
    String type, {
    int? hours,
    int? attachmentId,
  }) async {
    final r = await _dio.get('/requests/tariffs', queryParameters: {
      'equipment_type': type,
      if (hours != null) 'hours': hours,
      if (attachmentId != null) 'attachment_id': attachmentId,
    });
    return (r.data as List)
        .map((e) => TariffQuote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TaxiAttachment>> attachments(String type) async {
    final r = await _dio.get('/requests/attachments',
        queryParameters: {'equipment_type': type});
    return (r.data as List)
        .map((e) => TaxiAttachment.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Создаёт заказ. Суммы в теле НЕТ — её считает сервер по тарифу.
  /// Оплата с баланса: сумма сразу замораживается (не хватает — 400).
  /// Наличными: ничего не замораживается.
  Future<TaxiRequest> createOrder({
    required String equipmentType,
    required String tariff,
    required int hours,
    required DateTime start,
    required double toLat,
    required double toLon,
    String? toAddress,
    double? fromLat,
    double? fromLon,
    String? fromAddress,
    int? attachmentId,
    required String paymentMethod,
    String? comment,
    int surgePercent = 0,
    int? cardId,
  }) async {
    final day = _date(start);
    final r = await _dio.post('/requests/', data: {
      'equipment_type': equipmentType,
      'mode': 'quick',
      'tariff': tariff,
      'hours': hours,
      'payment_method': paymentMethod,
      'start_date': day,
      'end_date': day,
      'start_time':
          '${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}:00',
      'delivery_latitude': toLat,
      'delivery_longitude': toLon,
      if (toAddress != null && toAddress.isNotEmpty) 'delivery_address': toAddress,
      if (fromLat != null) 'origin_latitude': fromLat,
      if (fromLon != null) 'origin_longitude': fromLon,
      if (fromAddress != null && fromAddress.isNotEmpty) 'origin_address': fromAddress,
      if (attachmentId != null) 'attachment_id': attachmentId,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      if (surgePercent > 0) 'surge_percent': surgePercent,
      if (cardId != null) 'card_id': cardId,
    });
    return TaxiRequest.fromJson(r.data as Map<String, dynamic>);
  }

  Future<TaxiRequest> getRequest(int id) async {
    final r = await _dio.get('/requests/$id');
    return TaxiRequest.fromJson(r.data as Map<String, dynamic>);
  }

  Future<List<TaxiRequest>> myRequests() async {
    final r = await _dio.get('/requests/');
    return (r.data as List)
        .map((e) => TaxiRequest.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> cancelRequest(int id) async {
    await _dio.post('/requests/$id/cancel');
  }

  Future<Map<String, dynamic>> getOrder(int id) async {
    final r = await _dio.get('/orders/$id');
    return r.data as Map<String, dynamic>;
  }

  /// [reason] — E6, только для отмены: plans, long_wait, wrong_address, other.
  Future<void> setOrderStatus(int id, String status, {String? reason}) async {
    await _dio.put('/orders/$id', data: {'status': status, if (reason != null) 'cancel_reason': reason});
  }

  Future<Map<String, dynamic>> getEquipment(int id) async {
    final r = await _dio.get('/equipment/$id');
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getUser(int id) async {
    final r = await _dio.get('/users/$id');
    return r.data as Map<String, dynamic>;
  }

  /// Карточка исполнителя (экран 8): имя, рейтинг, машина, госномер, ETA.
  Future<TaxiExecutor> executor(int orderId) async {
    final r = await _dio.get('/orders/$orderId/executor');
    return TaxiExecutor.fromJson(r.data as Map<String, dynamic>);
  }

  /// B3 «So'rov yuborish»: просьба продлить на [hours] часов. Деньги и
  /// часы добавятся, когда владелец согласится.
  Future<Map<String, dynamic>> extend(int orderId, int hours) async {
    final r = await _dio.post('/orders/$orderId/extend', data: {'hours': hours});
    return r.data as Map<String, dynamic>;
  }

  /// M1–M3: «Buyurtmalarim» одним запросом.
  Future<List<OrderCard>> clientCards(String lang) async {
    final r = await _dio.get('/orders/client-cards', queryParameters: {'lang': lang});
    return [for (final j in r.data as List) OrderCard.fromJson(j as Map<String, dynamic>)];
  }

  /// B5: фото грузится отдельно, сервер отдаёт свой адрес.
  Future<String> uploadProblemPhoto(String path, String name) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)});
    final r = await _dio.post('/orders/problem-photo', data: form);
    return (r.data as Map<String, dynamic>)['url'] as String;
  }

  /// Тот же загрузчик для браузера, где пути к файлу нет — только байты.
  Future<String> uploadProblemPhotoBytes(List<int> bytes, String name) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)});
    final r = await _dio.post('/orders/problem-photo', data: form);
    return (r.data as Map<String, dynamic>)['url'] as String;
  }

  /// B5 «Yuborish». [reason]: not_arrived, wrong_equipment, poor_quality,
  /// price_differs, other.
  Future<void> reportProblem(int orderId,
      {required String reason, String? comment, List<String> photos = const []}) async {
    await _dio.post('/orders/$orderId/problem', data: {
      'reason': reason,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      'photos': photos,
    });
  }

  /// Чат по заказу: найти существующий или создать.
  Future<int> chatFor(int orderId) async {
    final r = await _dio.get('/chats/');
    for (final c in (r.data as List)) {
      final m = c as Map<String, dynamic>;
      if (m['order_id'] == orderId) return m['id'] as int;
    }
    final created = await _dio.post('/chats/', data: {'order_id': orderId});
    return (created.data as Map<String, dynamic>)['id'] as int;
  }

  Future<void> review({
    required int equipmentId,
    required int rating,
    String? comment,
  }) async {
    await _dio.post('/reviews/', data: {
      'equipment_id': equipmentId,
      'rating': rating,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
    });
  }

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

double _num(dynamic v) => v == null ? 0 : double.parse(v.toString());

class TariffQuote {
  TariffQuote({
    required this.tier,
    required this.pricePerHour,
    required this.attachmentPerHour,
    required this.minHours,
    required this.hours,
    required this.total,
    this.etaMinutes,
  });

  factory TariffQuote.fromJson(Map<String, dynamic> j) => TariffQuote(
        tier: j['tier'] as String,
        pricePerHour: _num(j['price_per_hour']),
        attachmentPerHour: _num(j['attachment_per_hour']),
        minHours: j['min_hours'] as int,
        hours: j['hours'] as int,
        total: _num(j['total']),
        etaMinutes: j['eta_minutes'] as int?,
      );

  final String tier;
  final double pricePerHour;
  final double attachmentPerHour;
  final int minHours;
  final int hours;
  final double total;

  /// «N daqiqada keladi» — задаёт админ; null — подпись без минут.
  final int? etaMinutes;
}

class TaxiExecutor {
  TaxiExecutor({
    this.name,
    this.initials,
    this.phone,
    this.rating,
    this.ordersDone = 0,
    this.model,
    this.type,
    this.plate,
    this.etaMinutes,
    this.lat,
    this.lon,
    this.destLat,
    this.destLon,
  });

  factory TaxiExecutor.fromJson(Map<String, dynamic> j) => TaxiExecutor(
        name: j['owner_name'] as String?,
        initials: j['owner_initials'] as String?,
        phone: j['owner_phone'] as String?,
        rating: j['rating'] == null ? null : _num(j['rating']),
        ordersDone: (j['orders_done'] as int?) ?? 0,
        model: j['equipment_model'] as String?,
        type: j['equipment_type'] as String?,
        plate: j['plate_number'] as String?,
        etaMinutes: j['eta_minutes'] as int?,
        lat: j['equipment_latitude'] == null ? null : _num(j['equipment_latitude']),
        lon: j['equipment_longitude'] == null ? null : _num(j['equipment_longitude']),
        destLat: j['destination_latitude'] == null ? null : _num(j['destination_latitude']),
        destLon: j['destination_longitude'] == null ? null : _num(j['destination_longitude']),
      );

  final String? name;
  final String? initials;
  final String? phone;
  final double? rating;
  final int ordersDone;
  final String? model;
  final String? type;
  final String? plate;
  final int? etaMinutes;

  /// Точка техники, которую владелец выбрал при добавлении (живого
  /// слежения нет) — по ней рисуется машина на карте шагов 8–9.
  final double? lat;
  final double? lon;

  /// Куда едет техника — точка «Qayerdan» заказа (макет, кадр 8).
  final double? destLat;
  final double? destLon;
}

class TaxiAttachment {
  TaxiAttachment({required this.id, required this.name, required this.pricePerHour});

  factory TaxiAttachment.fromJson(Map<String, dynamic> j) => TaxiAttachment(
        id: j['id'] as int,
        name: j['name'] as String,
        pricePerHour: _num(j['price_per_hour']),
      );

  final int id;
  final String name;
  final double pricePerHour;
}

/// Заявка из /requests/ — только поля, нужные потоку.
class TaxiRequest {
  TaxiRequest({
    required this.id,
    required this.status,
    required this.mode,
    required this.equipmentType,
    this.tariff,
    this.hours,
    this.budget,
    this.orderId,
    this.paymentMethod = 'balance',
    this.fromAddress,
    this.toAddress,
    this.startTime,
    this.toLat,
    this.toLon,
    this.attachmentId,
    this.attachmentPrice,
    this.fromLat,
    this.fromLon,
  });

  factory TaxiRequest.fromJson(Map<String, dynamic> j) => TaxiRequest(
        id: j['id'] as int,
        status: j['status'] as String,
        mode: (j['mode'] ?? 'tender') as String,
        equipmentType: j['equipment_type'] as String,
        tariff: j['tariff'] as String?,
        hours: j['hours'] as int?,
        budget: j['budget'] == null ? null : _num(j['budget']),
        orderId: j['order_id'] as int?,
        paymentMethod: (j['payment_method'] ?? 'balance') as String,
        fromAddress: j['origin_address'] as String?,
        toAddress: j['delivery_address'] as String?,
        startTime: j['start_time'] as String?,
        toLat: double.tryParse('${j['delivery_latitude']}'),
        toLon: double.tryParse('${j['delivery_longitude']}'),
        attachmentId: j['attachment_id'] as int?,
        attachmentPrice: j['attachment_price'] == null ? null : _num(j['attachment_price']),
        fromLat: double.tryParse('${j['origin_latitude']}'),
        fromLon: double.tryParse('${j['origin_longitude']}'),
      );

  final int id;
  final String status;
  final String mode;
  final String equipmentType;
  final String? tariff;
  final int? hours;
  final double? budget;
  final int? orderId;
  final String paymentMethod;
  final String? fromAddress;
  final String? toAddress;
  final String? startTime;
  final double? toLat;
  final double? toLon;
  final int? attachmentId;
  /// Надбавка навесного за час, как была в момент заказа.
  final double? attachmentPrice;
  final double? fromLat;
  final double? fromLon;

  bool get isTariff => tariff != null;
}


/// Карточка «Buyurtmalarim» (GET /orders/client-cards).
class OrderCard {
  OrderCard(this.j);

  factory OrderCard.fromJson(Map<String, dynamic> j) => OrderCard(j);

  final Map<String, dynamic> j;

  bool get isRequest => j['kind'] == 'request';
  int? get orderId => j['order_id'] as int?;
  int? get requestId => j['request_id'] as int?;
  /// searching, scheduled, on_the_way, working, awaiting_confirm,
  /// completed, cancelled.
  String get stage => j['stage'] as String;
  bool get isActive => stage != 'completed' && stage != 'cancelled';
  String get type => j['equipment_type'] as String;
  String? get model => j['equipment_model'] as String?;
  String? get plate => j['plate_number'] as String?;
  String? get ownerName => j['owner_name'] as String?;
  String? get ownerInitials => j['owner_initials'] as String?;
  String? get ownerPhone => j['owner_phone'] as String?;
  double? get ownerRating => (j['owner_rating'] as num?)?.toDouble();
  int? get myRating => j['my_rating'] as int?;
  int? get hours => j['hours'] as int?;
  String? get tariff => j['tariff'] as String?;
  String? get fromAddress => j['from_address'] as String?;
  String? get toAddress => j['to_address'] as String?;
  double? get fromLat => double.tryParse('${j['from_lat']}');
  double? get fromLon => double.tryParse('${j['from_lon']}');
  double? get toLat => double.tryParse('${j['to_lat']}');
  double? get toLon => double.tryParse('${j['to_lon']}');
  double get total => _num(j['total']);
  double get deliveryFee => _num(j['delivery_fee']);
  bool get cash => j['payment_method'] == 'cash';
  String get paymentMethod => (j['payment_method'] ?? 'balance') as String;
  String? get cardLabel => j['card_label'] as String?;
  int? get attachmentId => j['attachment_id'] as int?;
  String? get attachmentName => j['attachment_name'] as String?;
  double get attachmentPrice => _num(j['attachment_price']);

  DateTime? _dt(String k) => DateTime.tryParse('${j[k]}')?.toLocal();
  DateTime? get startedAt => _dt('started_at');
  DateTime? get finishedAt => _dt('finished_at');
  DateTime? get createdAt => _dt('created_at');

  /// Когда назначено: дата заказа + время начала.
  DateTime? get startAt {
    final d = DateTime.tryParse('${j['start_date']}');
    if (d == null) return createdAt;
    final t = (j['start_time'] as String?)?.split(':');
    return DateTime(d.year, d.month, d.day,
        t == null ? 0 : int.parse(t[0]), t == null || t.length < 2 ? 0 : int.parse(t[1]));
  }

  /// Для «Qayta buyurtma»: та же заявка, что создаёт поток.
  TaxiRequest asRequest() => TaxiRequest(
        id: requestId ?? 0,
        status: 'repeat',
        mode: 'quick',
        equipmentType: type,
        tariff: tariff,
        hours: hours,
        paymentMethod: paymentMethod,
        fromAddress: fromAddress,
        toAddress: toAddress,
        toLat: toLat,
        toLon: toLon,
        fromLat: fromLat,
        fromLon: fromLon,
        attachmentId: attachmentId,
      );
}

/// Что сделать главной после экранов «Buyurtmalarim»: показать живой
/// заказ («Kuzatish») или заказать то же самое снова.
class TaxiNav {
  const TaxiNav.track() : repeat = null;
  const TaxiNav.repeat(this.repeat);

  final TaxiRequest? repeat;
}

/// Сохранённый адрес (Pr4). [kind]: home, work, site, other.
class SavedAddress {
  SavedAddress({
    this.id,
    required this.kind,
    required this.title,
    required this.address,
    required this.lat,
    required this.lon,
  });

  factory SavedAddress.fromJson(Map<String, dynamic> j) => SavedAddress(
        id: j['id'] as int,
        kind: j['kind'] as String,
        title: j['title'] as String,
        address: j['address'] as String,
        lat: (j['latitude'] as num).toDouble(),
        lon: (j['longitude'] as num).toDouble(),
      );

  final int? id;
  final String kind;
  final String title;
  final String address;
  final double lat;
  final double lon;

  Map<String, dynamic> toJson() =>
      {'kind': kind, 'title': title, 'address': address, 'latitude': lat, 'longitude': lon};

  /// Иконка по типу — как в макете Pr4.
  String get icon => switch (kind) { 'home' => 'home', 'work' => 'briefcase', 'site' => 'building', _ => 'point_b' };
}

/// Профиль клиента: фото и сохранённые адреса.
class ProfileApi {
  final Dio _dio = DioClient.create();

  Future<List<SavedAddress>> addresses() async {
    final r = await _dio.get('/users/me/addresses');
    return [for (final j in r.data as List) SavedAddress.fromJson(j as Map<String, dynamic>)];
  }

  Future<void> saveAddress(SavedAddress a) async {
    if (a.id == null) {
      await _dio.post('/users/me/addresses', data: a.toJson());
    } else {
      await _dio.put('/users/me/addresses/${a.id}', data: a.toJson());
    }
  }

  Future<void> deleteAddress(int id) async {
    await _dio.delete('/users/me/addresses/$id');
  }

  Future<String?> uploadAvatar(List<int> bytes, String name) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)});
    final r = await _dio.post('/users/me/avatar', data: form);
    return (r.data as Map<String, dynamic>)['avatar_url'] as String?;
  }
}
