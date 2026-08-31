import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

/// Xarita — telefonda, brauzerda esa tushuntirish.
///
/// yandex_mapkit faqat Android va iOS uchun mavjud (uning pubspec'ida
/// boshqa platforma yo'q). Brauzerda YandexMap hech narsa chizmaydi:
/// ekranda bo'sh joy qoladi va konsolga "unregistered view type" tushadi.
/// Foydalanuvchi buni buzilgan ilova deb o'ylaydi.
///
/// Shuning uchun veb-versiyada xarita o'rniga nima bo'layotgani ochiq
/// yoziladi. Telefonda hech narsa o'zgarmaydi — [mapBuilder] o'z-o'zicha
/// chaqiriladi.
class MapOrPlaceholder extends StatelessWidget {
  const MapOrPlaceholder({
    super.key,
    required this.mapBuilder,
    this.hintKey,
  });

  /// Telefonda ko'rsatiladigan xarita.
  final WidgetBuilder mapBuilder;

  /// Brauzerda qo'shimcha izoh: masalan, "nuqtani telefonda tanlang".
  final String? hintKey;

  /// Brauzerdamizmi. Ekranlar shu bo'yicha o'zini moslaydi — masalan,
  /// mijozning bosh sahifasi darhol ro'yxatni ochadi.
  static bool get isWeb => kIsWeb;

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) return mapBuilder(context);

    return Container(
      color: const Color(0xFFEDF1EC),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 52, color: Colors.grey[500]),
          const SizedBox(height: 14),
          Text(
            'messages.map_web_unavailable'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            (hintKey ?? 'messages.map_web_unavailable_hint').tr(),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[700]),
          ),
        ],
      ),
    );
  }
}
