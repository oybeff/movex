import 'package:easy_localization/easy_localization.dart';

/// Qurilish materiallari ma'lumotnomasi.
///
/// Kodlar backend'dagi ro'yxat bilan BIR XIL bo'lishi shart:
/// backend/app/core/material_types.py
///
/// Texnika turlaridagi qoida bu yerda ham amal qiladi: bazada KOD
/// saqlanadi, ekranda esa nomi ko'rsatiladi. Kodni foydalanuvchiga
/// chiqarib yuborish loyihada allaqachon to'rt marta bo'lgan.
///
/// Ikonka sifatida emoji ishlatiladi — texnikadagidek svg yasash shart
/// emas: g'isht va sement uchun chizma emas, tanib olinadigan belgi
/// yetarli, va u har qanday platformada bir xil ko'rinadi.
class MaterialTypes {
  const MaterialTypes._();

  static const String fallback = 'other';

  static const List<String> codes = <String>[
    'brick',
    'gas_block',
    'cement',
    'sand',
    'gravel',
    'stone',
    'rebar',
    'concrete',
    'lumber',
    fallback,
  ];

  static const Map<String, String> _emoji = <String, String>{
    'brick': '🧱',
    'gas_block': '⬜',
    'cement': '🪣',
    'sand': '🏖',
    'gravel': '🪨',
    'stone': '🗿',
    'rebar': '🔩',
    'concrete': '🚧',
    'lumber': '🪵',
    fallback: '📦',
  };

  static String normalize(String? code) {
    if (code == null) return fallback;
    final value = code.trim().toLowerCase();
    return codes.contains(value) ? value : fallback;
  }

  static String emoji(String? code) => _emoji[normalize(code)] ?? '📦';

  /// Foydalanuvchi tilidagi nomi.
  static String label(String? code) =>
      'material_types.${normalize(code)}'.tr();

  /// O'lchov birligi nomi: piece → dona.
  static String unitLabel(String? unit) =>
      'material_units.${(unit ?? 'piece')}'.tr();
}

/// Yetkazadigan mashinalar. Sig'im SERVERDAN keladi, bu yerda faqat
/// nomi: sig'imni ikki joyda saqlash — ikki xil haqiqat degani.
class DeliveryVehicles {
  const DeliveryVehicles._();

  static String label(String? code) =>
      'delivery_vehicles.${(code ?? 'labo')}'.tr();
}
