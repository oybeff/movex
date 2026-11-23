import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/material_types.dart';
import '../../../core/theme/app_tokens.dart';
import '../../requests/presentation/pages/incoming_order_page.dart' show SwipeToAccept;
import '../data/delivery_api.dart';
import 'driver_ui.dart';

/// Входящий заказ на доставку стройматериала — как входящий заказ техники:
/// 15 секунд, принять свайпом (случайно не нажмёшь), отказаться кнопкой.
///
/// Результат: `true` — взял, `false` — отказался, `null` — не ответил.
class DeliveryIncomingPage extends StatefulWidget {
  const DeliveryIncomingPage({super.key, required this.order});

  final DeliveryIncoming order;

  @override
  State<DeliveryIncomingPage> createState() => _DeliveryIncomingPageState();
}

class _DeliveryIncomingPageState extends State<DeliveryIncomingPage> {
  static const _seconds = 15;
  final _api = DeliveryApi();
  Timer? _timer;
  int _left = _seconds;
  bool _busy = false;

  DeliveryIncoming get o => widget.order;

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
      await _api.accept(o.id);
      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      final d = e.response?.data;
      final msg = code == 409
          ? 'driver.delivery_taken'.tr()
          : (d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      Navigator.of(context).pop(false);
    }
  }

  String _qty() {
    final q = o.quantity == o.quantity.roundToDouble() ? o.quantity.toStringAsFixed(0) : o.quantity.toString();
    return '$q ${MaterialTypes.unitLabel(o.unit)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  DChip('driver.delivery_new'.tr(), bg: AppPalette.brandSubtle, fg: AppPalette.brand),
                  const Spacer(),
                  Text('$_left s', style: AppTypography.h3.copyWith(color: AppPalette.textDanger)),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: _left / _seconds,
                color: AppPalette.brand,
                backgroundColor: AppPalette.borderDefault,
              ),
              const SizedBox(height: 16),
              Text(money(o.youReceive), style: AppTypography.display),
              Text('driver.delivery_you_receive'.tr(),
                  style: const TextStyle(color: AppPalette.textSecondary)),
              const SizedBox(height: 16),
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('${MaterialTypes.label(o.materialType)} · ${_qty()}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                    if (o.title.isNotEmpty)
                      Text(o.title, style: const TextStyle(color: AppPalette.textSecondary)),
                    const SizedBox(height: 12),
                    _point(Icons.warehouse_outlined, 'driver.delivery_from'.tr(), o.pickupAddress,
                        o.toPickupKm == null ? null : 'driver.km_away'.tr(args: [o.toPickupKm!.toStringAsFixed(1)])),
                    const SizedBox(height: 10),
                    _point(Icons.flag_outlined, 'driver.delivery_to'.tr(), o.deliveryAddress,
                        o.distanceKm == null ? null : '${o.distanceKm!.toStringAsFixed(1)} km'),
                    const Divider(height: 24),
                    DRow('driver.delivery_fee'.tr(), money(o.fee)),
                    DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                    if (o.trips > 1) DRow('driver.delivery_trips'.tr(), '${o.trips}'),
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

  Widget _point(IconData icon, String label, String? address, String? extra) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: AppPalette.brand),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
              Text(address ?? 'driver.delivery_map_point'.tr(), style: const TextStyle(fontSize: 15)),
              if (extra != null) Text(extra, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
            ],
          ),
        ),
      ],
    );
  }
}
