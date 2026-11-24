import 'package:dio/dio.dart';

import '../../../core/app_flavor.dart';
import '../../../core/network/dio_client.dart';

/// Nizolar (`/disputes`) va «Yordam» chati (`/support`) — 24.11.2026.
///
/// Rasmlar `/orders/problem-photo` orqali yuklanadi (u `/static/problems/...`
/// qaytaradi, server boshqa manzildagi rasmni qabul qilmaydi).
class SupportApi {
  final Dio _dio = DioClient.create();

  /// Qaysi ilovadan yozilmoqda — admin ro'yxatida «Mijoz» / «Haydovchi».
  static String get app => AppFlavor.isDriver ? 'driver' : 'client';

  Future<String> uploadPhoto(String path, String name) async {
    final form = FormData.fromMap({'file': await MultipartFile.fromFile(path, filename: name)});
    final r = await _dio.post('/orders/problem-photo', data: form);
    return (r.data as Map<String, dynamic>)['url'] as String;
  }

  Future<String> uploadPhotoBytes(List<int> bytes, String name) async {
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(bytes, filename: name)});
    final r = await _dio.post('/orders/problem-photo', data: form);
    return (r.data as Map<String, dynamic>)['url'] as String;
  }

  // ------------------------------------------------------------ nizolar

  /// [kind]: equipment | freight | material.
  Future<Dispute> openDispute({
    required String kind,
    required int orderId,
    required String reason,
    String? comment,
    List<String> photos = const [],
  }) async {
    final r = await _dio.post('/disputes', data: {
      'kind': kind,
      'order_id': orderId,
      'reason': reason,
      if (comment != null && comment.isNotEmpty) 'comment': comment,
      'photos': photos,
    });
    return Dispute(r.data as Map<String, dynamic>);
  }

  Future<List<Dispute>> myDisputes() async {
    final r = await _dio.get('/disputes/mine');
    return (r.data as List).map((e) => Dispute(e as Map<String, dynamic>)).toList();
  }

  Future<Dispute> dispute(int id) async {
    final r = await _dio.get('/disputes/$id');
    return Dispute(r.data as Map<String, dynamic>);
  }

  Future<Dispute> sendDisputeMessage(int id, {String? text, List<String> photos = const []}) async {
    final r = await _dio.post('/disputes/$id/messages', data: {
      if (text != null && text.isNotEmpty) 'text': text,
      'photos': photos,
    });
    return Dispute(r.data as Map<String, dynamic>);
  }

  // ------------------------------------------------------------ yordam chati

  Future<SupportThread> thread() async {
    final r = await _dio.get('/support/thread', queryParameters: {'app': app});
    return SupportThread(r.data as Map<String, dynamic>);
  }

  Future<SupportThread> sendSupport({String? text, String? photo}) async {
    final r = await _dio.post('/support/messages', data: {
      'app': app,
      if (text != null && text.isNotEmpty) 'text': text,
      if (photo != null) 'photo': photo,
    });
    return SupportThread(r.data as Map<String, dynamic>);
  }

  Future<int> supportUnread() async {
    final r = await _dio.get('/support/unread', queryParameters: {'app': app});
    return ((r.data as Map<String, dynamic>)['count'] as num?)?.toInt() ?? 0;
  }
}

double _num(dynamic v) => v == null ? 0 : double.tryParse(v.toString()) ?? 0;

class ChatMessage {
  ChatMessage(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  bool get mine => j['mine'] == true;

  /// Nizoda: client | performer | admin. Yordam chatida — is_admin.
  bool get fromSupport => j['author_role'] == 'admin' || j['is_admin'] == true;
  String? get authorName => j['author_name'] as String?;
  String? get text => j['text'] as String?;
  List<String> get photos => [
        ...((j['photos'] as List?) ?? const []).map((e) => e.toString()),
        if (j['photo'] != null) j['photo'].toString(),
      ];
  DateTime get createdAt => DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now();
}

class Dispute {
  Dispute(this.j);
  final Map<String, dynamic> j;

  int get id => j['id'] as int;
  String get kind => j['kind'] as String;
  int get orderId => j['order_id'] as int;
  String get reason => j['reason'] as String;
  bool get open => j['status'] == 'open';

  /// client | performer — men bu nizoda kimman
  String? get myRole => j['my_role'] as String?;
  String? get resolution => j['resolution'] as String?;
  double get refundAmount => _num(j['refund_amount']);
  String? get comment => j['comment'] as String?;
  List<String> get photos => ((j['photos'] as List?) ?? const []).map((e) => e.toString()).toList();
  DateTime get createdAt => DateTime.tryParse('${j['created_at']}')?.toLocal() ?? DateTime.now();
  List<ChatMessage> get messages =>
      ((j['messages'] as List?) ?? const []).map((e) => ChatMessage(e as Map<String, dynamic>)).toList();
}

class SupportThread {
  SupportThread(this.j);
  final Map<String, dynamic> j;

  int? get id => j['id'] as int?;

  /// none — hali yozilmagan, open, closed
  String get status => j['status'] as String? ?? 'none';
  List<ChatMessage> get messages =>
      ((j['messages'] as List?) ?? const []).map((e) => ChatMessage(e as Map<String, dynamic>)).toList();
}
