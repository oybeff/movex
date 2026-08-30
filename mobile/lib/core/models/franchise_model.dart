/// Franchise ma'lumotlari modeli
class FranchiseModel {
  final int id;
  final String name;
  final String region;
  final String? address;
  final String? phone;
  final String? email;
  final int ownerId;
  final String status; // active, inactive, suspended
  final double? royaltyPercentage;
  final DateTime createdAt;
  final DateTime updatedAt;

  FranchiseModel({
    required this.id,
    required this.name,
    required this.region,
    this.address,
    this.phone,
    this.email,
    required this.ownerId,
    required this.status,
    this.royaltyPercentage,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FranchiseModel.fromJson(Map<String, dynamic> json) {
    return FranchiseModel(
      id: json['id'] as int,
      name: json['name'] as String,
      region: json['region'] as String,
      address: json['address'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      ownerId: json['owner_id'] as int,
      status: json['status'] as String,
      royaltyPercentage: json['royalty_percentage'] != null 
          ? (json['royalty_percentage'] as num).toDouble() 
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'region': region,
      'address': address,
      'phone': phone,
      'email': email,
      'owner_id': ownerId,
      'status': status,
      'royalty_percentage': royaltyPercentage,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

/// Franchise yaratish uchun model
class FranchiseCreateModel {
  final String name;
  final String region;
  final String? address;
  final String? phone;
  final String? email;
  final double? royaltyPercentage;

  FranchiseCreateModel({
    required this.name,
    required this.region,
    this.address,
    this.phone,
    this.email,
    this.royaltyPercentage,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'region': region,
      'address': address,
      'phone': phone,
      'email': email,
      'royalty_percentage': royaltyPercentage,
    };
  }
}

/// Franchise statistikasi modeli
class FranchiseStatsModel {
  final int franchiseId;
  final int totalEquipment;
  final int activeOrders;
  final int completedOrders;
  final double totalRevenue;
  final double totalRoyalty;
  final double monthlyRevenue;
  final double monthlyRoyalty;

  FranchiseStatsModel({
    required this.franchiseId,
    required this.totalEquipment,
    required this.activeOrders,
    required this.completedOrders,
    required this.totalRevenue,
    required this.totalRoyalty,
    required this.monthlyRevenue,
    required this.monthlyRoyalty,
  });

  factory FranchiseStatsModel.fromJson(Map<String, dynamic> json) {
    return FranchiseStatsModel(
      franchiseId: json['franchise_id'] as int,
      totalEquipment: json['total_equipment'] as int,
      activeOrders: json['active_orders'] as int,
      completedOrders: json['completed_orders'] as int,
      totalRevenue: (json['total_revenue'] as num).toDouble(),
      totalRoyalty: (json['total_royalty'] as num).toDouble(),
      monthlyRevenue: (json['monthly_revenue'] as num).toDouble(),
      monthlyRoyalty: (json['monthly_royalty'] as num).toDouble(),
    );
  }
}

