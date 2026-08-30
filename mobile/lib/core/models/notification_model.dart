import 'package:easy_localization/easy_localization.dart';

import '../constants/equipment_types.dart';

class NotificationModel {
  final int id;
  final String type;
  final String title;
  final String? body;
  final int? orderId;

  /// Texnika turi kodi — ro'yxatda ikonka shu bo'yicha tanlanadi
  /// (EquipmentTypes.svgAsset).
  final String? equipmentType;

  /// Texnika modeli ("JCB 3CX"). Turi bilan birga sarlavhani yig'ish uchun.
  final String? equipmentModel;

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
    this.equipmentModel,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as int,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String?,
      orderId: json['order_id'] as int?,
      equipmentType: json['equipment_type'] as String?,
      equipmentModel: json['equipment_model'] as String?,
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
      equipmentModel: equipmentModel,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
    );
  }

  /// Ro'yxatda ko'rsatiladigan sarlavha.
  ///
  /// Serverdagi title bitta tilda qotib qolgan va unda tur KODI bo'lishi
  /// mumkin (eski yozuvlar). Shuning uchun tur va model ma'lum bo'lsa,
  /// sarlavhani foydalanuvchi tilida shu yerda yig'amiz; bo'lmasa —
  /// serverning title'iga qaytamiz.
  String get displayTitle {
    if (equipmentType == null) return title;

    final what = [EquipmentTypes.label(equipmentType!), equipmentModel]
        .where((p) => p != null && p.isNotEmpty)
        .join(' ');
    if (what.isEmpty) return title;

    const prefixes = {
      'order_created': 'notifications.order_created',
      'order_confirmed': 'notifications.order_confirmed',
      'order_rejected': 'notifications.order_rejected',
      'order_cancelled': 'notifications.order_cancelled',
      'order_completed': 'notifications.order_completed',
    };
    final key = prefixes[type];
    if (key == null) return title;

    return '${key.tr()}: $what';
  }
}
