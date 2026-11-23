import 'package:easy_localization/easy_localization.dart';

import '../services/equipment_catalog.dart';

/// Texnika turlari ma'lumotnomasi.
///
/// Kodlar backend'dagi ro'yxat bilan BIR XIL bo'lishi shart:
/// backend/app/core/equipment_types.py
///
/// Ilgari tur erkin matn edi va egasi xohlagan narsani yozardi, shuning uchun
/// turga ikonka biriktirib bo'lmasdi. Endi bazada kod saqlanadi, nomi esa
/// tarjimalardan olinadi (assets/translations/*.json, `equipment_types` bo'limi).
///
/// Yangi tur qo'shish: shu ro'yxatga kod qo'shing, backend ro'yxatiga ham
/// qo'shing, `assets/equipment_types/<kod>_uz.png` va `<kod>_ru.png`
/// ikonkalarini qo'ying va ikkala tarjima fayliga nom qo'shing.
class EquipmentTypes {
  const EquipmentTypes._();

  static const String fallback = 'other';

  static const List<String> codes = <String>[
    'excavator',
    'backhoe_loader',
    'mini_excavator',
    'bulldozer',
    'front_loader',
    'truck_crane',
    'manipulator',
    'aerial_platform',
    'dump_truck',
    'concrete_mixer',
    'concrete_pump',
    'grader',
    'roller',
    'auger_drill',
    'tow_truck',
    'compressor',
    fallback,
  ];

  /// Noma'lum yoki bo'sh qiymatni 'other' ga aylantiradi.
  /// Eski yozuvlar (erkin matn) ham shu yerdan o'tadi.
  static String normalize(String? code) {
    if (code == null) return fallback;
    final value = code.trim().toLowerCase();
    if (codes.contains(value)) return value;
    // Тип, заведённый в админке (catalog.php) после выхода этой версии.
    return EquipmentCatalog.byCode(value) != null ? value : fallback;
  }

  /// Vektorli toza SVG ikonkasi (interfeys, chiplar, kartochkalar uchun).
  static String svgAsset(String? code) =>
      'assets/equipment_types/${normalize(code)}.svg';

  /// Ikonka: qora ramkali belgi, ostida tur nomi. Ham ro'yxatlarda, ham
  /// Yandex xarita markeri sifatida ishlatiladi.
  ///
  /// Nom rasmning ICHIDA yozilgan, shuning uchun har til uchun alohida
  /// fayl: `<kod>_uz.png`, `<kod>_ru.png`. Til berilmasa yoki noma'lum
  /// bo'lsa — o'zbekcha (ilovaning asosiy tili).
  static String markerAsset(String? code, [String? languageCode]) {
    final lang = languageCode == 'ru' ? 'ru' : 'uz';
    return 'assets/equipment_types/${normalize(code)}_$lang.png';
  }

  /// Foydalanuvchi tilidagi nomi.
  static String label(String? code) {
    final c = normalize(code);
    if (codes.contains(c)) return 'equipment_types.$c'.tr();
    return EquipmentCatalog.name(c, EquipmentCatalog.lang) ?? 'equipment_types.$fallback'.tr();
  }

  /// Тип есть в самом приложении (переводы, svg). Новые типы из админки —
  /// нет: у них только название и иконка с сервера.
  static bool isBuiltIn(String? code) => codes.contains(code);
}
