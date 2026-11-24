import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/map_or_placeholder.dart';
import '../../data/taxi_geo.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';
import '../../../../core/widgets/h_icon.dart';

/// «2 · Qayerga — manzilni qidirish». Возвращает выбранную точку
/// ([TaxiPlace]) через Navigator.pop.
class AddressPickPage extends StatefulWidget {
  const AddressPickPage({super.key, required this.from, this.recent = const [], this.forSaving = false});

  /// Pr4 «Manzil qo'shish»: выбирается один адрес, не маршрут — без строки
  /// «Qayerdan», заголовок и подпись поля свои.
  final bool forSaving;

  final TaxiPlace from;

  /// Последние адреса клиента (из его прошлых заказов).
  final List<TaxiPlace> recent;

  @override
  State<AddressPickPage> createState() => _AddressPickPageState();
}

class _AddressPickPageState extends State<AddressPickPage> {
  final _text = TextEditingController();
  Timer? _debounce;
  List<TaxiPlace> _results = const [];
  bool _searching = false;
  bool _searchFailed = false; // E2: поиск не ответил
  // Pr4: «Saqlangan manzillar buyurtma berishda birinchi bo'lib taklif qilinadi»
  List<SavedAddress> _saved = const [];

  @override
  void initState() {
    super.initState();
    ProfileApi().addresses().then((a) {
      if (mounted) setState(() => _saved = a);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!TaxiGeo.canSearch) {
        setState(() {});
        return;
      }
      setState(() => _searching = true);
      final found = await TaxiGeo.search(value, widget.from);
      if (!mounted) return;
      setState(() {
        _results = found ?? const [];
        _searchFailed = found == null && value.trim().length >= 3;
        _searching = false;
      });
    });
  }

  Future<void> _pickOnMap() async {
    final place = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => _MapPickPage(start: widget.from)),
    );
    if (place != null && mounted) Navigator.of(context).pop(place);
  }

  static double _km(TaxiPlace a, TaxiPlace b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lon - a.lon) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  @override
  Widget build(BuildContext context) {
    final typed = _text.text.trim();
    final list = typed.isEmpty ? widget.recent : _results;
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
              child: Row(
                children: [
                  Material(
                    color: AppPalette.brandSubtle,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(context).pop(),
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Center(child: TaxiIcon('back', size: 20, color: AppPalette.iconBrand)),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      widget.forSaving ? 'taxi.choose_address'.tr() : 'taxi.where_to_title'.tr(),
                      style: AppTypography.h2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Column(
                children: [
                  if (!widget.forSaving) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: AppPalette.page,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: AddressRow(
                        isFrom: true,
                        label: 'taxi.from'.tr(),
                        value: widget.from.address ?? 'taxi.my_location'.tr(),
                        onTap: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  Container(
                    height: 52,
                    padding: const EdgeInsets.only(left: 14, right: 10),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(color: AppPalette.borderFocus, width: 1.5),
                    ),
                    child: Row(
                      children: [
                        SvgPicture.asset('assets/brand/point_b.svg', width: 24, height: 24),
                        const SizedBox(width: AppSpacing.md),
                        // Подпись «Qayerga» над строкой ввода — как у поля
                        // «Qayerdan» и как в макете (кадр 2): без неё поле
                        // с набранным адресом теряло, что это именно «куда».
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(widget.forSaving ? 'taxi.address'.tr() : 'taxi.to'.tr(),
                                  style: AppTypography.captionS),
                              TextField(
                                controller: _text,
                                autofocus: true,
                                onChanged: _onChanged,
                                style: AppTypography.bodyMedium.copyWith(height: 22 / 16),
                                cursorColor: AppPalette.brand,
                                decoration: InputDecoration(
                                  hintText: 'taxi.enter_address'.tr(),
                                  hintStyle: AppTypography.bodyMedium.copyWith(
                                    height: 22 / 16,
                                    color: AppPalette.textSecondary,
                                  ),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isCollapsed: true,
                                  contentPadding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (_searching)
                          const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.brand),
                          )
                        else
                          const TaxiIcon('chevron_right', size: 20),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (!MapOrPlaceholder.isWeb)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.md, AppSpacing.gutter, 0),
                child: InkWell(
                  onTap: _pickOnMap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Row(
                      children: [
                        const HIcon(Icons.location_on_outlined, color: AppPalette.iconBrand, size: 20),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          'taxi.pick_on_map'.tr(),
                          style: AppTypography.bodyMMedium.copyWith(
                            color: AppPalette.textBrand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.sm),
              child: Divider(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                children: [
                  // В браузере поиска MapKit нет: введённый текст берётся как
                  // адрес, а точкой — место, откуда ехать.
                  if (!TaxiGeo.canSearch && typed.isNotEmpty)
                    _PlaceTile(
                      icon: Icons.edit_location_alt_outlined,
                      title: typed,
                      subtitle: 'taxi.use_typed_address'.tr(),
                      onTap: () => Navigator.of(context).pop(
                        TaxiPlace(widget.from.lat, widget.from.lon, typed),
                      ),
                    ),
                  if (_searchFailed && typed.isNotEmpty)
                    _PlaceTile(
                      icon: Icons.wifi_off_rounded,
                      title: 'taxi.offline_title'.tr(),
                      subtitle: 'taxi.search_offline_body'.tr(),
                      onTap: () => _onChanged(_text.text),
                    ),
                  if (typed.isEmpty)
                    for (final a in _saved)
                      _PlaceTile(
                        svg: a.icon,
                        title: a.title,
                        subtitle: a.address,
                        trailing: '${_km(widget.from, TaxiPlace(a.lat, a.lon)).toStringAsFixed(1)} km',
                        onTap: () => Navigator.of(context).pop(TaxiPlace(a.lat, a.lon, a.address)),
                      ),
                  for (final p in list)
                    _PlaceTile(
                      icon: Icons.location_on_outlined,
                      title: p.label,
                      subtitle: p.address ?? '',
                      trailing: '${_km(widget.from, p).toStringAsFixed(1)} km',
                      onTap: () => Navigator.of(context).pop(p),
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

/// Oqim/Manzil taklifi: круг 40 с иконкой, название 16, адрес 13, км.
class _PlaceTile extends StatelessWidget {
  const _PlaceTile({
    this.icon,
    this.svg,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData? icon;
  final String? svg;
  final String title;
  final String subtitle;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 64,
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: AppPalette.page, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: svg != null ? TaxiIcon(svg!, size: 20) : HIcon(icon, size: 20, color: AppPalette.iconBrand),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyMedium),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null)
              Text(
                trailing!,
                style: const TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppPalette.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Выбор точки на карте: булавка в центре, «Tayyor» определяет адрес.
class _MapPickPage extends StatefulWidget {
  const _MapPickPage({required this.start});

  final TaxiPlace start;

  @override
  State<_MapPickPage> createState() => _MapPickPageState();
}

class _MapPickPageState extends State<_MapPickPage> {
  late Point _center = widget.start.point;
  bool _busy = false;

  Future<void> _done() async {
    setState(() => _busy = true);
    final place = TaxiPlace(_center.latitude, _center.longitude);
    final address = await TaxiGeo.addressAt(place);
    if (!mounted) return;
    Navigator.of(context).pop(place.withAddress(address));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: YandexMap(
              onMapCreated: (c) => c.moveCamera(
                CameraUpdate.newCameraPosition(CameraPosition(target: widget.start.point, zoom: 15)),
              ),
              onCameraPositionChanged: (pos, reason, finished) => _center = pos.target,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 62),
              child: SvgPicture.asset('assets/icons/map_pin_a.svg', width: 44, height: 62),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.sm,
            left: AppSpacing.gutter,
            child: MapIconButton(
              icon: 'back',
              label: 'auth.back'.tr(),
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
          Positioned(
            left: AppSpacing.gutter,
            right: AppSpacing.gutter,
            bottom: MediaQuery.of(context).padding.bottom + AppSpacing.lg,
            child: SizedBox(
              height: AppSpacing.buttonHeight,
              child: ElevatedButton(
                onPressed: _busy ? null : _done,
                child: Text('taxi.done'.tr()),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
