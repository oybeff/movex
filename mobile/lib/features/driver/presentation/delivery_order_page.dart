import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/material_types.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/delivery_api.dart';
import 'driver_ui.dart';

/// Доставка стройматериала, которую водитель принял:
///
///   accepted  → едет на склад: адрес, звонок продавцу, навигатор,
///               «Tovarni oldim» (или отказ — заказ уйдёт другому);
///   picked_up → везёт клиенту: адрес, звонок, навигатор, «Yetib keldim»;
///   arrived   → ждёт, пока клиент нажмёт «Yetkazildi». Наличная
///               доставка — «Naqd pulni oling: …».
///   done      → готово, сколько заработал.
class DeliveryOrderPage extends StatefulWidget {
  const DeliveryOrderPage({super.key, required this.order});

  final DeliveryOrder order;

  @override
  State<DeliveryOrderPage> createState() => _DeliveryOrderPageState();
}

class _DeliveryOrderPageState extends State<DeliveryOrderPage> {
  final _api = DeliveryApi();
  late DeliveryOrder o = widget.order;
  bool _busy = false;

  Future<void> _reload() async {
    try {
      final all = await _api.orders();
      final fresh = all.where((x) => x.id == o.id).firstOrNull;
      if (fresh != null && mounted) setState(() => o = fresh);
    } catch (_) {}
  }

  Future<void> _do(Future<DeliveryOrder> Function(int) step, {bool close = false}) async {
    setState(() => _busy = true);
    try {
      final r = await step(o.id);
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

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('driver.delivery_cancel_q'.tr()),
        content: Text('driver.delivery_cancel_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.back'.tr())),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('driver.delivery_cancel'.tr())),
        ],
      ),
    );
    if (ok == true) await _do(_api.cancel, close: true);
  }

  Future<void> _call(String? phone) async {
    if (phone == null) return;
    await launchUrl(Uri.parse('tel:+${phone.replaceAll(RegExp(r'[^0-9]'), '')}'));
  }

  Future<void> _navigate(double? lat, double? lon) async {
    if (lat == null || lon == null) return;
    final nav = Uri.parse('yandexnavi://build_route_on_map?lat_to=$lat&lon_to=$lon');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    await launchUrl(Uri.parse('https://yandex.uz/maps/?rtext=~$lat,$lon&rtt=auto'),
        mode: LaunchMode.externalApplication);
  }

  String _qty() {
    final q = o.quantity == o.quantity.roundToDouble() ? o.quantity.toStringAsFixed(0) : o.quantity.toString();
    return '$q ${MaterialTypes.unitLabel(o.unit)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = o.deliveryStatus;
    final toPickup = s == 'accepted';
    final done = o.status == 'delivered' || s == 'done';
    final closed = o.status == 'cancelled' || o.status == 'rejected' || s == 'cancelled';
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text('driver.delivery_order'.tr(args: ['${o.id}']), style: AppTypography.h3),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DChip(_statusText(s, done, closed),
                bg: done ? AppPalette.successSubtle : AppPalette.brandSubtle,
                fg: done ? AppPalette.textSuccess : AppPalette.brand),
            const SizedBox(height: 12),
            DCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('${MaterialTypes.label(o.materialType)} · ${_qty()}',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                  if (o.title.isNotEmpty) Text(o.title, style: const TextStyle(color: AppPalette.textSecondary)),
                  if (o.trips > 1)
                    Text('driver.delivery_trips_n'.tr(args: ['${o.trips}']),
                        style: const TextStyle(color: AppPalette.textSecondary)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (!done && !closed) ...[
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(toPickup ? 'driver.delivery_go_pickup'.tr() : 'driver.delivery_go_client'.tr(),
                        style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                    const SizedBox(height: 4),
                    Text((toPickup ? o.pickupAddress : o.deliveryAddress) ?? 'driver.delivery_map_point'.tr(),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text(toPickup ? (o.sellerName ?? '') : (o.buyerName ?? ''),
                        style: const TextStyle(color: AppPalette.textSecondary)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DAction(
                            icon: Icons.call_outlined,
                            label: 'driver.call'.tr(),
                            onTap: () => _call(toPickup ? o.sellerPhone : o.buyerPhone),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DAction(
                            icon: Icons.navigation_outlined,
                            label: 'driver.navigate'.tr(),
                            accent: true,
                            onTap: () => toPickup
                                ? _navigate(o.pickupLat, o.pickupLon)
                                : _navigate(o.deliveryLat, o.deliveryLon),
                          ),
                        ),
                      ],
                    ),
                    if (!toPickup && (o.comment ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text('“${o.comment}”', style: const TextStyle(fontStyle: FontStyle.italic)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            DCard(
              child: Column(
                children: [
                  DRow('driver.delivery_fee'.tr(), money(o.fee)),
                  DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                  DRow('driver.delivery_you_receive'.tr(), money(o.fee - o.commission), bold: true),
                  DRow('driver.delivery_payment'.tr(),
                      o.cash ? 'driver.delivery_cash'.tr() : 'driver.delivery_wallet'.tr()),
                ],
              ),
            ),
            if (s == 'arrived') ...[
              const SizedBox(height: 12),
              DCard(
                color: AppPalette.accentSubtle,
                child: Text(
                  o.cash
                      ? 'driver.delivery_take_cash'.tr(args: [money(o.fee)])
                      : 'driver.delivery_wait_client'.tr(),
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: done || closed
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (s == 'accepted')
                      DPrimary('driver.delivery_picked_up'.tr(), busy: _busy,
                          onPressed: _busy ? null : () => _do(_api.pickedUp)),
                    if (s == 'picked_up')
                      DPrimary('driver.delivery_arrived'.tr(), busy: _busy,
                          onPressed: _busy ? null : () => _do(_api.arrived)),
                    if (s == 'arrived')
                      DSecondary('driver.delivery_refresh'.tr(), onPressed: _busy ? null : _reload),
                    if (s == 'accepted') ...[
                      const SizedBox(height: 8),
                      DSecondary('driver.delivery_cancel'.tr(), onPressed: _busy ? null : _cancel),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  String _statusText(String? s, bool done, bool closed) {
    if (done) return 'driver.delivery_st_done'.tr();
    if (closed) return 'driver.delivery_st_cancelled'.tr();
    switch (s) {
      case 'accepted':
        return 'driver.delivery_st_accepted'.tr();
      case 'picked_up':
        return 'driver.delivery_st_picked_up'.tr();
      case 'arrived':
        return 'driver.delivery_st_arrived'.tr();
    }
    return s ?? '';
  }
}
