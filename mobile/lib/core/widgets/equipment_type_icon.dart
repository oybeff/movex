import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/equipment_types.dart';

/// Texnika turining ikonkasi.
///
/// Odatda IKKI RANGLI chiziladi: korpus to'q, ishchi qismi (cho'mich, tig',
/// baraban) yashil — mashinalar bir-biridan aynan shu detal bilan farq
/// qiladi va ko'z avval o'shanga tushadi.
///
/// [color] berilsa — butun ikonka shu rangga bo'yaladi. Bu faqat ikkinchi
/// darajali joylar uchun: masalan kulrang matn yonidagi kichik belgi.
///
/// Turi noma'lum bo'lsa ham bo'sh joy qolmaydi — 'other' ikonkasi
/// ko'rsatiladi (qarang: [EquipmentTypes.normalize]).
class EquipmentTypeIcon extends StatelessWidget {
  const EquipmentTypeIcon(
    this.typeCode, {
    super.key,
    this.size = 24,
    this.color,
  });

  final String? typeCode;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      EquipmentTypes.svgAsset(typeCode),
      width: size,
      height: size,
      colorFilter:
          color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

/// Ikonka + tur nomi bitta qatorda. Kataloglarda va buyurtma ro'yxatlarida
/// bir xil ko'rinishi uchun alohida vidjet.
class EquipmentTypeChip extends StatelessWidget {
  const EquipmentTypeChip(
    this.typeCode, {
    super.key,
    this.iconSize = 18,
    this.textStyle,
  });

  final String? typeCode;
  final double iconSize;
  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        EquipmentTypeIcon(typeCode, size: iconSize, color: AppColors.grey),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            EquipmentTypes.label(typeCode),
            overflow: TextOverflow.ellipsis,
            style: textStyle,
          ),
        ),
      ],
    );
  }
}
