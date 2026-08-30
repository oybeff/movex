import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/app_colors.dart';
import '../constants/equipment_types.dart';

/// Texnika turining ikonkasi.
///
/// Turi noma'lum bo'lsa ham hech qachon bo'sh joy qolmaydi — 'other'
/// ikonkasi ko'rsatiladi (qarang: [EquipmentTypes.normalize]).
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
      colorFilter: ColorFilter.mode(
        color ?? AppColors.black,
        BlendMode.srcIn,
      ),
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
