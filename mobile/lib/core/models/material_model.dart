import '../constants/material_types.dart';

double? _toDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Sotuvchining tovari: "G'isht M-100, 900 so'm/dona".
///
/// Texnikadan farqi — bu IJARA emas, savdo: narx birlik uchun, muddat
/// yo'q. Shuning uchun alohida model, EquipmentModel ga tiqilmagan.
class MaterialProductModel {
  final int id;
  final int ownerId;
  final String materialType;
  final String title;
  final String? description;

  /// piece | bag | tonne | m3
  final String unit;

  /// Bitta birlikning og'irligi — MASHINA shunga qarab tanlanadi.
  final double unitWeightKg;

  final double pricePerUnit;
  final double minQuantity;
  final double? availableQuantity;
  final double? deliveryPricePerKm;

  final String? address;
  final double? latitude;
  final double? longitude;

  /// pending | approved | rejected
  final String status;
  final String? moderationComment;

  final List<String> photos;
  final String? ownerName;
  final double? distanceKm;

  const MaterialProductModel({
    required this.id,
    required this.ownerId,
    required this.materialType,
    required this.title,
    required this.unit,
    required this.unitWeightKg,
    required this.pricePerUnit,
    required this.minQuantity,
    required this.status,
    this.description,
    this.availableQuantity,
    this.deliveryPricePerKm,
    this.address,
    this.latitude,
    this.longitude,
    this.moderationComment,
    this.photos = const [],
    this.ownerName,
    this.distanceKm,
  });

  bool get isApproved => status == 'approved';
  bool get isPending => status == 'pending';
  bool get isRejected => status == 'rejected';

  String get typeLabel => MaterialTypes.label(materialType);
  String get unitLabel => MaterialTypes.unitLabel(unit);

  factory MaterialProductModel.fromJson(Map<String, dynamic> json) {
    return MaterialProductModel(
      id: json['id'] as int,
      ownerId: json['owner_id'] as int,
      materialType: json['material_type'] as String? ?? 'other',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      unit: json['unit'] as String? ?? 'piece',
      // Serverdan son SATR bo'lib keladi ("3.500") — num deb o'qib bo'lmaydi.
      unitWeightKg: _toDouble(json['unit_weight_kg']) ?? 1,
      pricePerUnit: _toDouble(json['price_per_unit']) ?? 0,
      minQuantity: _toDouble(json['min_quantity']) ?? 1,
      availableQuantity: _toDouble(json['available_quantity']),
      deliveryPricePerKm: _toDouble(json['delivery_price_per_km']),
      address: json['address'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      status: json['status'] as String? ?? 'pending',
      moderationComment: json['moderation_comment'] as String?,
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => (e as Map<String, dynamic>)['url'] as String)
              .toList() ??
          const [],
      ownerName: json['owner_name'] as String?,
      distanceKm: _toDouble(json['distance_km']),
    );
  }
}

/// Ekrandagi jonli hisob. HAMMASI SERVERDAN keladi.
///
/// Ilova o'zi hisoblamaydi ataylab: formula ikki joyda bo'lsa, ekranda
/// bir summa ko'rinib, balansdan boshqasi yechilardi.
class MaterialQuoteModel {
  final double quantity;
  final String unit;
  final double pricePerUnit;
  final double goodsAmount;

  final double weightKg;
  final String vehicleCode;
  final int vehicleCapacityKg;
  final int trips;

  final double? deliveryDistanceKm;
  final double deliveryFee;

  /// Xaridor to'laydigan summa. Ulush bunga KIRMAYDI — uni sotuvchi
  /// to'laydi, xuddi ijaradagidek.
  final double total;

  const MaterialQuoteModel({
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.goodsAmount,
    required this.weightKg,
    required this.vehicleCode,
    required this.vehicleCapacityKg,
    required this.trips,
    required this.deliveryFee,
    required this.total,
    this.deliveryDistanceKm,
  });

  double get weightTonnes => weightKg / 1000;

  factory MaterialQuoteModel.fromJson(Map<String, dynamic> json) {
    return MaterialQuoteModel(
      quantity: _toDouble(json['quantity']) ?? 0,
      unit: json['unit'] as String? ?? 'piece',
      pricePerUnit: _toDouble(json['price_per_unit']) ?? 0,
      goodsAmount: _toDouble(json['goods_amount']) ?? 0,
      weightKg: _toDouble(json['weight_kg']) ?? 0,
      vehicleCode: json['vehicle_code'] as String? ?? 'labo',
      vehicleCapacityKg: json['vehicle_capacity_kg'] as int? ?? 0,
      trips: json['trips'] as int? ?? 1,
      deliveryDistanceKm: _toDouble(json['delivery_distance_km']),
      deliveryFee: _toDouble(json['delivery_fee']) ?? 0,
      total: _toDouble(json['total']) ?? 0,
    );
  }
}

class DeliveryVehicleModel {
  final String code;
  final int capacityKg;

  const DeliveryVehicleModel({required this.code, required this.capacityKg});

  double get capacityTonnes => capacityKg / 1000;

  factory DeliveryVehicleModel.fromJson(Map<String, dynamic> json) =>
      DeliveryVehicleModel(
        code: json['code'] as String,
        capacityKg: json['capacity_kg'] as int,
      );
}

/// Material buyurtmasi.
class MaterialOrderModel {
  final int id;
  final int buyerId;
  final int sellerId;
  final int productId;

  final double quantity;
  final String unit;
  final double pricePerUnit;
  final double goodsAmount;

  final double weightKg;
  final String vehicleCode;
  final int trips;

  final double? deliveryDistanceKm;
  final double deliveryFee;
  final double commission;
  final double totalAmount;

  final String? deliveryAddress;
  final String? comment;

  /// pending | confirmed | delivered | cancelled | rejected
  final String status;
  final DateTime createdAt;

  final String? productTitle;
  final String? materialType;
  final String? buyerName;
  final String? sellerName;

  const MaterialOrderModel({
    required this.id,
    required this.buyerId,
    required this.sellerId,
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.pricePerUnit,
    required this.goodsAmount,
    required this.weightKg,
    required this.vehicleCode,
    required this.trips,
    required this.deliveryFee,
    required this.commission,
    required this.totalAmount,
    required this.status,
    required this.createdAt,
    this.deliveryDistanceKm,
    this.deliveryAddress,
    this.comment,
    this.productTitle,
    this.materialType,
    this.buyerName,
    this.sellerName,
  });

  bool get isPending => status == 'pending';
  bool get isConfirmed => status == 'confirmed';
  bool get isDelivered => status == 'delivered';
  bool get isClosed => status == 'cancelled' || status == 'rejected';

  String get unitLabel => MaterialTypes.unitLabel(unit);

  factory MaterialOrderModel.fromJson(Map<String, dynamic> json) {
    return MaterialOrderModel(
      id: json['id'] as int,
      buyerId: json['buyer_id'] as int,
      sellerId: json['seller_id'] as int,
      productId: json['product_id'] as int,
      quantity: _toDouble(json['quantity']) ?? 0,
      unit: json['unit'] as String? ?? 'piece',
      pricePerUnit: _toDouble(json['price_per_unit']) ?? 0,
      goodsAmount: _toDouble(json['goods_amount']) ?? 0,
      weightKg: _toDouble(json['weight_kg']) ?? 0,
      vehicleCode: json['vehicle_code'] as String? ?? 'labo',
      trips: json['trips'] as int? ?? 1,
      deliveryDistanceKm: _toDouble(json['delivery_distance_km']),
      deliveryFee: _toDouble(json['delivery_fee']) ?? 0,
      commission: _toDouble(json['commission']) ?? 0,
      totalAmount: _toDouble(json['total_amount']) ?? 0,
      deliveryAddress: json['delivery_address'] as String?,
      comment: json['comment'] as String?,
      status: json['status'] as String? ?? 'pending',
      createdAt: DateTime.parse(json['created_at'] as String),
      productTitle: json['product_title'] as String?,
      materialType: json['material_type'] as String?,
      buyerName: json['buyer_name'] as String?,
      sellerName: json['seller_name'] as String?,
    );
  }
}
