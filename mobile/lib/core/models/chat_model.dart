class ChatModel {
  final int id;
  final int orderId;
  final DateTime createdAt;
  String? lastMessage;
  DateTime? lastMessageTime;
  int unreadCount;

  ChatModel({
    required this.id,
    required this.orderId,
    required this.createdAt,
    this.lastMessage,
    this.lastMessageTime,
    this.unreadCount = 0,
  });

  factory ChatModel.fromJson(Map<String, dynamic> json) {
    return ChatModel(
      id: json['id'] as int,
      orderId: json['order_id'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      lastMessage: json['last_message'] as String?,
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : null,
      unreadCount: json['unread_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'order_id': orderId,
      'created_at': createdAt.toIso8601String(),
      'last_message': lastMessage,
      'last_message_time': lastMessageTime?.toIso8601String(),
      'unread_count': unreadCount,
    };
  }
}

class ChatCreateModel {
  final int orderId;

  ChatCreateModel({
    required this.orderId,
  });

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
    };
  }
}

