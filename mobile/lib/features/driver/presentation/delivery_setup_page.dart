import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/material_types.dart';
import '../../../core/models/material_model.dart';
import '../../../core/services/material_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/delivery_api.dart';
import 'driver_ui.dart';

/// «Yuk mashinam» — водитель, который возит стройматериалы (ТЗ 23.11.2026).
///
/// Машину выбирает из списка админки (Damas … HOWO), грузоподъёмность
/// берётся оттуда же. Отмечает, что возит, и с какого количества
/// («Penablok — 50 dona dan»): заказ меньше минимума ему не придёт. Своя
/// цена за км необязательна — клиент всё равно не платит больше расчёта
/// по ценам админки. Возвращает `true`, если сохранено.
class DeliverySetupPage extends StatefulWidget {
  const DeliverySetupPage({super.key});

  @override
  State<DeliverySetupPage> createState() => _DeliverySetupPageState();
}

class _DeliverySetupPageState extends State<DeliverySetupPage> {
  final _api = DeliveryApi();
  final _plate = TextEditingController();
  final _perKm = TextEditingController();
  final _base = TextEditingController();

  List<DeliveryVehicleModel> _vehicles = const [];
  List<DeliveryCategory> _cats = const [];
  String? _vehicle;
  String? _body;

  bool get _bodyChoice => _vehicles.where((v) => v.code == _vehicle).firstOrNull?.hasBodyChoice ?? false;
  final Map<String, TextEditingController> _mins = {};
  final Set<String> _picked = {};
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _plate.dispose();
    _perKm.dispose();
    _base.dispose();
    for (final c in _mins.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final lang = context.locale.languageCode;
    try {
      final res = await Future.wait([
        MaterialService().getVehicles(),
        _api.categories(lang),
        _api.profile(),
      ]);
      final p = res[2] as DeliveryProfile;
      _vehicles = res[0] as List<DeliveryVehicleModel>;
      _cats = res[1] as List<DeliveryCategory>;
      for (final c in _cats) {
        final min = p.categories[c.code];
        _mins[c.code] = TextEditingController(text: min == null ? '' : _fmt(min));
        if (min != null) _picked.add(c.code);
      }
      _vehicle = p.vehicleCode;
      _body = p.bodyType;
      _plate.text = p.plate ?? '';
      _perKm.text = p.pricePerKm == null ? '' : _fmt(p.pricePerKm!);
      _base.text = p.baseFee == null ? '' : _fmt(p.baseFee!);
    } catch (_) {
      _error = 'driver.delivery_load_failed'.tr();
    }
    if (mounted) setState(() => _loading = false);
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  static double? _parse(String s) {
    final t = s.replaceAll(' ', '').replaceAll(',', '.');
    if (t.isEmpty) return null;
    return double.tryParse(t);
  }

  Future<void> _save() async {
    if (_vehicle == null) {
      _toast('driver.delivery_pick_vehicle'.tr());
      return;
    }
    if (_bodyChoice && _body == null) {
      _toast('driver.delivery_pick_body'.tr());
      return;
    }
    final cats = <String, double>{};
    for (final code in _picked) {
      final v = _parse(_mins[code]!.text) ?? 1;
      if (v <= 0) {
        _toast('driver.delivery_bad_min'.tr());
        return;
      }
      cats[code] = v;
    }
    setState(() => _saving = true);
    try {
      await _api.saveProfile(
        vehicleCode: _vehicle!,
        plate: _plate.text.trim().isEmpty ? null : _plate.text.trim(),
        pricePerKm: _parse(_perKm.text),
        baseFee: _parse(_base.text),
        bodyType: _bodyChoice ? _body : null,
        categories: cats,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final d = e.response?.data;
      _toast(d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text('driver.delivery_title'.tr(), style: AppTypography.h3),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                  children: [
                    Text('driver.delivery_intro'.tr(),
                        style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                    const SizedBox(height: 16),
                    _section('driver.delivery_vehicle'.tr()),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final v in _vehicles)
                          ChoiceChip(
                            label: Text(DeliveryVehicles.label(v.code)),
                            selected: _vehicle == v.code,
                            onSelected: (_) => setState(() => _vehicle = v.code),
                            selectedColor: AppPalette.brandSubtle,
                            side: BorderSide(color: _vehicle == v.code ? AppPalette.brand : AppPalette.borderDefault),
                          ),
                      ],
                    ),
                    if (_bodyChoice) ...[
                      const SizedBox(height: 12),
                      Text('driver.delivery_body'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 8, children: [
                        ChoiceChip(
                          label: Text('freight.body_tent'.tr()),
                          selected: _body == 'tent',
                          onSelected: (_) => setState(() => _body = 'tent'),
                        ),
                        ChoiceChip(
                          label: Text('freight.body_open'.tr()),
                          selected: _body == 'open',
                          onSelected: (_) => setState(() => _body = 'open'),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    _field(_plate, 'driver.delivery_plate'.tr(), hint: '01 A 123 BC', caps: true),
                    const SizedBox(height: 20),
                    _section('driver.delivery_what'.tr()),
                    Text('driver.delivery_what_hint'.tr(),
                        style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                    const SizedBox(height: 8),
                    for (final c in _cats) _catRow(c),
                    const SizedBox(height: 20),
                    _section('driver.delivery_price'.tr()),
                    Text('driver.delivery_price_hint'.tr(),
                        style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: _field(_base, 'driver.delivery_base_fee'.tr(), number: true)),
                        const SizedBox(width: 10),
                        Expanded(child: _field(_perKm, 'driver.delivery_per_km'.tr(), number: true)),
                      ],
                    ),
                  ],
                ),
      bottomNavigationBar: _loading || _error != null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: DPrimary('driver.delivery_save'.tr(), busy: _saving, onPressed: _saving ? null : _save),
              ),
            ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      );

  Widget _catRow(DeliveryCategory c) {
    final on = _picked.contains(c.code);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: on ? AppPalette.brand : AppPalette.borderDefault),
      ),
      child: Row(
        children: [
          Checkbox(
            value: on,
            activeColor: AppPalette.brand,
            onChanged: (v) => setState(() => v == true ? _picked.add(c.code) : _picked.remove(c.code)),
          ),
          Expanded(child: Text(c.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
          if (on)
            SizedBox(
              width: 120,
              child: TextField(
                controller: _mins[c.code],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  isDense: true,
                  labelText: 'driver.delivery_min_from'.tr(),
                  suffixText: MaterialTypes.unitLabel(c.unit),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {String? hint, bool number = false, bool caps = false}) {
    return TextField(
      controller: c,
      textCapitalization: caps ? TextCapitalization.characters : TextCapitalization.none,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppPalette.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        suffixText: number ? 'common.currency'.tr() : null,
      ),
    );
  }
}
