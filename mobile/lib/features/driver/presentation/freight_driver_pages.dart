import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_tokens.dart';
import '../../freight/data/freight_api.dart';
import '../../requests/presentation/pages/incoming_order_page.dart' show SwipeToAccept;
import 'driver_ui.dart';

String _cargo(double? tonnes, String? body, String? note, {String? type, bool loader = false, DateTime? when}) => [
      if (type != null) 'freight.cargo_$type'.tr(),
      if (tonnes != null) '$tonnes t',
      if (body != null) 'freight.body_$body'.tr(),
      if (loader) 'freight.loader'.tr(),
      if (when != null) '${when.day.toString().padLeft(2, '0')}.${when.month.toString().padLeft(2, '0')} '
          '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
      if (note != null && note.isNotEmpty) note,
    ].join(' · ');

/// Входящий «Yuk tashish»: 15 секунд, принять свайпом.
/// `true` — взял, `false` — отказался, `null` — не ответил.
class FreightIncomingPage extends StatefulWidget {
  const FreightIncomingPage({super.key, required this.order});

  final FreightIncoming order;

  @override
  State<FreightIncomingPage> createState() => _FreightIncomingPageState();
}

class _FreightIncomingPageState extends State<FreightIncomingPage> {
  static const _seconds = 15;
  final _api = FreightApi();
  Timer? _timer;
  int _left = _seconds;
  bool _busy = false;

  FreightIncoming get o => widget.order;

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _left--);
      if (_left <= 0) {
        _timer?.cancel();
        Navigator.of(context).pop();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _accept() async {
    _timer?.cancel();
    setState(() => _busy = true);
    try {
      await _api.step(o.id, 'accept');
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final d = e.response?.data;
      final msg = e.response?.statusCode == 409
          ? 'driver.delivery_taken'.tr()
          : (d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cargo = _cargo(o.tonnes, o.bodyType, o.note, type: o.cargoType, loader: o.needsLoader, when: o.scheduledAt);
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(children: [
                DChip('driver.freight_new'.tr(), bg: AppPalette.brandSubtle, fg: AppPalette.brand),
                const Spacer(),
                Text('$_left s', style: AppTypography.h3.copyWith(color: AppPalette.textDanger)),
              ]),
              const SizedBox(height: 4),
              LinearProgressIndicator(value: _left / _seconds, color: AppPalette.brand),
              const SizedBox(height: 16),
              Text(money(o.youReceive), style: AppTypography.display),
              Text('driver.delivery_you_receive'.tr(), style: const TextStyle(color: AppPalette.textSecondary)),
              const SizedBox(height: 16),
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (cargo.isNotEmpty)
                      Text(cargo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 10),
                    DRow('freight.from'.tr(), o.fromAddress ?? 'driver.delivery_map_point'.tr()),
                    if (o.toPickupKm != null) DRow('', 'driver.km_away'.tr(args: [o.toPickupKm!.toStringAsFixed(1)])),
                    DRow('freight.to'.tr(), o.toAddress ?? 'driver.delivery_map_point'.tr()),
                    DRow('driver.freight_route'.tr(), '${o.distanceKm.toStringAsFixed(1)} km'),
                    if (o.hours != null) DRow('freight.hours'.tr(), 'freight.hours_n'.tr(args: ['${o.hours}'])),
                    const Divider(height: 20),
                    DRow('driver.delivery_fee'.tr(), money(o.fee)),
                    DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                    DRow('driver.delivery_payment'.tr(),
                        o.cash ? 'driver.delivery_cash'.tr() : 'driver.delivery_wallet'.tr(), bold: true),
                  ],
                ),
              ),
              const Spacer(),
              SwipeToAccept(label: 'driver.delivery_swipe'.tr(), busy: _busy, onAccepted: _accept),
              const SizedBox(height: 10),
              DSecondary('driver.delivery_skip'.tr(), onPressed: _busy ? null : () => Navigator.of(context).pop(false)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Принятый «Yuk tashish»: accepted → «Yuk ortildi» → loaded →
/// «Yetib keldim» → arrived → клиент жмёт «Yakunlash».
class FreightDriverOrderPage extends StatefulWidget {
  const FreightDriverOrderPage({super.key, required this.order});

  final FreightOrder order;

  @override
  State<FreightDriverOrderPage> createState() => _FreightDriverOrderPageState();
}

class _FreightDriverOrderPageState extends State<FreightDriverOrderPage> {
  final _api = FreightApi();
  late FreightOrder o = widget.order;
  bool _busy = false;

  Future<void> _reload() async {
    try {
      final all = await _api.driverOrders();
      final fresh = all.where((x) => x.id == o.id).firstOrNull;
      if (fresh != null && mounted) setState(() => o = fresh);
    } catch (_) {}
  }

  Future<void> _step(String step, {bool close = false}) async {
    setState(() => _busy = true);
    try {
      final r = await _api.step(o.id, step);
      if (!mounted) return;
      if (close) {
        Navigator.of(context).pop();
        return;
      }
      setState(() => o = r);
    } on DioException catch (e) {
      final d = e.response?.data;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr()),
        ));
      }
      await _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _navigate(double lat, double lon) async {
    final nav = Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    await launchUrl(Uri.parse('https://yandex.uz/maps/?rtext=~$lat,$lon&rtt=auto'), mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final toA = o.status == 'accepted';
    final done = o.status == 'done' || o.status == 'cancelled';
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text('driver.freight_order'.tr(args: ['${o.id}']), style: AppTypography.h3),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DChip('freight.st_${o.status}'.tr(), bg: AppPalette.brandSubtle, fg: AppPalette.brand),
            const SizedBox(height: 12),
            DCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text([o.vehicleName, _cargo(o.tonnes, o.bodyType, o.note, type: o.cargoType, loader: o.needsLoader, when: o.scheduledAt)]
                          .where((x) => x.isNotEmpty)
                          .join(' · '),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(toA ? 'driver.freight_go_a'.tr() : 'driver.freight_go_b'.tr(),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                  Text((toA ? o.fromAddress : o.toAddress) ?? 'driver.delivery_map_point'.tr(),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  Text(o.clientName ?? '', style: const TextStyle(color: AppPalette.textSecondary)),
                  if (!done) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: DAction(
                          icon: Icons.call_outlined,
                          label: 'driver.call'.tr(),
                          onTap: () => o.clientPhone == null
                              ? null
                              : launchUrl(Uri.parse('tel:+${o.clientPhone!.replaceAll(RegExp(r'[^0-9]'), '')}')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DAction(
                          icon: Icons.navigation_outlined,
                          label: 'driver.navigate'.tr(),
                          accent: true,
                          onTap: () => toA ? _navigate(o.fromLat, o.fromLon) : _navigate(o.toLat, o.toLon),
                        ),
                      ),
                    ]),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            DCard(
              child: Column(children: [
                DRow('driver.delivery_fee'.tr(), money(o.driverFee)),
                DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                DRow('driver.delivery_you_receive'.tr(), money(o.driverFee - o.commission), bold: true),
                DRow('driver.delivery_payment'.tr(), o.cash ? 'driver.delivery_cash'.tr() : 'driver.delivery_wallet'.tr()),
              ]),
            ),
            if (o.status == 'arrived') ...[
              const SizedBox(height: 12),
              DCard(
                color: AppPalette.accentSubtle,
                child: Text(
                  o.cash ? 'driver.freight_take_cash'.tr(args: [money(o.price)]) : 'driver.freight_wait_client'.tr(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: done
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (o.status == 'accepted')
                      DPrimary('driver.freight_loaded'.tr(), busy: _busy, onPressed: _busy ? null : () => _step('loaded')),
                    if (o.status == 'loaded')
                      DPrimary('driver.delivery_arrived'.tr(), busy: _busy, onPressed: _busy ? null : () => _step('arrived')),
                    if (o.status == 'arrived') DSecondary('driver.delivery_refresh'.tr(), onPressed: _reload),
                    if (o.status == 'accepted') ...[
                      const SizedBox(height: 8),
                      DSecondary('driver.delivery_cancel'.tr(),
                          onPressed: _busy ? null : () => _step('cancel', close: true)),
                    ],
                  ],
                ),
              ),
            ),
    );
  }
}
