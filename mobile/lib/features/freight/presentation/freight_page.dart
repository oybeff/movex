import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/number_formatter.dart';
import '../../taxi/data/taxi_geo.dart';
import '../../taxi/presentation/pages/address_pick_page.dart';
import '../data/freight_api.dart';
import 'freight_orders_page.dart';

/// «Yuk tashish» — клиент везёт СВОЙ груз из А в Б (просьба Шерзодбека
/// 24.11.2026): Labo, Porter, Gazel, Isuzu, KamAZ, HOWO… с тоннажем.
///
/// Сколько тонн → сервер подсказывает самую малую подходящую машину,
/// клиент может выбрать другую. У бортовых — tentli / tentsiz. Цену
/// считает сервер (`/freight/quote`) по режиму машины из админки: по км
/// или по часам.
class FreightPage extends StatefulWidget {
  const FreightPage({super.key, required this.from, this.vehicleCode});

  final TaxiPlace from;

  /// Машина, выбранная заранее (из «Barcha kategoriyalar»).
  final String? vehicleCode;

  @override
  State<FreightPage> createState() => _FreightPageState();
}

class _FreightPageState extends State<FreightPage> {
  final _api = FreightApi();
  final _tonnes = TextEditingController();
  final _note = TextEditingController();
  late TaxiPlace _from = widget.from;
  TaxiPlace? _to;
  FreightQuote? _quote;
  String? _vehicle;
  String? _body;
  int? _hours;
  bool _cash = false;
  bool _loading = false;
  bool _sending = false;
  bool _userPicked = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _vehicle = widget.vehicleCode;
    _userPicked = widget.vehicleCode != null;
    _tonnes.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 450), _load);
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _tonnes.dispose();
    _note.dispose();
    super.dispose();
  }

  double? get _tonnesValue => double.tryParse(_tonnes.text.replaceAll(',', '.').trim());

  FreightVehicle? get _selected => _quote?.vehicles.where((v) => v.code == _vehicle).firstOrNull;

  Future<void> _pick(bool from) async {
    final place = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => AddressPickPage(from: _from, forSaving: true)),
    );
    if (place == null || !mounted) return;
    setState(() => from ? _from = place : _to = place);
    _load();
  }

  Future<void> _load() async {
    final to = _to;
    if (to == null) return;
    setState(() => _loading = true);
    try {
      final q = await _api.quote(
        fromLat: _from.lat,
        fromLon: _from.lon,
        toLat: to.lat,
        toLon: to.lon,
        tonnes: _tonnesValue,
        hours: _hours,
      );
      if (!mounted) return;
      setState(() {
        _quote = q;
        // Подсказка сервера — пока клиент сам не выбрал машину
        if (!_userPicked && q.suggested != null) _vehicle = q.suggested;
        _vehicle ??= q.vehicles.where((v) => v.price != null).firstOrNull?.code;
      });
    } catch (_) {
      if (mounted) _toast('errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _order() async {
    final v = _selected;
    final to = _to;
    if (to == null) return _toast('freight.pick_to'.tr());
    if (v == null || v.price == null) return _toast('freight.pick_vehicle'.tr());
    if (v.bodyChoice && _body == null) return _toast('freight.pick_body'.tr());
    final t = _tonnesValue;
    if (t != null && t * 1000 > v.capacityKg) return _toast('freight.too_heavy'.tr(args: [v.name]));
    setState(() => _sending = true);
    try {
      await _api.create({
        'vehicle_code': v.code,
        if (v.bodyChoice) 'body_type': _body,
        if (t != null && t > 0) 'cargo_tonnes': t,
        if (_note.text.trim().isNotEmpty) 'cargo_note': _note.text.trim(),
        'from_address': _from.address ?? _from.label,
        'from_latitude': _from.lat,
        'from_longitude': _from.lon,
        'to_address': to.address ?? to.label,
        'to_latitude': to.lat,
        'to_longitude': to.lon,
        if (v.hourly) 'hours': v.hours ?? v.minHours,
        'payment_method': _cash ? 'cash' : 'balance',
      });
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const FreightOrdersPage()));
    } on DioException catch (e) {
      final d = e.response?.data;
      _toast(d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String m) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  String _sum(double v) => '${NumberFormatter.formatCurrency(v)} ${'common.currency'.tr()}';

  String _t(double t) => t == t.roundToDouble() ? t.toStringAsFixed(0) : t.toString().replaceAll('.', ',');

  @override
  Widget build(BuildContext context) {
    final v = _selected;
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text('freight.title'.tr(), style: AppTypography.h3),
        actions: [
          IconButton(
            tooltip: 'freight.my_orders'.tr(),
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FreightOrdersPage())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          _card([
            _point(Icons.radio_button_checked, 'freight.from'.tr(), _from.address ?? _from.label, () => _pick(true)),
            const Divider(height: 1),
            _point(Icons.flag_outlined, 'freight.to'.tr(), _to == null ? null : (_to!.address ?? _to!.label),
                () => _pick(false)),
          ]),
          const SizedBox(height: 12),
          _card([
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _tonnes,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
                decoration: InputDecoration(
                  labelText: 'freight.tonnes'.tr(),
                  hintText: 'freight.tonnes_hint'.tr(),
                  suffixText: 't',
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (_to == null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('freight.pick_to_first'.tr(), style: const TextStyle(color: AppPalette.textSecondary)),
            )
          else if (_loading && _quote == null)
            const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
          else if (_quote != null) ...[
            Text('freight.vehicle'.tr(args: [_quote!.distanceKm.toStringAsFixed(1)]),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final x in _quote!.vehicles) _vehicleTile(x),
          ],
          if (v != null && v.bodyChoice) ...[
            const SizedBox(height: 12),
            Text('freight.body'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
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
          if (v != null && v.hourly) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: Text('freight.hours'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
                IconButton(
                  onPressed: (v.hours ?? v.minHours) <= v.minHours
                      ? null
                      : () {
                          _hours = (v.hours ?? v.minHours) - 1;
                          _load();
                        },
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text('${v.hours ?? v.minHours}', style: AppTypography.h3),
                IconButton(
                  onPressed: () {
                    _hours = (v.hours ?? v.minHours) + 1;
                    _load();
                  },
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text('freight.payment'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            ChoiceChip(label: Text('freight.pay_wallet'.tr()), selected: !_cash, onSelected: (_) => setState(() => _cash = false)),
            ChoiceChip(label: Text('freight.pay_cash'.tr()), selected: _cash, onSelected: (_) => setState(() => _cash = true)),
          ]),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'freight.note'.tr(),
              hintText: 'freight.note_hint'.tr(),
              filled: true,
              fillColor: AppPalette.surface,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            height: 52,
            child: FilledButton(
              onPressed: _sending || v?.price == null ? null : _order,
              child: _sending
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(v?.price == null ? 'freight.order'.tr() : '${'freight.order'.tr()} · ${_sum(v!.price!)}'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      );

  Widget _point(IconData icon, String label, String? value, VoidCallback onTap) => ListTile(
        leading: Icon(icon, color: AppPalette.brand),
        title: Text(label, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
        subtitle: Text(value ?? 'freight.choose_address'.tr(),
            style: TextStyle(fontSize: 15, color: value == null ? AppPalette.textBrand : AppPalette.textPrimary)),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      );

  Widget _vehicleTile(FreightVehicle x) {
    final on = x.code == _vehicle;
    final t = _tonnesValue;
    final small = t != null && t * 1000 > x.capacityKg;
    final disabled = x.price == null || small;
    return Opacity(
      opacity: disabled ? .45 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: on ? AppPalette.brand : AppPalette.borderDefault, width: on ? 2 : 1),
        ),
        child: ListTile(
          onTap: disabled
              ? null
              : () => setState(() {
                    _vehicle = x.code;
                    _userPicked = true;
                    if (!x.bodyChoice) _body = null;
                  }),
          leading: const Icon(Icons.local_shipping_outlined, color: AppPalette.brand),
          title: Text(x.name, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(
            [
              'freight.up_to'.tr(args: [_t(x.tonnes)]),
              if (x.hourly) 'freight.hours_n'.tr(args: ['${x.hours ?? x.minHours}']),
              if (small) 'freight.too_small'.tr(),
            ].join(' · '),
          ),
          trailing: Text(x.price == null ? 'freight.no_price'.tr() : _sum(x.price!),
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
      ),
    );
  }
}
