import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/services/equipment_request_service.dart';
import '../../../driver/presentation/driver_ui.dart';

/// Qidiruv va xabarnoma radiusi.
///
/// Ega uchun: shu radiusdan uzoqdagi zayavkalar kelmaydi.
/// Mijoz uchun: shu radiusdan uzoqdagi texnika ko'rsatilmaydi.
class SearchAreaPage extends StatefulWidget {
  const SearchAreaPage({super.key, required this.isOwner});

  final bool isOwner;

  @override
  State<SearchAreaPage> createState() => _SearchAreaPageState();
}

class _SearchAreaPageState extends State<SearchAreaPage> {
  static const List<int> _presets = [25, 50, 100, 150, 200, 500];

  final EquipmentRequestService _service = EquipmentRequestService();

  int _radius = 100;
  double? _lat;
  double? _lon;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isLocating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final area = await _service.getSearchArea();
      if (!mounted) return;
      setState(() {
        _radius = area.radiusKm;
        _lat = area.latitude;
        _lon = area.longitude;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('errors.something_went_wrong'.tr());
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _isLocating = true);
    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
      if (!mounted) return;
      setState(() {
        _lat = position.latitude;
        _lon = position.longitude;
        _isLocating = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLocating = false);
      _snack('errors.location_error'.tr());
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final saved = await _service.setSearchArea(
        latitude: _lat,
        longitude: _lon,
        radiusKm: _radius,
      );
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack('area.saved'.tr());
      Navigator.of(context).pop(saved);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _snack('errors.something_went_wrong'.tr());
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text(
          'area.title'.tr(),
          style: AppTypography.h2,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.isOwner
                      ? 'area.owner_hint'.tr()
                      : 'area.client_hint'.tr(),
                  style: const TextStyle(color: AppPalette.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: 16),
                _radiusCard(),
                const SizedBox(height: 16),
                _pointCard(),
                const SizedBox(height: 24),
                DPrimary(
                  'common.save'.tr(),
                  onPressed: _save,
                  busy: _isSaving,
                ),
              ],
            ),
    );
  }

  Widget _radiusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('area.title'.tr(), style: AppTypography.h3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: DChip.blueBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$_radius ${'common.km'.tr()}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.brand,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((value) {
              final selected = _radius == value;
              return ChoiceChip(
                label: Text('$value ${'common.km'.tr()}'),
                selected: selected,
                onSelected: (_) => setState(() => _radius = value),
                selectedColor: DChip.blueBg,
                labelStyle: TextStyle(
                  color: selected ? AppPalette.brand : AppPalette.textPrimary,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          Slider(
            value: _radius.toDouble().clamp(1, 1000),
            min: 1,
            max: 1000,
            divisions: 999,
            activeColor: AppPalette.brand,
            inactiveColor: AppPalette.page,
            label: '$_radius ${'common.km'.tr()}',
            onChanged: (v) => setState(() => _radius = v.round()),
          ),
        ],
      ),
    );
  }

  Widget _pointCard() {
    final hasPoint = _lat != null && _lon != null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('area.point'.tr(), style: AppTypography.h3),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                hasPoint ? Icons.place_rounded : Icons.place_outlined,
                size: 20,
                color: hasPoint ? AppPalette.brand : AppPalette.iconSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  hasPoint
                      ? '${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}'
                      : 'area.point_not_set'.tr(),
                  style: TextStyle(
                    color: hasPoint ? AppPalette.textPrimary : AppPalette.textSecondary,
                    fontSize: 14,
                    fontWeight: hasPoint ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _isLocating ? null : _useMyLocation,
            icon: _isLocating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppPalette.brand),
                  )
                : const Icon(Icons.my_location_rounded, size: 18),
            label: Text('area.use_my_location'.tr()),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppPalette.brand,
              side: const BorderSide(color: AppPalette.brand),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}
