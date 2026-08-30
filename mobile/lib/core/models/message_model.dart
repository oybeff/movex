class MessageModel {
  final int id;
  final int chatId;
  final int senderId;
  final String messageText;
  final DateTime sentAt;

  MessageModel({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.messageText,
    required this.sentAt,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      id: json['id'] as int,
      chatId: json['chat_id'] as int,
      senderId: json['sender_id'] as int,
      messageText: json['message_text'] as String,
      sentAt: DateTime.parse(json['sent_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'chat_id': chatId,
      'sender_id': senderId,
      'message_text': messageText,
      'sent_at': sentAt.toIso8601String(),
    };
  }
}

class MessageCreateModel {
  final int chatId;
  final String messageText;

  MessageCreateModel({
    required this.chatId,
    required this.messageText,
  });

  Map<String, dynamic> toJson() {
    return {
      'chat_id': chatId,
      'message_text': messageText,
    };
  }
}

