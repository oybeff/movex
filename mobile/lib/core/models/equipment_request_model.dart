import '../constants/equipment_types.dart';

/// Egasining zayavkaga javobi: qaysi mashina va qancha narxga.
class RequestOfferModel {
  final int id;
  final int requestId;
  final int ownerId;
  final int equipmentId;

  /// Egasi so'ragan KUNLIK narx.
  final double pricePerDay;
  final String? comment;

  /// pending | accepted | rejected | withdrawn
  final String status;
  final DateTime createdAt;

  final String? equipmentType;
  final String? equipmentModel;
  final String? ownerName;

  /// Kunlik narx * kunlar. Komissiya va yetkazib berish BUNGA KIRMAYDI —
  /// to'liq summa buyurtma yaratilganda serverda hisoblanadi, shuning uchun
  /// ekranda buni "taxminiy" deb ko'rsatish kerak.
  final double? estimatedSubtotal;

  const RequestOfferModel({
    required this.id,
    required this.requestId,
    required this.ownerId,
    required this.equipmentId,
    required this.pricePerDay,
    required this.status,
    required this.createdAt,
    this.comment,
    this.equipmentType,
    this.equipmentModel,
    this.ownerName,
    this.estimatedSubtotal,
  });

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  factory RequestOfferModel.fromJson(Map<String, dynamic> json) {
    return RequestOfferModel(
      id: json['id'] as int,
      requestId: json['request_id'] as int,
      ownerId: json['owner_id'] as int,
      equipmentId: json['equipment_id'] as int,
      pricePerDay: _toDouble(json['price_per_day']) ?? 0,
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      equipmentType: json['equipment_type'] as String?,
      equipmentModel: json['equipment_model'] as String?,
      ownerName: json['owner_name'] as String?,
      estimatedSubtotal: _toDouble(json['estimated_subtotal']),
    );
  }

  bool get isPending => status == 'pending';

  /// "Ekskavator Komatsu PC200" — foydalanuvchi tilida.
  String get equipmentLabel => [
        if (equipmentType != null) EquipmentTypes.label(equipmentType),
        if (equipmentModel != null && equipmentModel!.isNotEmpty) equipmentModel,
      ].join(' ');
}

/// Mijozning texnikaga bo'lgan zayavkasi.
class EquipmentRequestModel {
  final int id;
  final int clientId;

  /// Ma'lumotnomadagi KOD ('excavator'). Ekranda EquipmentTypes.label orqali.
  final String equipmentType;

  final DateTime startDate;
  final DateTime endDate;

  final String deliveryLatitude;
  final String deliveryLongitude;
  final String? deliveryAddress;

  /// Mijozning mo'ljali. Bo'sh bo'lishi mumkin — "narxni o'zingiz ayting".
  final double? budget;
  final String? comment;

  /// open | assigned | cancelled | expired
  final String status;

  final int? selectedOfferId;
  final int? orderId;
  final DateTime? expiresAt;
  final DateTime createdAt;

  /// Ro'yxatda "3 ta taklif" deb ko'rsatish uchun
  final int offersCount;

  /// Egaga: zayavka nuqtasigacha masofa, km
  final double? distanceKm;

  final List<RequestOfferModel> offers;

  const EquipmentRequestModel({
    required this.id,
    required this.clientId,
    required this.equipmentType,
    required this.startDate,
    required this.endDate,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    required this.status,
    required this.createdAt,
    this.deliveryAddress,
    this.budget,
    this.comment,
    this.selectedOfferId,
    this.orderId,
    this.expiresAt,
    this.offersCount = 0,
    this.distanceKm,
    this.offers = const [],
  });

  factory EquipmentRequestModel.fromJson(Map<String, dynamic> json) {
    return EquipmentRequestModel(
      id: json['id'] as int,
      clientId: json['client_id'] as int,
      equipmentType: json['equipment_type'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      deliveryLatitude: json['delivery_latitude'].toString(),
      deliveryLongitude: json['delivery_longitude'].toString(),
      deliveryAddress: json['delivery_address'] as String?,
      budget: RequestOfferModel._toDouble(json['budget']),
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'open',
      selectedOfferId: json['selected_offer_id'] as int?,
      orderId: json['order_id'] as int?,
      expiresAt: json['expires_at'] == null
          ? null
          : DateTime.parse(json['expires_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      offersCount: json['offers_count'] as int? ?? 0,
      distanceKm: RequestOfferModel._toDouble(json['distance_km']),
      offers: (json['offers'] as List<dynamic>?)
              ?.map((e) => RequestOfferModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  bool get isOpen => status == 'open';

  int get rentalDays => endDate.difference(startDate).inDays + 1;

  String get typeLabel => EquipmentTypes.label(equipmentType);
}

/// Qidiruv va xabarnoma radiusi.
class SearchAreaModel {
  final double? latitude;
  final double? longitude;
  final int radiusKm;

  const SearchAreaModel({
    required this.radiusKm,
    this.latitude,
    this.longitude,
  });

  factory SearchAreaModel.fromJson(Map<String, dynamic> json) {
    return SearchAreaModel(
      latitude: RequestOfferModel._toDouble(json['latitude']),
      longitude: RequestOfferModel._toDouble(json['longitude']),
      radiusKm: json['radius_km'] as int? ?? 100,
    );
  }

  bool get hasPoint => latitude != null && longitude != null;
}
