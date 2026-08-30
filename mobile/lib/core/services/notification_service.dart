import 'package:dio/dio.dart';

import '../models/notification_model.dart';
import '../network/dio_client.dart';

class NotificationService {
  final Dio _dio = DioClient.create();

  /// Xabarnomalar ro'yxati — faqat o'ziniki, yangisidan eskisiga.
  Future<List<NotificationModel>> getNotifications({
    bool onlyUnread = false,
    int skip = 0,
    int limit = 50,
  }) async {
    final response = await _dio.get(
      '/notifications/',
      queryParameters: {
        'only_unread': onlyUnread,
        'skip': skip,
        'limit': limit,
      },
    );

    final List<dynamic> data = response.data as List<dynamic>;
    return data
        .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Qo'ng'iroq belgisidagi raqam uchun.
  Future<int> getUnreadCount() async {
    final response = await _dio.get('/notifications/unread-count');
    return (response.data as Map<String, dynamic>)['unread'] as int? ?? 0;
  }

  Future<void> markRead(int id) async {
    await _dio.post('/notifications/$id/read');
  }

  Future<void> markAllRead() async {
    await _dio.post('/notifications/read-all');
  }

  Future<void> delete(int id) async {
    await _dio.delete('/notifications/$id');
  }

  /// Push uchun qurilma tokenini serverga berish.
  /// Firebase ulanganda chaqiriladi; hozircha server tomoni tayyor turadi.
  Future<void> registerDevice(String token, String platform) async {
    await _dio.post(
      '/notifications/devices',
      data: {'token': token, 'platform': platform},
    );
  }

  Future<void> unregisterDevice(String token) async {
    await _dio.delete('/notifications/devices', data: {'token': token});
  }
}
