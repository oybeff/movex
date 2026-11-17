import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/network/dio_client.dart';

/// GET /settings/app-status: обязательное обновление (U2), техработы (U3)
/// и зона обслуживания (E3). Всё задаёт админка, в приложении не хранится.
class AppStatus {
  AppStatus(this.j);

  final Map<String, dynamic> j;

  String get minVersion => (j['min_version'] ?? '0.0.0') as String;
  bool get maintenance => j['maintenance'] == true;
  String? get maintenanceUntil => j['maintenance_until'] as String?;
  String? get storeAndroid => j['store_android'] as String?;
  String? get storeIos => j['store_ios'] as String?;
  Map<String, dynamic> get area => (j['service_area'] as Map?)?.cast<String, dynamic>() ?? const {};

  bool inArea(double lat, double lon) {
    final a = area;
    if (a.isEmpty) return true;
    return lat >= (a['min_lat'] as num) &&
        lat <= (a['max_lat'] as num) &&
        lon >= (a['min_lon'] as num) &&
        lon <= (a['max_lon'] as num);
  }

  String areaName(String lang) => (lang == 'ru' ? area['name_ru'] : area['name_uz']) as String? ?? '';

  static AppStatus? last;

  /// null — сервер не ответил: тогда приложение просто работает дальше.
  static Future<AppStatus?> fetch() async {
    try {
      final r = await DioClient.create()
          .get('/settings/app-status', options: Options(receiveTimeout: const Duration(seconds: 5)));
      return last = AppStatus(r.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<String> currentVersion() async {
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return '0.0.0';
    }
  }

  /// «1.0.0» < «1.2.0»: сравнение по числам, не по строкам.
  static bool older(String a, String b) {
    List<int> p(String s) => s.split('.').map((x) => int.tryParse(x.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
    final x = p(a), y = p(b);
    for (var i = 0; i < 3; i++) {
      final u = i < x.length ? x[i] : 0, v = i < y.length ? y[i] : 0;
      if (u != v) return u < v;
    }
    return false;
  }
}
