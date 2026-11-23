import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../../core/constants/app_config.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/services/equipment_catalog.dart';
import '../../../../core/theme/app_tokens.dart';

/// Куски экранов заказа «как такси». Размеры и цвета — из макета (клиентский
/// файл, страница «01 Asosiy», компоненты Home/* и Oqim/*).

/// Сумма «1 600 000» — пробел между тысячами, как в макете.
String formatSum(num value) {
  final s = value.round().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(' ');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Иконка из assets/icons, одноцветная, цвет можно перекрасить.
class TaxiIcon extends StatelessWidget {
  const TaxiIcon(this.name, {super.key, this.size = 20, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/icons/$name.svg',
        width: size,
        height: size,
        colorFilter:
            color == null ? null : ColorFilter.mode(color!, BlendMode.srcIn),
      );
}

/// Фото техники для плиток и тарифов. Фото есть не на все типы — тогда
/// иконка типа, а не пустое место.
class EquipmentPhoto extends StatelessWidget {
  const EquipmentPhoto(
    this.type, {
    super.key,
    this.width = 70,
    this.height = 52,
    this.background = AppPalette.brandSubtle,
  });

  final String type;
  final double width;
  final double height;

  /// Цвет подложки, на которой лежит фото. Фото снято на белом, и в макете
  /// белое «растворяется» (mix-blend-multiply). Во Flutter то же даёт
  /// умножение картинки на цвет подложки: белое становится цветом фона,
  /// остальное почти не меняется.
  final Color background;

  static const _photos = {
    'excavator',
    'bulldozer',
    'truck_crane',
    'manipulator',
    'concrete_pump',
    'dump_truck',
    'aerial_platform',
  };

  Widget _local() {
    if (!EquipmentTypes.isBuiltIn(type)) {
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: SvgPicture.asset('assets/brand/more_types.svg', width: height * 0.6, height: height * 0.6),
        ),
      );
    }
    return _builtIn();
  }

  @override
  Widget build(BuildContext context) {
    // Иконка из админки (catalog.php) главнее зашитой в приложение:
    // её можно поменять без новой версии в Play Market.
    final remote = EquipmentCatalog.iconUrl(type);
    if (remote != null && remote.isNotEmpty) {
      return Image.network(
        AppConfig.mediaUrl(remote),
        width: width,
        height: height,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => _local(),
      );
    }
    return _local();
  }

  Widget _builtIn() {
    if (!_photos.contains(type)) {
      // Agar texnikaning fotosurati bo'lmasa, toza vektorli SVG ikonkasi
      // ko'rsatiladi (eskirgan va noaniq kesilgan marker o'rniga).
      return SizedBox(
        width: width,
        height: height,
        child: Center(
          child: SvgPicture.asset(
            EquipmentTypes.svgAsset(type),
            width: width * 0.85,
            height: height * 0.85,
            fit: BoxFit.contain,
          ),
        ),
      );
    }
    return Image.asset(
      'assets/equipment_photos/$type.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      color: background,
      colorBlendMode: BlendMode.multiply,
    );
  }
}

/// Нижняя панель над картой: белая, верхние углы 20, ручка 40×4,
/// Shadow/Floating.
class TaxiSheet extends StatelessWidget {
  const TaxiSheet({super.key, required this.child, this.bottomInset = 0});

  final Widget child;

  /// Системный отступ снизу (полоска жестов) — добавляется внутри панели,
  /// чтобы белое доходило до края экрана.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: AppShadows.floating,
      ),
      // SafeArea здесь НЕ нужен: панель лежит над плавающим меню, и
      // нижний отступ задаёт страница. Scaffold(extendBody) уже включает
      // высоту меню в padding.bottom, и SafeArea добавил бы её второй раз.
      child: Padding(
        padding: EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.lg + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFD3D8DF),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    );
  }
}

/// Заголовок панели — Heading/H2 20 Bold.
class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key, this.trailing});

  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Row(
          children: [
            Expanded(child: Text(text, style: AppTypography.h2)),
            if (trailing != null) trailing!,
          ],
        ),
      );
}

/// Круглая белая кнопка 40 поверх карты (Icon Button / White).
class MapIconButton extends StatelessWidget {
  const MapIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.label,
  });

  final String icon;
  final VoidCallback onTap;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: AppPalette.surface,
        shape: const CircleBorder(),
        elevation: 0,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Container(
            width: AppSpacing.iconButton,
            height: AppSpacing.iconButton,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Color(0x1F162438), offset: Offset(0, 8), blurRadius: 12),
              ],
            ),
            alignment: Alignment.center,
            child: TaxiIcon(icon, size: 20),
          ),
        ),
      ),
    );
  }
}

/// Строка адреса (Home/Manzil qatori): иконка точки, подпись 12,
/// адрес 16 Medium, стрелка.
class AddressRow extends StatelessWidget {
  const AddressRow({
    super.key,
    required this.isFrom,
    required this.label,
    required this.value,
    required this.onTap,
    this.placeholder = false,
  });

  final bool isFrom;
  final String label;
  final String value;
  final bool placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 10),
          child: Row(
            children: [
              SvgPicture.asset(
                isFrom ? 'assets/brand/point_a.svg' : 'assets/brand/point_b.svg',
                width: 24,
                height: 24,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.captionS),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMedium.copyWith(
                        height: 22 / 16,
                        color: placeholder
                            ? AppPalette.textSecondary
                            : AppPalette.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const TaxiIcon('chevron_right', size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

/// Плитка типа техники (Category Tile (rasm)): 76×88, подложка
/// bg/brand-subtle 64 высотой, фото 70×52, подпись 12.
class TypeTile extends StatelessWidget {
  const TypeTile({super.key, required this.type, required this.onTap, this.label});

  final String type;
  final String? label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label ?? EquipmentTypes.label(type),
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                height: 64,
                width: 76,
                decoration: BoxDecoration(
                  color: AppPalette.brandSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                alignment: Alignment.center,
                child: type == 'more'
                    ? SvgPicture.asset('assets/brand/more_types.svg', width: 32, height: 32)
                    : (type == 'materials'
                        ? SvgPicture.asset('assets/material_types/brick.svg', width: 38, height: 38, fit: BoxFit.contain)
                        : (type == 'freight'
                            ? SvgPicture.asset('assets/equipment_types/dump_truck.svg', width: 42, height: 42, fit: BoxFit.contain)
                            : EquipmentPhoto(type))),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label ??
                    (type == 'materials'
                        ? 'taxi.materials'.tr()
                        : (type == 'freight'
                            ? 'taxi.freight'.tr()
                            : EquipmentTypes.label(type))),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.captionS.copyWith(color: AppPalette.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Карточка тарифа (Home/Tarif kartasi (ixcham)): 134 шириной; выбранная —
/// белая с синей рамкой 2 и галочкой, остальные — серые.
class TariffCard extends StatelessWidget {
  const TariffCard({
    super.key,
    required this.type,
    required this.name,
    required this.price,
    required this.note,
    required this.selected,
    required this.onTap,
    this.fast = false,
  });

  final String type;
  final String name;
  final double price;
  final String note;
  final bool selected;
  final bool fast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '$name, ${formatSum(price)}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 134,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
          decoration: BoxDecoration(
            color: selected ? AppPalette.surface : AppPalette.page,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: selected ? AppPalette.borderFocus : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x2E306EC7),
                      offset: Offset(0, 4),
                      blurRadius: 6,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: EquipmentPhoto(
                      type,
                      width: 110,
                      height: 54,
                      background: selected ? AppPalette.surface : AppPalette.page,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            height: 18 / 13,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ),
                      if (fast) ...[
                        const SizedBox(width: 3),
                        SvgPicture.asset('assets/icons/bolt.svg', width: 14, height: 14),
                      ],
                    ],
                  ),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        formatSum(price),
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 15,
                          height: 20 / 15,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Text(
                        'common.currency'.tr(),
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 11,
                      height: 14 / 11,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ],
              ),
              if (selected)
                Positioned(
                  right: 0,
                  top: -2,
                  child: SvgPicture.asset('assets/icons/check_badge.svg', width: 20, height: 20),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Серая кнопка-опция 44 высотой: «Hozir · 4 soat», «Oddiy kovsh».
class OptionPill extends StatelessWidget {
  const OptionPill({
    super.key,
    required this.icon,
    required this.text,
    required this.onTap,
  });

  final String icon;
  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 8),
            child: Row(
              children: [
                TaxiIcon(icon, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMMedium,
                  ),
                ),
                const TaxiIcon('chevron_right', size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка способа оплаты (Home/To'lov tugmasi): 52, серая, «Naqd ⌄».
class PaymentButton extends StatelessWidget {
  const PaymentButton({super.key, required this.label, required this.onTap, required this.cash, this.card = false});

  final String label;
  final bool cash;
  final bool card;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: SizedBox(
          height: AppSpacing.buttonHeight,
          child: Padding(
            padding: const EdgeInsets.only(left: 14, right: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                cash
                    ? const TaxiIcon('cash', size: 24)
                    : card
                    ? const TaxiIcon('menu_card', size: 22)
                    : const Icon(Icons.account_balance_wallet_outlined,
                        size: 24, color: AppPalette.iconPrimary),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppPalette.textPrimary,
                  ),
                ),
                const SizedBox(width: 2),
                const TaxiIcon('chevron_down', size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Кнопка Accent L (жёлтая) — «Buyurtma berish».
class AccentButton extends StatelessWidget {
  const AccentButton({super.key, required this.label, required this.onPressed, this.loading = false});

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: enabled ? AppShadows.accent : null,
      ),
      child: SizedBox(
        height: AppSpacing.buttonHeight,
        child: ElevatedButton(
          onPressed: loading ? () {} : onPressed,
          style: ElevatedButton.styleFrom(
            foregroundColor: AppPalette.textOnAccent,
            minimumSize: const Size(0, AppSpacing.buttonHeight),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((s) {
              if (s.contains(WidgetState.disabled)) return AppPalette.disabledBg;
              if (s.contains(WidgetState.pressed)) return AppPalette.accentPressed;
              return AppPalette.accent;
            }),
            foregroundColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.disabled)
                    ? AppPalette.textDisabled
                    : AppPalette.textOnAccent),
          ),
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2, color: AppPalette.textOnAccent),
                )
              : Text(label),
        ),
      ),
    );
  }
}

/// Строка «подпись — значение» в сводке заказа (Oqim/Ma'lumot qatori).
class InfoRow extends StatelessWidget {
  const InfoRow(this.label, this.value, {super.key, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: bold ? AppTypography.h3 : AppTypography.bodyMMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Шапка экранов M1–M6: круглая кнопка «назад» (Icon Button Subtle 40)
/// и заголовок H3 17. [trailing] — справа («Hammasini o'qish», телефон).
class TaxiPageHeader extends StatelessWidget {
  const TaxiPageHeader({super.key, required this.title, this.trailing, this.leading, this.onBack});

  final String title;
  final Widget? trailing;

  /// Вместо заголовка — свой блок (чат: аватар и имя).
  final Widget? leading;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 4, AppSpacing.gutter, 4),
      child: Row(
        children: [
          TaxiRoundButton(icon: 'back', onTap: onBack ?? () => Navigator.of(context).maybePop()),
          const SizedBox(width: 12),
          Expanded(child: leading ?? Text(title, style: AppTypography.h3, overflow: TextOverflow.ellipsis)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Icon Button · Subtle/Brand, 40×40, иконка 20.
class TaxiRoundButton extends StatelessWidget {
  const TaxiRoundButton({super.key, required this.icon, this.onTap});

  final String icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppPalette.brandSubtle,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Center(
              child: TaxiIcon(icon, size: 20, color: icon == 'back' ? AppPalette.iconBrand : null),
            ),
          ),
        ),
      );
}

/// Badge из макета: высота 24, Caption/12 Semibold.
class TaxiBadge extends StatelessWidget {
  const TaxiBadge(this.label, {super.key, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  /// Цвета по этапу заказа (M1–M3).
  factory TaxiBadge.stage(String stage) {
    final label = 'taxi.stage_$stage'.tr();
    switch (stage) {
      case 'scheduled':
        return TaxiBadge(label, bg: AppPalette.accent, fg: AppPalette.textOnAccent);
      case 'working':
      case 'awaiting_confirm':
      case 'completed':
        return TaxiBadge(label, bg: AppPalette.successSubtle, fg: AppPalette.textSuccess);
      case 'cancelled':
        return TaxiBadge(label, bg: AppPalette.dangerSubtle, fg: AppPalette.textDanger);
      default:
        return TaxiBadge(label, bg: AppPalette.brandSubtle, fg: AppPalette.textBrand);
    }
  }

  @override
  // Не растягивается: плашка по размеру текста, как Badge в макете
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(AppRadius.full)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [Text(label, style: AppTypography.captionSemibold.copyWith(color: fg))],
        ),
      );
}

/// Кнопка размера S (36): «Kuzatish», «Qayta buyurtma» (Secondary) или
/// «Bekor qilish» (Ghost).
class SmallButton extends StatelessWidget {
  const SmallButton(this.label, {super.key, required this.onTap, this.ghost = false});

  final String label;
  final VoidCallback? onTap;
  final bool ghost;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 36,
        child: TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            backgroundColor: ghost ? Colors.transparent : AppPalette.brandSubtle,
            foregroundColor: AppPalette.textBrand,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            textStyle: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              height: 18 / 14,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.1,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
          ),
          child: Text(label),
        ),
      );
}

/// Подзаголовок группы: «NOYABR 2026», «BUGUN» — 12 Semibold, разрядка 0.6.
class GroupLabel extends StatelessWidget {
  const GroupLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: AppPalette.textSecondary,
        ),
      );
}

/// «12-noyabr» / «12 ноября» — дата как в макете.
String taxiDate(DateTime d, {bool withTime = false}) {
  final month = 'taxi.month_${d.month}'.tr();
  final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  final now = DateTime.now();
  final today = d.year == now.year && d.month == now.month && d.day == now.day;
  final date = today ? 'taxi.today'.tr() : 'taxi.date_fmt'.tr(args: ['${d.day}', month]);
  return withTime ? '$date, $hm' : date;
}

/// Аватар профиля: фото, а без него — инициалы на синем градиенте
/// (135°, #2A62C0 → #5B9BEA).
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({super.key, required this.size, required this.initials, this.url});

  final double size;
  final String initials;
  final String? url;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            stops: [0, .714],
            colors: [Color(0xFF2A62C0), Color(0xFF5B9BEA)],
          ),
        ),
        alignment: Alignment.center,
        child: url == null
            ? Text(
                initials,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: size * 0.365,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              )
            : Image.network(AppConfig.mediaUrl(url), width: size, height: size, fit: BoxFit.cover),
      );
}

/// Oqim/Menyu qatori: иконка в квадрате 36 (радиус 10), название 16
/// Medium, значение справа 14 и шеврон 18.
class MenuRow extends StatelessWidget {
  const MenuRow({
    super.key,
    this.icon = '',
    this.iconData,
    required this.title,
    this.value,
    this.onTap,
    this.iconBg = AppPalette.page,
    this.color = AppPalette.textPrimary,
    this.chevron = true,
  });

  final String icon;

  /// Для строк, которых нет в макете (каталог, объявления, карта), —
  /// системная иконка вместо svg.
  final IconData? iconData;
  final String title;
  final String? value;
  final VoidCallback? onTap;
  final Color iconBg;
  final Color color;
  final bool chevron;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 56,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, right: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
                  alignment: Alignment.center,
                  child: iconData != null
                      ? Icon(iconData, size: 20, color: AppPalette.iconPrimary)
                      : TaxiIcon(icon, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(color: color),
                  ),
                ),
                if (value != null) ...[
                  const SizedBox(width: 8),
                  Text(value!, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
                ],
                if (chevron) ...[
                  const SizedBox(width: 8),
                  const TaxiIcon('chevron_right', size: 18),
                ],
              ],
            ),
          ),
        ),
      );
}

/// Белая карточка-список с отступом 4 сверху и снизу.
class MenuCard extends StatelessWidget {
  const MenuCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        clipBehavior: Clip.antiAlias,
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Column(children: children),
      );
}
