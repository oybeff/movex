import 'package:dio/dio.dart';

import '../network/dio_client.dart';

/// Тип техники из админки (GET /equipment/catalog).
class CatalogType {
  CatalogType(this.j);
  final Map<String, dynamic> j;

  String get code => j['code'] as String;
  String get name => (j['name'] ?? code) as String;
  String get nameUz => (j['name_uz'] ?? name) as String;
  String get nameRu => (j['name_ru'] ?? name) as String;
  String get group => (j['group'] ?? 'other') as String;
  String? get subtitle => j['subtitle'] as String?;
  String? get iconUrl => j['icon_url'] as String?;
  bool get hasTariff => j['has_tariff'] == true;
}

class CatalogGroup {
  CatalogGroup(this.code, this.name);
  final String code;
  final String name;
}

/// Справочник типов техники, который ведёт админка (catalog.php).
///
/// Загружается один раз при запуске (и при открытии «Barcha
/// kategoriyalar»). Новый тип или иконка из админки появляются в
/// приложении без новой версии в Play Market. Не загрузился — всё
/// работает по списку и иконкам, зашитым в приложение.
class EquipmentCatalog {
  EquipmentCatalog._();

  static List<CatalogGroup> groups = const [];
  static String lang = 'uz';
  static List<CatalogType> types = const [];
  static final Map<String, CatalogType> _byCode = {};

  static CatalogType? byCode(String? code) => code == null ? null : _byCode[code];

  /// Название типа из админки на языке [lang]; null — в админке его нет.
  static String? name(String? code, String lang) {
    final t = byCode(code);
    if (t == null) return null;
    return lang == 'ru' ? t.nameRu : t.nameUz;
  }

  static String? iconUrl(String? code) => byCode(code)?.iconUrl;

  static Future<bool> load(String lang) async {
    try {
      final r = await DioClient.create().get(
        '/equipment/catalog',
        queryParameters: {'lang': lang},
        options: Options(receiveTimeout: const Duration(seconds: 8)),
      );
      final data = r.data as Map<String, dynamic>;
      EquipmentCatalog.lang = lang;
      groups = [
        for (final g in (data['groups'] as List? ?? const []))
          CatalogGroup(g['code'] as String, g['name'] as String),
      ];
      types = [
        for (final t in (data['types'] as List? ?? const []))
          CatalogType((t as Map).cast<String, dynamic>()),
      ];
      _byCode
        ..clear()
        ..addEntries(types.map((t) => MapEntry(t.code, t)));
      return true;
    } catch (_) {
      return false;
    }
  }
}
