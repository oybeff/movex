import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/chat_model.dart';
import '../models/message_model.dart';

class ChatService {
  final Dio _dio = DioClient.create();

  /// Barcha chatlarni olish
  Future<List<ChatModel>> getChats({
    int skip = 0,
    int limit = 100,
  }) async {
    try {
      final response = await _dio.get(
        '/chats/',
        queryParameters: {
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      final chats = data.map((e) => ChatModel.fromJson(e as Map<String, dynamic>)).toList();

      // Har bir chat uchun oxirgi xabarni olish
      for (var chat in chats) {
        try {
          final messages = await getMessagesForChat(chat.id, limit: 1);
          if (messages.isNotEmpty) {
            chat.lastMessage = messages.first.messageText;
            chat.lastMessageTime = messages.first.sentAt;
          }
        } catch (e) {
          print('Error getting last message for chat ${chat.id}: $e');
        }
      }

      return chats;
    } catch (e) {
      print('Get chats error: $e');
      rethrow;
    }
  }

  /// Bitta chatni olish
  Future<ChatModel> getChat(int chatId) async {
    try {
      final response = await _dio.get('/chats/$chatId');
      return ChatModel.fromJson(response.data);
    } catch (e) {
      print('Get chat error: $e');
      rethrow;
    }
  }

  /// Yangi chat yaratish
  Future<ChatModel> createChat(ChatCreateModel chat) async {
    try {
      final response = await _dio.post(
        '/chats/',
        data: chat.toJson(),
      );
      return ChatModel.fromJson(response.data);
    } catch (e) {
      print('Create chat error: $e');
      rethrow;
    }
  }

  /// Chatni o'chirish
  Future<void> deleteChat(int chatId) async {
    try {
      await _dio.delete('/chats/$chatId');
    } catch (e) {
      print('Delete chat error: $e');
      rethrow;
    }
  }

  /// Chat uchun xabarlarni olish
  Future<List<MessageModel>> getMessagesForChat(int chatId, {int skip = 0, int limit = 100}) async {
    try {
      final response = await _dio.get(
        '/messages/',
        queryParameters: {
          'chat_id': chatId,
          'skip': skip,
          'limit': limit,
        },
      );

      final List<dynamic> data = response.data as List<dynamic>;
      final messages = data.map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();

      // Backend'dan desc tartibda keladi (yangidan eskiga)
      // Biz shunday qaytaramiz, keyin UI'da reverse qilinadi
      return messages;
    } catch (e) {
      print('Get messages for chat error: $e');
      rethrow;
    }
  }
}

