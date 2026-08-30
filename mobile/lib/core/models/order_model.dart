class OrderModel {
  final int id;
  final int userId;
  final int equipmentId;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final double totalAmount;
  final double commission;
  final String deliveryLatitude;
  final String deliveryLongitude;
  final String? deliveryAddress;
  final double? deliveryDistance;
  final double? deliveryFee;
  final DateTime createdAt;
  final DateTime updatedAt;

  OrderModel({
    required this.id,
    required this.userId,
    required this.equipmentId,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.totalAmount,
    required this.commission,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    this.deliveryAddress,
    this.deliveryDistance,
    this.deliveryFee,
    required this.createdAt,
    required this.updatedAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as int,
      userId: json['user_id'] as int,
      equipmentId: json['equipment_id'] as int,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      status: json['status'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      commission: (json['commission'] as num).toDouble(),
      deliveryLatitude: json['delivery_latitude'] as String,
      deliveryLongitude: json['delivery_longitude'] as String,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryDistance: json['delivery_distance'] != null ? (json['delivery_distance'] as num).toDouble() : null,
      deliveryFee: json['delivery_fee'] != null ? (json['delivery_fee'] as num).toDouble() : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'equipment_id': equipmentId,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'status': status,
      'total_amount': totalAmount,
      'commission': commission,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'delivery_address': deliveryAddress,
      'delivery_distance': deliveryDistance,
      'delivery_fee': deliveryFee,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

class OrderCreateModel {
  final int equipmentId;
  final DateTime startDate;
  final DateTime endDate;
  final double totalAmount;
  final double commission;
  final String deliveryLatitude;
  final String deliveryLongitude;
  final String? deliveryAddress;
  final double? deliveryDistance;
  final double? deliveryFee;

  OrderCreateModel({
    required this.equipmentId,
    required this.startDate,
    required this.endDate,
    required this.totalAmount,
    required this.commission,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    this.deliveryAddress,
    this.deliveryDistance,
    this.deliveryFee,
  });

  Map<String, dynamic> toJson() {
    return {
      'equipment_id': equipmentId,
      'start_date': startDate.toIso8601String().split('T')[0],
      'end_date': endDate.toIso8601String().split('T')[0],
      'total_amount': totalAmount,
      'commission': commission,
      'delivery_latitude': deliveryLatitude,
      'delivery_longitude': deliveryLongitude,
      'delivery_address': deliveryAddress,
      'delivery_distance': deliveryDistance,
      'delivery_fee': deliveryFee,
    };
  }
}

