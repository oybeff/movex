import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/constants/equipment_types.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/map_or_placeholder.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';
import 'orders_page.dart' show cardSubStyle, cardTitleStyle;

/// M3 · Buyurtma tafsiloti. Закрывается с [TaxiNav.repeat] на «Qayta
/// buyurtma berish».
class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({super.key, required this.card});

  final OrderCard card;

  String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// «8-noyabr, 09:30 – 13:30 · 4 soat»
  String get _when {
    final c = card;
    final start = c.startedAt ?? c.startAt;
    if (start == null) return '';
    final end = c.finishedAt ?? (c.hours == null ? null : start.add(Duration(hours: c.hours!)));
    return [
      '${taxiDate(start)}, ${_hm(start)}${end == null ? '' : ' – ${_hm(end)}'}',
      if (c.hours != null) 'taxi.hours_n'.tr(args: ['${c.hours}']),
    ].join(' · ');
  }

  String _sum(num v) => "${formatSum(v)} ${'common.currency'.tr()}";

  Future<void> _call() async {
    final p = card.ownerPhone;
    if (p == null) return;
    await launchUrl(Uri.parse('tel:+${p.replaceAll(RegExp(r'\D'), '')}'));
  }

  /// «Chekni yuklab olish»: чек на экране — его можно показать или снять
  /// скриншотом. Отдельного файла чека сервер пока не отдаёт.
  void _receipt(BuildContext context, List<MapEntry<String, String>> rows) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('taxi.order_n'.tr(args: ['${card.orderId}']), style: AppTypography.h2),
              const SizedBox(height: 4),
              Text(_when, style: AppTypography.subtitle),
              const SizedBox(height: 12),
              for (final r in rows) InfoRow(r.key, r.value),
              const Divider(height: 20),
              InfoRow('taxi.total'.tr(), _sum(card.total), bold: true),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = card;
    final hours = c.hours ?? 0;
    final att = c.attachmentPrice * hours;
    final work = (c.total - att - c.deliveryFee).clamp(0, double.infinity);
    final perHour = hours > 0 ? work / hours : work;
    final rows = <MapEntry<String, String>>[
      MapEntry(
        hours > 0
            ? '${'taxi.work_time'.tr()} · ${'taxi.hours_n'.tr(args: ['$hours'])} × ${formatSum(perHour)}'
            : 'taxi.work_time'.tr(),
        _sum(work),
      ),
      if (att > 0) MapEntry(c.attachmentName ?? 'taxi.attachment'.tr(), _sum(att)),
      if (c.deliveryFee > 0) MapEntry('taxi.delivery'.tr(), _sum(c.deliveryFee)),
      MapEntry('taxi.payment_method'.tr(),
          c.cash ? 'taxi.pay_cash'.tr() : (c.paymentMethod == 'card' ? (c.cardLabel ?? 'taxi.bank_card'.tr()) : 'taxi.pay_balance'.tr())),
    ];
    final title = [EquipmentTypes.label(c.type), if ((c.model ?? '').isNotEmpty) c.model!].join(' · ');
    final sub = [
      if ((c.plate ?? '').isNotEmpty) c.plate!,
      if ((c.attachmentName ?? '').isNotEmpty && att > 0) 'taxi.with_attachment'.tr(args: [c.attachmentName!]),
    ].join(' · ');
    final rating = [
      if (c.ownerRating != null) c.ownerRating!.toStringAsFixed(1),
      if (c.myRating != null) 'taxi.you_rated'.tr(args: ['${c.myRating}']),
    ].join(' · ');
    final target = c.toLat == null ? null : Point(latitude: c.toLat!, longitude: c.toLon!);

    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.order_n'.tr(args: ['${c.orderId}'])),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 16),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      height: 150,
                      color: AppPalette.surface,
                      child: MapOrPlaceholder(
                        hintKey: 'taxi.map_web_hint',
                        mapBuilder: (_) => YandexMap(
                          scrollGesturesEnabled: false,
                          zoomGesturesEnabled: false,
                          rotateGesturesEnabled: false,
                          tiltGesturesEnabled: false,
                          onMapCreated: (m) {
                            if (target != null) {
                              m.moveCamera(CameraUpdate.newCameraPosition(
                                CameraPosition(target: target, zoom: 15),
                              ));
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text('taxi.stage_title_${c.stage}'.tr(), style: AppTypography.h3)),
                            TaxiBadge.stage(c.stage),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(_when, style: AppTypography.subtitle),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Box(
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration:
                                  BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
                              alignment: Alignment.center,
                              child: EquipmentPhoto(c.type, width: 44, height: 44, background: AppPalette.page),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(title, style: cardTitleStyle),
                                  if (sub.isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(sub, style: cardSubStyle),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (c.ownerName != null) ...[
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(color: AppPalette.accent, shape: BoxShape.circle),
                                alignment: Alignment.center,
                                child: Text(
                                  c.ownerInitials ?? '',
                                  style: const TextStyle(
                                    fontFamily: AppTypography.fontFamily,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppPalette.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.ownerName!,
                                      style: cardTitleStyle.copyWith(fontWeight: FontWeight.w500),
                                    ),
                                    if (rating.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const TaxiIcon('star_fill', size: 14),
                                          const SizedBox(width: 4),
                                          Text(rating, style: cardSubStyle),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              if (c.ownerPhone != null) TaxiRoundButton(icon: 'phone_brand', onTap: _call),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _Box(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('taxi.bill'.tr(), style: AppTypography.bodyMedium),
                        const SizedBox(height: 8),
                        for (final r in rows) InfoRow(r.key, r.value),
                        const SizedBox(height: 4),
                        Container(height: 1, color: AppPalette.borderDefault),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'taxi.total'.tr(),
                                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, height: 22 / 16),
                              ),
                            ),
                            Text(
                              _sum(c.stage == 'cancelled' ? 0 : c.total),
                              style: const TextStyle(
                                fontFamily: AppTypography.fontFamily,
                                fontSize: 18,
                                height: 24 / 18,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(TaxiNav.repeat(c.asRequest())),
                    child: Text('taxi.repeat_order'.tr()),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: AppSpacing.buttonHeight,
                    child: TextButton(
                      onPressed: c.stage == 'completed' ? () => _receipt(context, rows) : null,
                      style: TextButton.styleFrom(
                        foregroundColor: AppPalette.textBrand,
                        textStyle: AppTypography.buttonLarge,
                      ),
                      child: Text('taxi.receipt'.tr()),
                    ),
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

class _Box extends StatelessWidget {
  const _Box({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: child,
      );
}
