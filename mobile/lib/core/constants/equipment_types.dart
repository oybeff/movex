import 'package:easy_localization/easy_localization.dart';

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
/// qo'shing, `tool/generate_equipment_icons.py` ga chizmasini yozib ikonkalarni
/// qayta yasang va ikkala tarjima fayliga nom qo'shing.
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
    return codes.contains(value) ? value : fallback;
  }

  /// Interfeys uchun ikonka — rangi bilan bo'yaladi.
  static String svgAsset(String? code) =>
      'assets/equipment_types/${normalize(code)}.svg';

  /// Yandex xarita markeri uchun rasm — yashil doira ichida oq belgi.
  static String markerAsset(String? code) =>
      'assets/equipment_types/${normalize(code)}.png';

  /// Foydalanuvchi tilidagi nomi.
  static String label(String? code) =>
      'equipment_types.${normalize(code)}'.tr();
}
