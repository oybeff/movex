import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/models/equipment_request_model.dart';
import '../../../core/services/equipment_request_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/map_or_placeholder.dart';
import '../../requests/presentation/pages/incoming_order_page.dart' show SwipeToAccept;
import '../data/driver_api.dart';
import 'driver_ui.dart';
import '../../../core/widgets/h_icon.dart';

/// Входящий заказ водителя — макет 01: H3 (сейчас, 15 секунд на ответ,
/// свайп), H5 (запланированный — кнопками), H4 (причина отказа).
///
/// Результат: `true` — взял, `false` — отказался, `null` — не ответил
/// (время вышло, E2: дом считает пропуски подряд).
class DriverIncomingPage extends StatefulWidget {
  const DriverIncomingPage({super.key, required this.order});

  final QuickIncomingModel order;

  @override
  State<DriverIncomingPage> createState() => _DriverIncomingPageState();
}

class _DriverIncomingPageState extends State<DriverIncomingPage> {
  static const _seconds = 15;

  final _requests = EquipmentRequestService();
  final _api = DriverApi();
  Timer? _timer;
  int _left = _seconds;
  bool _busy = false;

  QuickIncomingModel get o => widget.order;

  /// «Hozir» — начало сегодня; иначе это «Rejalashtirilgan» (H5).
  bool get _scheduled {
    final now = DateTime.now();
    final d = o.startDate;
    return DateTime(d.year, d.month, d.day).isAfter(DateTime(now.year, now.month, now.day));
  }

  @override
  void initState() {
    super.initState();
    HapticFeedback.heavyImpact();
    SystemSound.play(SystemSoundType.alert);
    // Таймер только у «сейчас»: запланированный можно обдумать
    if (!_scheduled) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _left--);
        if (_left <= 0) {
          _timer?.cancel();
          // Время вышло — «пропустил», без причины. Заказ уходит другим (E2).
          Navigator.of(context).pop(null);
        }
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// E6 «Komissiya uchun balans yetmaydi». В макете — «долг по комиссии с
  /// лимитом»; у нас долга нет вовсе: комиссия наличного заказа
  /// замораживается на балансе при принятии (request_service.quick_accept),
  /// поэтому экран говорит, сколько пополнить, чтобы взять заказ.
  Future<void> _noBalanceSheet() async {
    double available = 0;
    try {
      final b = await _api.balance();
      double n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
      available = n(b['balance']) - n(b['frozen_balance']);
    } catch (_) {}
    final need = (o.price - o.youReceive);
    final missing = (need - available).clamp(0, double.infinity);
    if (!mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: DChip.redBg, borderRadius: BorderRadius.circular(24)),
                child: const HIcon(Icons.account_balance_wallet_outlined, color: AppPalette.textDanger),
              ),
            ),
            const SizedBox(height: 12),
            Text('driver.e6_title'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text('driver.e6_body'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 12),
            DRow('driver.e6_available'.tr(), money(available)),
            DRow('driver.e6_commission'.tr(), money(need)),
            DRow('driver.e6_missing'.tr(), money(missing), bold: true, valueColor: AppPalette.textDanger),
            const SizedBox(height: 14),
            DPrimary('driver.e6_topup'.tr(), onPressed: () => Navigator.of(ctx).pop(true)),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('driver.later'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
    if (go == true && mounted) await context.push('/balance-topup');
  }

  Future<void> _accept() async {
    if (_busy) return;
    _timer?.cancel();
    setState(() => _busy = true);
    HapticFeedback.mediumImpact();
    try {
      await _requests.quickAccept(o.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      int? status;
      String? detail;
      try {
        status = (e as dynamic).response?.statusCode as int?;
        final data = (e as dynamic).response?.data;
        if (data is Map && data['detail'] is String) detail = data['detail'] as String;
      } catch (_) {}
      setState(() => _busy = false);
      if (status == 402 && o.paymentMethod == 'cash') {
        // E6: на комиссию наличного заказа не хватает баланса
        await _noBalanceSheet();
        if (mounted) Navigator.of(context).pop(false);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(status == 409 ? 'requests.quick_taken'.tr() : (detail ?? 'errors.something_went_wrong'.tr())),
      ));
      if (status == 409) Navigator.of(context).pop(false);
    }
  }

  Future<void> _decline() async {
    _timer?.cancel();
    final reason = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _DeclineSheet(),
    );
    if (reason == null) {
      // Передумал отказываться — «сейчас» возвращаем в ожидание без таймера
      if (mounted) setState(() {});
      return;
    }
    try {
      await _api.decline(o.id, reason);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(false);
  }

  String get _when {
    final hours = o.hours != null ? 'driver.hours_n'.tr(args: ['${o.hours}']) : 'driver.days_n'.tr(args: ['${o.days}']);
    if (!_scheduled) return '${'driver.now'.tr()} · $hours';
    final day = DateFormat('d MMMM', context.locale.languageCode).format(o.startDate);
    return '$day, ${o.startTime ?? ''} · $hours';
  }

  @override
  Widget build(BuildContext context) {
    final point = Point(latitude: o.deliveryLatitude, longitude: o.deliveryLongitude);
    final eta = o.distanceKm == null ? null : (o.distanceKm! / 25 * 60).ceil().clamp(3, 999);
    final commission = o.price - o.youReceive;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapOrPlaceholder(
              mapBuilder: (_) => YandexMap(
                onMapCreated: (c) => c.moveCamera(
                  CameraUpdate.newCameraPosition(CameraPosition(target: point, zoom: 14)),
                ),
                mapObjects: [
                  CircleMapObject(
                    mapId: const MapObjectId('client'),
                    circle: Circle(center: point, radius: 70),
                    fillColor: AppPalette.textPrimary,
                    strokeColor: Colors.white,
                    strokeWidth: 3,
                  ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              child: DSheet(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _scheduled
                                  ? DChip('driver.scheduled'.tr(), bg: DChip.blueBg, fg: AppPalette.brand)
                                  : DChip('driver.new_order'.tr(), bg: DChip.warn, fg: AppPalette.textPrimary),
                              const SizedBox(height: 8),
                              Text(orderTitle(o.equipmentType, o.tariff), style: AppTypography.h2),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  if (o.distanceKm != null) '${o.distanceKm!.toStringAsFixed(1)} km',
                                  if (eta != null && !_scheduled) 'driver.arrive_in'.tr(args: ['$eta']),
                                  if (_scheduled) _when,
                                ].join(' · '),
                                style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        if (!_scheduled) _Countdown(left: _left, total: _seconds),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(money(o.price), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        DChip(
                          o.paymentMethod == 'cash'
                              ? 'driver.pay_cash'.tr()
                              : (o.paymentMethod == 'card' ? 'driver.pay_card'.tr() : 'driver.pay_balance'.tr()),
                        ),
                      ],
                    ),
                    Text(
                      'driver.you_get'.tr(args: [money(o.youReceive), money(commission)]),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary),
                    ),
                    if (o.clientRating != null) ...[
                      const SizedBox(height: 6),
                      Row(children: [
                        Text('driver.client_rating'.tr(),
                            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                        const SizedBox(width: 6),
                        const HIcon(Icons.star_rounded, size: 16, color: Color(0xFFF5B400)),
                        Text(o.clientRating!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    DAddress(o.deliveryAddress),
                    const SizedBox(height: 8),
                    DRow('driver.when'.tr(), _when),
                    if ((o.comment ?? '').isNotEmpty) DRow('driver.note'.tr(), o.comment!),
                    const SizedBox(height: 12),
                    if (_scheduled) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: DChip.blueBg, borderRadius: BorderRadius.circular(12)),
                        child: Row(
                          children: [
                            const HIcon(Icons.event_available_rounded, size: 18, color: AppPalette.brand),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text('driver.remind_hour'.tr(),
                                  style: const TextStyle(fontSize: 13, color: AppPalette.brand)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: DSecondary('driver.skip'.tr(), tinted: true, onPressed: _busy ? null : _decline)),
                          const SizedBox(width: 10),
                          Expanded(child: DPrimary('driver.accept'.tr(), busy: _busy, onPressed: _accept)),
                        ],
                      ),
                    ] else ...[
                      SwipeToAccept(
                        label: 'driver.swipe_accept'.tr(),
                        busy: _busy,
                        onAccepted: _accept,
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _busy ? null : _decline,
                          child: Text('driver.decline'.tr(), style: const TextStyle(color: AppPalette.textDanger)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кольцо «15» — сколько секунд осталось ответить.
class _Countdown extends StatelessWidget {
  const _Countdown({required this.left, required this.total});

  final int left;
  final int total;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 48,
        height: 48,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: left / total,
              strokeWidth: 4,
              color: DChip.warn,
              backgroundColor: AppPalette.page,
            ),
            Text('$left', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );
}

/// H4 «Nega rad etyapsiz?».
class _DeclineSheet extends StatefulWidget {
  const _DeclineSheet();

  @override
  State<_DeclineSheet> createState() => _DeclineSheetState();
}

class _DeclineSheetState extends State<_DeclineSheet> {
  static const _reasons = ['far', 'low_price', 'busy', 'not_my_job', 'other'];
  String? _picked;

  @override
  Widget build(BuildContext context) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('driver.why_decline'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text('driver.why_decline_hint'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 12),
            for (final r in _reasons)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _picked = r),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    decoration: BoxDecoration(
                      color: _picked == r ? DChip.blueBg : AppPalette.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _picked == r ? AppPalette.brand : AppPalette.borderDefault),
                    ),
                    child: Row(
                      children: [
                        HIcon(_picked == r ? Icons.radio_button_checked : Icons.radio_button_off,
                            color: _picked == r ? AppPalette.brand : AppPalette.textPlaceholder, size: 22),
                        const SizedBox(width: 10),
                        Text('driver.reason_$r'.tr(), style: const TextStyle(fontSize: 15)),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            DPrimary('driver.send'.tr(), onPressed: _picked == null ? null : () => Navigator.of(context).pop(_picked)),
          ],
        ),
      );
}
