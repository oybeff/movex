class NotificationModel {
  final int id;
  final String type;
  final String title;
  final String? body;
  final int? orderId;

  /// Texnika turi kodi — ro'yxatda ikonka shu bo'yicha tanlanadi
  /// (EquipmentTypes.svgAsset).
  final String? equipmentType;

  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.isRead,
    required this.createdAt,
    this.body,
    this.orderId,
    this.equipmentType,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      orderId: json['order_id'] as int?,
      equipmentType: json['equipment_type'] as String?,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  NotificationModel copyWith({bool? isRead}) {
    return NotificationModel(
      id: id,
      type: type,
      title: title,
      body: body,
      orderId: orderId,
      equipmentType: equipmentType,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }
}
