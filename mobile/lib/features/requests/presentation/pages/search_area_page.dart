import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/equipment_request_model.dart';
import '../../../../core/services/equipment_request_service.dart';

/// Qidiruv va xabarnoma radiusi.
///
/// Ega uchun: shu radiusdan uzoqdagi zayavkalar kelmaydi.
/// Mijoz uchun: shu radiusdan uzoqdagi texnika ko'rsatilmaydi.
///
/// Nuqta belgilanmagan bo'lsa radius ISHLAMAYDI va hech narsa filtrlanmaydi —
/// sozlamagan foydalanuvchi bo'sh ro'yxat ko'rmasligi kerak. Ekranda buni
/// ochiq yozib qo'yamiz, aks holda "nega hech narsa yo'q" degan savol
/// tug'iladi.
class SearchAreaPage extends StatefulWidget {
  const SearchAreaPage({super.key, required this.isOwner});

  final bool isOwner;

  @override
  State<SearchAreaPage> createState() => _SearchAreaPageState();
}

class _SearchAreaPageState extends State<SearchAreaPage> {
  static const List<int> _presets = [25, 50, 100, 150, 200, 500];

  final EquipmentRequestService _service = EquipmentRequestService();

  SearchAreaModel? _area;
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
        _area = area;
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
      setState(() {
        _area = saved;
        _isSaving = false;
      });
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
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'area.title'.tr(),
          style: const TextStyle(
              color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  widget.isOwner
                      ? 'area.owner_hint'.tr()
                      : 'area.client_hint'.tr(),
                  style: TextStyle(color: Colors.grey[700], fontSize: 14),
                ),
                const SizedBox(height: 20),
                _radiusCard(),
                const SizedBox(height: 16),
                _pointCard(),
                const SizedBox(height: 28),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryGreen,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('common.save'.tr(),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _radiusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('area.title'.tr(),
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              Text(
                '$_radius ${'common.km'.tr()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryGreen,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((value) {
              final selected = _radius == value;
              return ChoiceChip(
                label: Text('$value ${'common.km'.tr()}'),
                selected: selected,
                onSelected: (_) => setState(() => _radius = value),
                selectedColor: AppColors.primaryGreen,
                labelStyle: TextStyle(
                  color: selected ? Colors.white : Colors.black87,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Slider(
            value: _radius.toDouble().clamp(1, 1000),
            min: 1,
            max: 1000,
            divisions: 999,
            activeColor: AppColors.primaryGreen,
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
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('area.point'.tr(),
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                hasPoint ? Icons.place : Icons.place_outlined,
                size: 18,
                color: hasPoint ? AppColors.primaryGreen : Colors.grey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasPoint
                      ? '${_lat!.toStringAsFixed(4)}, ${_lon!.toStringAsFixed(4)}'
                      : 'area.point_not_set'.tr(),
                  style: TextStyle(
                    color: hasPoint ? Colors.black87 : Colors.grey[600],
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _isLocating ? null : _useMyLocation,
            icon: _isLocating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location, size: 18),
            label: Text('area.use_my_location'.tr()),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primaryGreen,
              side: const BorderSide(color: AppColors.primaryGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
