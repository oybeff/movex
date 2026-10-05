import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/equipment_types.dart';

/// Texnika turining ikonkasi.
///
/// Ikonka RANGLI: sariq korpus, po'lat ishchi qismi, qora gusenitsa.
/// Mashinalar bir-biridan aynan ishchi qismi bilan farq qiladi.
///
/// [color] berilsa — butun ikonka bitta rangga bo'yaladi va detallar
/// yo'qoladi. Buni faqat zarur bo'lganda ishlating: 18-20 px da bo'yalgan
/// ikonka tanib bo'lmaydigan dog'ga aylanadi, shuning uchun ro'yxatlardagi
/// chip ham endi uni bo'yamaydi.
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
        EquipmentTypeIcon(typeCode, size: iconSize),
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

/// Rasmi yo'q texnika uchun o'rin — yumshoq fon va KATTA ikonka.
///
/// Ilgari bu yerda kulrang (grey[200]) to'rtburchak va o'rtasida kichkina
/// belgi turardi: katta bo'sh maydon ichida 48 px ikonka "unutilgan"
/// ko'rinardi. Endi fon mashinaning rangiga ohangdosh va ikonka maydonning
/// qariyb yarmini egallaydi — kartochka to'la ko'rinadi.
class EquipmentPhotoPlaceholder extends StatelessWidget {
  const EquipmentPhotoPlaceholder(
    this.typeCode, {
    super.key,
    this.borderRadius,
  });

  final String? typeCode;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ikonka maydonning kichik tomoniga qarab o'lchanadi: kartochka
        // ham, ro'yxatdagi kichik katak ham bir xil to'la ko'rinsin.
        final side = constraints.biggest.shortestSide;
        final iconSize = side.isFinite ? side * 0.72 : 64.0;
        return Container(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFFF6E0), Color(0xFFF1F3F5)],
            ),
          ),
          alignment: Alignment.center,
          child: EquipmentTypeIcon(typeCode, size: iconSize),
        );
      },
    );
  }
}
