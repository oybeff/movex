import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/equipment_types.dart';
import '../../../core/theme/app_tokens.dart';
import '../../taxi/presentation/widgets/taxi_ui.dart' show formatSum;

/// Общие кирпичи экранов MoveX GO Driver — по Figma «Texnika egasi ilovasi
/// (Owner)»: белые карточки r16 на сером фоне, синяя кнопка 52, плашки-чипы.

String money(num v) => "${formatSum(v)} ${'common.currency'.tr()}";

String tariffName(String? t) => t == null ? '' : 'driver.tariff_$t'.tr();

/// «Ekskavator · Ekonom».
String orderTitle(String? type, String? tariff) {
  final name = EquipmentTypes.label(type);
  return tariff == null ? name : '$name · ${tariffName(tariff)}';
}

class DCard extends StatelessWidget {
  const DCard({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.color});

  final Widget child;
  final EdgeInsets padding;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color ?? AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: child,
      );
}

/// Плашка-статус: «Yangi buyurtma», «Naqd», «Yakunlandi».
class DChip extends StatelessWidget {
  const DChip(this.text, {super.key, this.bg = AppPalette.successSubtle, this.fg = AppPalette.textSuccess});

  final String text;
  final Color bg;
  final Color fg;

  static const warn = Color(0xFFF6C849);
  static const blueBg = Color(0xFFEAF2FB);
  static const redBg = Color(0xFFFDECEC);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
        child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg, height: 1.3)),
      );
}

/// Плитка «0 so'm / Bugun» из H1/H2.
class DStat extends StatelessWidget {
  const DStat(this.value, this.label, {super.key});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Сумма «1 275 000 so'm» не должна обрезаться — уменьшается
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppPalette.textPrimary)),
              ),
              const SizedBox(height: 2),
              Text(label, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
            ],
          ),
        ),
      );
}

/// Строка «Qachon ........ Hozir · 4 soat».
class DRow extends StatelessWidget {
  const DRow(this.label, this.value, {super.key, this.bold = false, this.valueColor});

  final String label;
  final String value;
  final bool bold;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(fontSize: bold ? 16 : 14, fontWeight: bold ? FontWeight.w700 : null,
                color: bold ? AppPalette.textPrimary : AppPalette.textSecondary)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: bold ? 18 : 14,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                    color: valueColor ?? AppPalette.textPrimary,
                  )),
            ),
          ],
        ),
      );
}

/// Адрес клиента с точкой — единственная точка заказа (как у клиента).
class DAddress extends StatelessWidget {
  const DAddress(this.address, {super.key});

  final String? address;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: AppPalette.brand, width: 4),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('driver.client_address'.tr(),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                  Text(address ?? '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Квадратная кнопка-действие: «Qo'ng'iroq», «Xabar», «Navigator».
class DAction extends StatelessWidget {
  const DAction({super.key, required this.icon, required this.label, required this.onTap, this.accent = false});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final fg = accent ? AppPalette.brand : AppPalette.textPrimary;
    return Expanded(
      child: Material(
        color: accent ? DChip.blueBg : AppPalette.page,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Column(
              children: [
                Icon(icon, size: 20, color: fg),
                const SizedBox(height: 4),
                Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Синяя кнопка 52 на всю ширину.
class DPrimary extends StatelessWidget {
  const DPrimary(this.text, {super.key, required this.onPressed, this.busy = false});

  final String text;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppPalette.brand,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          onPressed: busy ? null : onPressed,
          child: busy
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(text),
        ),
      );
}

/// Белая/голубая кнопка 52: «Ishni to'xtatish», «Rad etish».
class DSecondary extends StatelessWidget {
  const DSecondary(this.text, {super.key, required this.onPressed, this.tinted = false});

  final String text;
  final VoidCallback? onPressed;
  final bool tinted;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 52,
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            backgroundColor: tinted ? DChip.blueBg : AppPalette.surface,
            foregroundColor: tinted ? AppPalette.brand : AppPalette.textPrimary,
            side: tinted ? BorderSide.none : const BorderSide(color: AppPalette.borderDefault),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          onPressed: onPressed,
          child: Text(text),
        ),
      );
}

/// Белая шторка снизу с «ручкой», как во всех экранах макета.
class DSheet extends StatelessWidget {
  const DSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + MediaQuery.of(context).padding.bottom * 0),
        decoration: const BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [BoxShadow(color: Color(0x1A000000), blurRadius: 16, offset: Offset(0, -2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppPalette.borderDefault, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            child,
          ],
        ),
      );
}

/// «2 soat 15 daq» из длительности.
String durationText(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return 'driver.min_n'.tr(args: ['$m']);
  if (m == 0) return 'driver.hours_n'.tr(args: ['$h']);
  return 'driver.h_min'.tr(args: ['$h', '$m']);
}
