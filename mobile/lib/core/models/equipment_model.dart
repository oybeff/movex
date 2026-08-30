class EquipmentPhotoModel {
  final int id;
  final String url;
  final bool isPrimary;
  final DateTime createdAt;

  EquipmentPhotoModel({
    required this.id,
    required this.url,
    required this.isPrimary,
    required this.createdAt,
  });

  factory EquipmentPhotoModel.fromJson(Map<String, dynamic> json) {
    return EquipmentPhotoModel(
      id: json['id'] as int,
      url: json['url'] as String,
      isPrimary: json['is_primary'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class EquipmentModel {
  final int id;
  final String type;
  final String model;
  final int? year;
  final int? powerHp;
  final String? pricePerHour;
  final String? pricePerShift;
  final String pricePerDay;
  final String? deliveryPricePerKm;
  final String? address;
  final String? latitude;
  final String? longitude;
  final int? payloadKg;
  final String? dimensions;
  final String? description;
  final String? status;
  final bool? available;
  final int? companyId;
  final int ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<EquipmentPhotoModel> photos;

  EquipmentModel({
    required this.id,
    required this.type,
    required this.model,
    this.year,
    this.powerHp,
    this.pricePerHour,
    this.pricePerShift,
    required this.pricePerDay,
    this.deliveryPricePerKm,
    this.address,
    this.latitude,
    this.longitude,
    this.payloadKg,
    this.dimensions,
    this.description,
    this.status,
    this.available,
    this.companyId,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.photos = const [],
  });

  factory EquipmentModel.fromJson(Map<String, dynamic> json) {
    // Helper function to convert price to String
    String? _priceToString(dynamic value) {
      if (value == null) return null;
      if (value is String) return value;
      if (value is num) return value.toString();
      return value.toString();
    }

    return EquipmentModel(
      id: json['id'] as int,
      type: json['type'] as String,
      model: json['model'] as String,
      year: json['year'] as int?,
      powerHp: json['power_hp'] as int?,
      pricePerHour: _priceToString(json['price_per_hour']),
      pricePerShift: _priceToString(json['price_per_shift']),
      pricePerDay: _priceToString(json['price_per_day']) ?? '0',
      deliveryPricePerKm: _priceToString(json['delivery_price_per_km']),
      address: json['address'] as String?,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      payloadKg: json['payload_kg'] as int?,
      dimensions: json['dimensions'] as String?,
      description: json['description'] as String?,
      status: json['status'] as String?,
      available: json['available'] as bool?,
      companyId: json['company_id'] as int?,
      ownerId: json['owner_id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
      photos: (json['photos'] as List<dynamic>?)
              ?.map((e) => EquipmentPhotoModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class EquipmentCreateModel {
  final String type;
  final String model;
  final int? year;
  final int? powerHp;
  final double? pricePerHour;
  final double? pricePerShift;
  final double pricePerDay;
  final double? deliveryPricePerKm;
  final String? address;
  final double? latitude;
  final double? longitude;
  final int? payloadKg;
  final String? dimensions;
  final String? description;
  final String? status;
  final bool? available;
  final int? companyId;

  EquipmentCreateModel({
    required this.type,
    required this.model,
    this.year,
    this.powerHp,
    this.pricePerHour,
    this.pricePerShift,
    required this.pricePerDay,
    this.deliveryPricePerKm,
    this.address,
    this.latitude,
    this.longitude,
    this.payloadKg,
    this.dimensions,
    this.description,
    this.status = 'available',
    this.available = true,
    this.companyId,
  });

  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'model': model,
      'year': year,
      'power_hp': powerHp,
      'price_per_hour': pricePerHour,
      'price_per_shift': pricePerShift,
      'price_per_day': pricePerDay,
      'delivery_price_per_km': deliveryPricePerKm,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'payload_kg': payloadKg,
      'dimensions': dimensions,
      'description': description,
      'status': status,
      'available': available,
      'company_id': companyId,
    };
  }
}

class EquipmentUpdateModel {
  final String? type;
  final String? model;
  final int? year;
  final int? powerHp;
  final String? pricePerHour;
  final String? pricePerShift;
  final String? pricePerDay;
  final String? deliveryPricePerKm;
  final String? address;
  final String? latitude;
  final String? longitude;
  final int? payloadKg;
  final String? dimensions;
  final String? description;
  final String? status;
  final bool? available;
  final int? companyId;

  EquipmentUpdateModel({
    this.type,
    this.model,
    this.year,
    this.powerHp,
    this.pricePerHour,
    this.pricePerShift,
    this.pricePerDay,
    this.deliveryPricePerKm,
    this.address,
    this.latitude,
    this.longitude,
    this.payloadKg,
    this.dimensions,
    this.description,
    this.status,
    this.available,
    this.companyId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> data = {};

    if (type != null) data['type'] = type;
    if (model != null) data['model'] = model;
    if (year != null) data['year'] = year;
    if (powerHp != null) data['power_hp'] = powerHp;
    if (pricePerHour != null) data['price_per_hour'] = pricePerHour;
    if (pricePerShift != null) data['price_per_shift'] = pricePerShift;
    if (pricePerDay != null) data['price_per_day'] = pricePerDay;
    if (deliveryPricePerKm != null) data['delivery_price_per_km'] = deliveryPricePerKm;
    if (address != null) data['address'] = address;
    if (latitude != null) data['latitude'] = latitude;
    if (longitude != null) data['longitude'] = longitude;
    if (payloadKg != null) data['payload_kg'] = payloadKg;
    if (dimensions != null) data['dimensions'] = dimensions;
    if (description != null) data['description'] = description;
    if (status != null) data['status'] = status;
    if (available != null) data['available'] = available;
    if (companyId != null) data['company_id'] = companyId;

    return data;
  }
}

