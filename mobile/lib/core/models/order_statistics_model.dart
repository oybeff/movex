class OrderStatisticsModel {
  final int totalOrders;
  final double totalIncome;
  final Map<String, int> ordersByStatus;
  final List<OrdersByDateModel> ordersByDate;
  final List<OrdersByEquipmentModel> ordersByEquipment;
  final double averageOrderValue;

  OrderStatisticsModel({
    required this.totalOrders,
    required this.totalIncome,
    required this.ordersByStatus,
    required this.ordersByDate,
    required this.ordersByEquipment,
    required this.averageOrderValue,
  });

  factory OrderStatisticsModel.fromJson(Map<String, dynamic> json) {
    return OrderStatisticsModel(
      totalOrders: json['total_orders'] as int,
      totalIncome: (json['total_income'] as num).toDouble(),
      ordersByStatus: Map<String, int>.from(json['orders_by_status'] as Map),
      ordersByDate: (json['orders_by_date'] as List)
          .map((e) => OrdersByDateModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      ordersByEquipment: (json['orders_by_equipment'] as List)
          .map((e) => OrdersByEquipmentModel.fromJson(e as Map<String, dynamic>))
          .toList(),
      averageOrderValue: (json['average_order_value'] as num).toDouble(),
    );
  }
}

class OrdersByDateModel {
  final String date;
  final int count;

  OrdersByDateModel({
    required this.date,
    required this.count,
  });

  factory OrdersByDateModel.fromJson(Map<String, dynamic> json) {
    return OrdersByDateModel(
      date: json['date'] as String,
      count: json['count'] as int,
    );
  }
}

class OrdersByEquipmentModel {
  final int equipmentId;
  final String equipmentName;
  final int count;
  final double income;

  OrdersByEquipmentModel({
    required this.equipmentId,
    required this.equipmentName,
    required this.count,
    required this.income,
  });

  factory OrdersByEquipmentModel.fromJson(Map<String, dynamic> json) {
    return OrdersByEquipmentModel(
      equipmentId: json['equipment_id'] as int,
      equipmentName: json['equipment_name'] as String,
      count: json['count'] as int,
      income: (json['income'] as num).toDouble(),
    );
  }
}

