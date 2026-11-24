import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/material_types.dart';
import '../../../../core/models/material_model.dart';
import '../../../../core/services/equipment_catalog.dart';
import '../../../../core/services/material_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../widgets/taxi_ui.dart';
import '../../../../core/widgets/h_icon.dart';

/// K2 · «Barcha kategoriyalar» — открывается с плитки «Boshqalar».
///
/// Список ведёт админка (catalog.php): название, группа, подпись, иконка,
/// вкл/выкл. Возвращает код выбранного типа — дальше обычный заказ «как
/// такси» с тарифами. Тип без тарифа показан серым: заказать его нельзя,
/// пока админ не поставит цену.
class CatalogAllPage extends StatefulWidget {
  const CatalogAllPage({super.key});

  @override
  State<CatalogAllPage> createState() => _CatalogAllPageState();
}

class _CatalogAllPageState extends State<CatalogAllPage> {
  final _search = TextEditingController();
  String _group = 'all';
  bool _loading = true;
  bool _failed = false;

  /// Грузовики «Yuk tashish» (Labo, Porter, Gazel, Isuzu…) — сверху группы
  /// transport. Выбор возвращает `truck:<код>`, главная открывает перевозку.
  List<DeliveryVehicleModel> _trucks = const [];

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final hadData = EquipmentCatalog.types.isNotEmpty;
    setState(() {
      _loading = !hadData;
      _failed = false;
    });
    final lang = context.locale.languageCode;
    MaterialService().getVehicles().then((v) {
      if (mounted) setState(() => _trucks = v);
    }).catchError((_) {});
    final ok = await EquipmentCatalog.load(lang);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = !ok && EquipmentCatalog.types.isEmpty;
    });
  }

  List<CatalogType> get _visible {
    final q = _search.text.trim().toLowerCase();
    return EquipmentCatalog.types.where((t) {
      if (_group != 'all' && t.group != _group) return false;
      if (q.isEmpty) return true;
      return t.nameUz.toLowerCase().contains(q) ||
          t.nameRu.toLowerCase().contains(q) ||
          (t.subtitle ?? '').toLowerCase().contains(q);
    }).toList();
  }

  void _pick(CatalogType t) {
    if (!t.hasTariff) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('catalog.no_price'.tr(args: [t.name]))));
      return;
    }
    Navigator.of(context).pop(t.code);
  }

  @override
  Widget build(BuildContext context) {
    final groups = EquipmentCatalog.groups;
    final usedGroups = EquipmentCatalog.types.map((t) => t.group).toSet()
      ..addAll(_trucks.isEmpty ? const <String>[] : const ['transport']);
    final items = _visible;

    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
              child: Row(
                children: [
                  _RoundIconButton(
                    icon: Icons.chevron_left,
                    tooltip: 'common.back'.tr(),
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('catalog.all_title'.tr(), style: AppTypography.h3),
                        if (EquipmentCatalog.types.isNotEmpty)
                          Text(
                            'catalog.count'.tr(args: [EquipmentCatalog.types.length.toString()]),
                            style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.gutter, 0),
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'catalog.search_hint'.tr(),
                  prefixIcon: const HIcon(Icons.search, color: AppPalette.iconSecondary),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'common.clear'.tr(),
                          icon: const HIcon(Icons.close, color: AppPalette.iconSecondary),
                          onPressed: _search.clear,
                        ),
                  filled: true,
                  fillColor: AppPalette.page,
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                children: [
                  _chip('all', 'catalog.all'.tr()),
                  for (final g in groups)
                    if (usedGroups.contains(g.code)) _chip(g.code, g.name),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(child: _body(items, groups)),
          ],
        ),
      ),
    );
  }

  Widget _chip(String code, String label) {
    final selected = _group == code;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => setState(() => _group = code),
        labelStyle: AppTypography.bodyMMedium.copyWith(
          color: selected ? AppPalette.textOnBrand : AppPalette.textPrimary,
        ),
        selectedColor: AppPalette.brand,
        backgroundColor: AppPalette.surface,
        side: BorderSide(color: selected ? AppPalette.brand : AppPalette.borderDefault),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );
  }

  Widget _body(List<CatalogType> items, List<CatalogGroup> groups) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppPalette.brand));
    }
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('catalog.load_failed'.tr(), textAlign: TextAlign.center, style: AppTypography.body),
              const SizedBox(height: AppSpacing.md),
              FilledButton(onPressed: _load, child: Text('common.retry'.tr())),
            ],
          ),
        ),
      );
    }
    if (items.isEmpty && _trucks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Text('catalog.nothing_found'.tr(), textAlign: TextAlign.center, style: AppTypography.body),
        ),
      );
    }

    final children = <Widget>[];
    final q = _search.text.trim().toLowerCase();
    final trucks = _trucks.where((t) => q.isEmpty || (t.name ?? t.code).toLowerCase().contains(q)).toList();
    for (final g in groups) {
      final inGroup = items.where((t) => t.group == g.code).toList();
      final withTrucks = g.code == 'transport' && (_group == 'all' || _group == 'transport') && trucks.isNotEmpty;
      if (inGroup.isEmpty && !withTrucks) continue;
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, AppSpacing.xs),
        child: Text(
          g.name.toUpperCase(),
          style: AppTypography.captionSemibold.copyWith(color: AppPalette.textSecondary, letterSpacing: 0.4),
        ),
      ));
      if (withTrucks) {
        for (final t in trucks) {
          children.add(_truckRow(t));
        }
      }
      for (final t in inGroup) {
        children.add(_row(t));
      }
    }
    // Тип с группой, которой нет в списке групп (не должно быть, но не терять).
    final known = groups.map((g) => g.code).toSet();
    for (final t in items.where((t) => !known.contains(t.group))) {
      children.add(_row(t));
    }
    return RefreshIndicator(
      color: AppPalette.brand,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: children,
      ),
    );
  }

  Widget _truckRow(DeliveryVehicleModel t) {
    return InkWell(
      onTap: () => Navigator.of(context).pop('truck:${t.code}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppPalette.brandSubtle,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: const HIcon(Icons.local_shipping_outlined, color: AppPalette.iconBrand),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.name ?? DeliveryVehicles.label(t.code),
                      style: AppTypography.bodyMedium.copyWith(color: AppPalette.textPrimary)),
                  Text('catalog.truck_up_to'.tr(args: [_tonnes(t.capacityKg)]),
                      style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                ],
              ),
            ),
            const HIcon(Icons.chevron_right, color: AppPalette.iconPrimary),
          ],
        ),
      ),
    );
  }

  static String _tonnes(int kg) {
    final t = kg / 1000;
    return t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toString().replaceAll('.', ',');
  }

  Widget _row(CatalogType t) {
    final subtitle = t.hasTariff ? t.subtitle : 'catalog.soon'.tr();
    return Opacity(
      opacity: t.hasTariff ? 1 : 0.5,
      child: InkWell(
        onTap: () => _pick(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 6),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppPalette.brandSubtle,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                alignment: Alignment.center,
                child: EquipmentPhoto(t.code, width: 44, height: 36),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.name, style: AppTypography.bodyMedium.copyWith(color: AppPalette.textPrimary)),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(subtitle, style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                  ],
                ),
              ),
              const HIcon(Icons.chevron_right, color: AppPalette.iconPrimary),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({required this.icon, required this.onTap, required this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: AppPalette.page,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: AppSpacing.iconButton,
            height: AppSpacing.iconButton,
            child: HIcon(icon, color: AppPalette.iconPrimary),
          ),
        ),
      ),
    );
  }
}
