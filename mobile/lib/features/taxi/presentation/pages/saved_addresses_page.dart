import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/taxi_geo.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';
import 'address_pick_page.dart';

/// Pr4 · Saqlangan manzillar. Адрес выбирается тем же экраном, что и при
/// заказе (поиск MapKit / точка на карте), — второй копии поиска нет.
class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  final _api = ProfileApi();
  List<SavedAddress>? _items;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final a = await _api.addresses();
      if (mounted) setState(() => _items = a);
    } catch (e) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _edit([SavedAddress? a]) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _AddressSheet(initial: a, api: _api),
    );
    if (changed == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.saved_addresses'.tr()),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 24),
                      children: [
                        MenuCard(children: [
                          for (final a in items)
                            InkWell(
                              onTap: () => _edit(a),
                              child: SizedBox(
                                height: 64,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 40,
                                        height: 40,
                                        decoration: const BoxDecoration(color: AppPalette.page, shape: BoxShape.circle),
                                        alignment: Alignment.center,
                                        child: TaxiIcon(a.icon, size: 20),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              a.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: AppTypography.fontFamily,
                                                fontSize: 15,
                                                height: 20 / 15,
                                                fontWeight: FontWeight.w500,
                                                color: AppPalette.textPrimary,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              a.address,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontFamily: AppTypography.fontFamily,
                                                fontSize: 13,
                                                height: 18 / 13,
                                                color: AppPalette.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const Opacity(opacity: .6, child: TaxiIcon('edit', size: 20)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          MenuRow(
                            icon: 'plus_brand',
                            iconBg: AppPalette.brandSubtle,
                            title: 'taxi.add_address'.tr(),
                            color: AppPalette.textBrand,
                            onTap: () => _edit(),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        Text(
                          'taxi.saved_addresses_hint'.tr(),
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            height: 18 / 13,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Добавить / изменить адрес: название, тип, сам адрес.
class _AddressSheet extends StatefulWidget {
  const _AddressSheet({this.initial, required this.api});

  final SavedAddress? initial;
  final ProfileApi api;

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final _title = TextEditingController(text: widget.initial?.title ?? '');
  late String _kind = widget.initial?.kind ?? 'home';
  late TaxiPlace? _place = widget.initial == null
      ? null
      : TaxiPlace(widget.initial!.lat, widget.initial!.lon, widget.initial!.address);
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final from = _place ?? await TaxiGeo.current();
    if (!mounted) return;
    final p = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => AddressPickPage(from: from)),
    );
    if (p != null && mounted) setState(() => _place = p);
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _save() async {
    final title = _title.text.trim().isEmpty ? 'taxi.kind_$_kind'.tr() : _title.text.trim();
    final p = _place;
    if (p == null || (p.address ?? '').isEmpty) {
      _toast('taxi.address_required'.tr());
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.api.saveAddress(SavedAddress(
        id: widget.initial?.id,
        kind: _kind,
        title: title,
        address: p.address!,
        lat: p.lat,
        lon: p.lon,
      ));
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast(getErrorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await widget.api.deleteAddress(widget.initial!.id!);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _toast(getErrorMessage(e));
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(color: const Color(0xFFD3D8DF), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                widget.initial == null ? 'taxi.add_address'.tr() : 'taxi.edit_address'.tr(),
                style: AppTypography.h2,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final k in const ['home', 'work', 'site', 'other']) ...[
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _kind = k),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: k == _kind ? AppPalette.brandSubtle : AppPalette.page,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: k == _kind ? AppPalette.brand : Colors.transparent, width: 1.5),
                          ),
                          child: Text(
                            'taxi.kind_$k'.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: k == _kind ? AppPalette.textBrand : AppPalette.textPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (k != 'other') const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _title,
                maxLength: 60,
                decoration: InputDecoration(labelText: 'taxi.address_title'.tr(), counterText: ''),
              ),
              const SizedBox(height: 12),
              Material(
                color: AppPalette.page,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: _pick,
                  child: SizedBox(
                    height: 56,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const TaxiIcon('point_b', size: 20),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _place?.address ?? 'taxi.choose_address'.tr(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium.copyWith(
                                color: _place == null ? AppPalette.textSecondary : AppPalette.textPrimary,
                              ),
                            ),
                          ),
                          const TaxiIcon('chevron_right', size: 18),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _busy ? null : _save, child: Text('taxi.save'.tr())),
              if (widget.initial != null)
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: _busy ? null : _delete,
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.textDanger,
                      textStyle: AppTypography.buttonLarge,
                    ),
                    child: Text('taxi.delete_address'.tr()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
