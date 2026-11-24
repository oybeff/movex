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

  /// «Qurilish materiallari» включены в админке. Старый сервер поля не
  /// шлёт — считаем включёнными.
  bool get materialsEnabled => j['materials_enabled'] != false;
  Map<String, dynamic> get area => (j['service_area'] as Map?)?.cast<String, dynamic>() ?? const {};

  /// Регионы из админки (zones.php): там тоже обслуживаем, со своей ценой.
  List<List<List<double>>> get zones => [
        for (final z in (j['zones'] as List? ?? const []))
          [
            for (final p in ((z as Map)['polygon'] as List? ?? const []))
              [((p as List)[0] as num).toDouble(), (p[1] as num).toDouble()],
          ],
      ];

  bool inArea(double lat, double lon) {
    if (zones.any((z) => _inPolygon(lat, lon, z))) return true;
    final a = area;
    if (a.isEmpty) return true;
    return lat >= (a['min_lat'] as num) &&
        lat <= (a['max_lat'] as num) &&
        lon >= (a['min_lon'] as num) &&
        lon <= (a['max_lon'] as num);
  }

  /// Тот же ray casting, что на сервере (zone_service.point_in_polygon).
  static bool _inPolygon(double lat, double lon, List<List<double>> poly) {
    if (poly.length < 3) return false;
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final yi = poly[i][0], xi = poly[i][1], yj = poly[j][0], xj = poly[j][1];
      if ((yi > lat) != (yj > lat) && lon < (xj - xi) * (lat - yi) / (yj - yi) + xi) {
        inside = !inside;
      }
    }
    return inside;
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
