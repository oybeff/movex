import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/equipment_types.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../../taxi/data/taxi_geo.dart';
import '../data/driver_api.dart';
import 'driver_ui.dart';

/// R4 «Texnikangiz» (макет 00/03 «qisqa forma»): тип, марка и модель,
/// госномер, год, цена часа. Точка техники — где водитель сейчас:
/// живого слежения нет, и это честнее, чем просить ткнуть в карту.
///
/// Результат: `true` — техника добавлена.
class DriverEquipmentStep extends StatefulWidget {
  const DriverEquipmentStep({super.key});

  @override
  State<DriverEquipmentStep> createState() => _DriverEquipmentStepState();
}

class _DriverEquipmentStepState extends State<DriverEquipmentStep> {
  final _model = TextEditingController();
  final _plate = TextEditingController();
  final _year = TextEditingController();
  final _price = TextEditingController();
  String _type = 'excavator';
  bool _busy = false;

  @override
  void dispose() {
    _model.dispose();
    _plate.dispose();
    _year.dispose();
    _price.dispose();
    super.dispose();
  }

  bool get _valid => _model.text.trim().isNotEmpty && (int.tryParse(_price.text.replaceAll(' ', '')) ?? 0) > 0;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      final here = await TaxiGeo.current();
      await DriverApi().addEquipment(
        type: _type,
        model: _model.text.trim(),
        plate: _plate.text.trim().toUpperCase(),
        year: int.tryParse(_year.text),
        pricePerHour: int.parse(_price.text.replaceAll(' ', '')),
        lat: here.lat,
        lon: here.lon,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  InputDecoration _field(String label, {String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppPalette.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      );

  @override
  Widget build(BuildContext context) {
    // Весь справочник: тип решает, какие заказы придут водителю
    const types = EquipmentTypes.codes;
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(backgroundColor: AppPalette.page, title: Text('driver.my_equipment'.tr())),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('driver.your_equipment'.tr(), style: AppTypography.h1),
          const SizedBox(height: 4),
          Text('driver.your_equipment_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
          const SizedBox(height: 16),
          Text('driver.equipment_type'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final t in types)
                ChoiceChip(
                  label: Text(EquipmentTypes.label(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                  selectedColor: DChip.blueBg,
                  labelStyle: TextStyle(color: _type == t ? AppPalette.brand : AppPalette.textPrimary),
                ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(controller: _model, onChanged: (_) => setState(() {}), decoration: _field('driver.model'.tr(), hint: 'JCB 3CX')),
          const SizedBox(height: 10),
          TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: _field('driver.plate'.tr(), hint: '01 A 777 BA'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            decoration: _field('driver.made_year'.tr(), hint: '2019'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _price,
            onChanged: (_) => setState(() {}),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: _field('driver.price_hour'.tr(), hint: '400000'),
          ),
          const SizedBox(height: 6),
          Text('driver.price_hour_hint'.tr(), style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: DPrimary('driver.continue'.tr(), busy: _busy, onPressed: _valid ? _save : null),
        ),
      ),
    );
  }
}
