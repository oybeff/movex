import 'package:dio/dio.dart';
import '../network/dio_client.dart';
import '../models/message_model.dart';

class MessageService {
  final Dio _dio = DioClient.create();

  /// Chat xabarlarini olish.
  ///
  /// chatId MAJBURIY. Ilgari bu metod butun tizimdagi 1000 ta xabarni
  /// yuklab, keraklisini telefonda ajratib olardi — ya'ni begona
  /// yozishmalar ham qurilmaga tushardi. Endi server faqat shu chatning
  /// xabarlarini beradi va faqat ishtirokchiga.
  Future<List<MessageModel>> getChatMessages(
    int chatId, {
    int skip = 0,
    int limit = 100,
  }) async {
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
      return data.map((e) => MessageModel.fromJson(e as Map<String, dynamic>)).toList();
    } catch (e) {
      print('Get chat messages error: $e');
      rethrow;
    }
  }

  /// Bitta xabarni olish
  Future<MessageModel> getMessage(int messageId) async {
    try {
      final response = await _dio.get('/messages/$messageId');
      return MessageModel.fromJson(response.data);
    } catch (e) {
      print('Get message error: $e');
      rethrow;
    }
  }

  /// Yangi xabar yuborish
  Future<MessageModel> createMessage(MessageCreateModel message) async {
    try {
      final response = await _dio.post(
        '/messages/',
        data: message.toJson(),
      );
      return MessageModel.fromJson(response.data);
    } catch (e) {
      print('Create message error: $e');
      rethrow;
    }
  }

  /// Xabarni o'chirish
  Future<void> deleteMessage(int messageId) async {
    try {
      await _dio.delete('/messages/$messageId');
    } catch (e) {
      print('Delete message error: $e');
      rethrow;
    }
  }
}

