import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../../core/models/notification_model.dart';
import '../../../../core/services/notification_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../widgets/taxi_ui.dart';
import 'app_status_pages.dart' show HaloState;

/// M5 · Bildirishnomalar.
class TaxiNotificationsPage extends StatefulWidget {
  const TaxiNotificationsPage({super.key});

  @override
  State<TaxiNotificationsPage> createState() => _TaxiNotificationsPageState();
}

class _TaxiNotificationsPageState extends State<TaxiNotificationsPage> {
  final _service = NotificationService();
  List<NotificationModel>? _items;
  bool _pushOff = false; // U5

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _checkPush() async {
    if (kIsWeb) return;
    final st = await Permission.notification.status;
    if (mounted) setState(() => _pushOff = !st.isGranted);
  }

  Future<void> _enablePush() async {
    final st = await Permission.notification.request();
    if (!st.isGranted) await openAppSettings();
    _checkPush();
  }

  Future<void> _load() async {
    _checkPush();
    try {
      final items = await _service.getNotifications();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _items = const []);
    }
  }

  Future<void> _readAll() async {
    try {
      await _service.markAllRead();
      await _load();
    } catch (_) {}
  }

  Future<void> _read(NotificationModel n) async {
    if (n.isRead) return;
    try {
      await _service.markRead(n.id);
      await _load();
    } catch (_) {}
  }

  /// Ikon foni и иконка по типу — как в макете.
  (String, Color) _look(String type) {
    if (type == 'order_confirmed' || type == 'request_offer_accepted') {
      return ('check_circle', const Color(0xFFE6F4F1));
    }
    if (type == 'order_completed') return ('star_fill', const Color(0xFFFFF6E0));
    if (type.startsWith('payment') || type.startsWith('balance') || type.startsWith('payout')) {
      return ('card', AppPalette.page);
    }
    if (type.startsWith('order') || type.startsWith('request') || type.startsWith('quick')) {
      return ('orders', AppPalette.brandSubtle);
    }
    return ('bolt_amber', AppPalette.page);
  }

  String _day(DateTime d) {
    final now = DateTime.now();
    final a = DateTime(d.year, d.month, d.day);
    final diff = DateTime(now.year, now.month, now.day).difference(a).inDays;
    if (diff == 0) return 'taxi.today'.tr();
    if (diff == 1) return 'taxi.yesterday'.tr();
    return taxiDate(d);
  }

  Widget _row(NotificationModel n) {
    final (icon, bg) = _look(n.type);
    final t = n.createdAt.toLocal();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => _read(n),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: TaxiIcon(icon, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          n.displayTitle,
                          style: TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w600,
                            color: AppPalette.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hm,
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          height: 16 / 12,
                          color: AppPalette.textSecondary,
                        ),
                      ),
                      if (!n.isRead) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(color: AppPalette.brand, shape: BoxShape.circle),
                        ),
                      ],
                    ],
                  ),
                  if ((n.body ?? '').isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      n.body!,
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 13,
                        height: 18 / 13,
                        color: AppPalette.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// U5: системные уведомления выключены.
  Widget _pushCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(color: Color(0xFFFFF6E0), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const TaxiIcon('menu_bell', size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('taxi.push_off_title'.tr(), style: AppTypography.bodyMedium),
                  const SizedBox(height: 2),
                  Text('taxi.push_off_body'.tr(), style: AppTypography.captionS.copyWith(fontSize: 13, height: 18 / 13)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 36,
                    child: ElevatedButton(
                      onPressed: _enablePush,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        textStyle: AppTypography.bodyMMedium.copyWith(fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                      ),
                      child: Text('taxi.enable'.tr()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final items = _items;
    final groups = <String, List<NotificationModel>>{};
    for (final n in items ?? const <NotificationModel>[]) {
      groups.putIfAbsent(_day(n.createdAt.toLocal()), () => []).add(n);
    }
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(
              title: 'notifications.title'.tr(),
              trailing: (items ?? const []).any((n) => !n.isRead)
                  ? GestureDetector(
                      onTap: _readAll,
                      child: Text(
                        'taxi.read_all'.tr(),
                        style: AppTypography.bodyMMedium.copyWith(color: AppPalette.textBrand),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: items == null
                  ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
                  : items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 24),
                          children: [
                            if (_pushOff) _pushCard(),
                            const SizedBox(height: 40),
                            HaloState(
                              icon: const TaxiIcon('menu_bell', size: 32),
                              title: 'taxi.no_notifications'.tr(),
                              body: 'taxi.no_notifications_body'.tr(),
                            ),
                          ],
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 24),
                            children: [
                              if (_pushOff) ...[_pushCard(), const SizedBox(height: 12)],
                              for (final e in groups.entries) ...[
                                GroupLabel(e.key),
                                const SizedBox(height: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppPalette.surface,
                                    borderRadius: BorderRadius.circular(AppRadius.lg),
                                  ),
                                  child: Column(children: [for (final n in e.value) _row(n)]),
                                ),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
