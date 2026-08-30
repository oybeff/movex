class ContactMethodModel {
  final int id;
  final String type; // phone, email, telegram, whatsapp, website, sms
  final String label;
  final String value;
  final String? icon;
  final int order;
  final int isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContactMethodModel({
    required this.id,
    required this.type,
    required this.label,
    required this.value,
    this.icon,
    required this.order,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ContactMethodModel.fromJson(Map<String, dynamic> json) {
    return ContactMethodModel(
      id: json['id'] as int,
      type: json['type'] as String,
      label: json['label'] as String,
      value: json['value'] as String,
      icon: json['icon'] as String?,
      order: json['order'] as int,
      isActive: json['is_active'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'label': label,
      'value': value,
      'icon': icon,
      'order': order,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }
}

