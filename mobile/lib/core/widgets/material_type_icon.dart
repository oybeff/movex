import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../constants/material_types.dart';

/// Qurilish materiali ikonkasi.
///
/// Texnikadagi [EquipmentTypeIcon] bilan bir xil uslubda: rangli SVG,
/// assets/material_types/ dan. Ilgari bu yerda emoji ko'rsatilardi va
/// har bir telefonda boshqacha chizilardi.
///
/// Turi noma'lum bo'lsa 'other' ikonkasi chiqadi — bo'sh joy qolmaydi.
class MaterialTypeIcon extends StatelessWidget {
  const MaterialTypeIcon(this.code, {super.key, this.size = 28});

  final String? code;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      MaterialTypes.svgAsset(code),
      width: size,
      height: size,
    );
  }
}
