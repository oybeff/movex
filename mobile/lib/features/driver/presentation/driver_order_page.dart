import '../../support/presentation/support_pages.dart';
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/map_or_placeholder.dart';
import '../../taxi/presentation/pages/taxi_chat_page.dart';
import '../data/driver_api.dart';
import 'driver_ui.dart';
import '../../../core/widgets/h_icon.dart';

/// Исполнение заказа — макет 02 «Buyurtmani bajarish»:
/// D1 в пути («Ketdik» → «Yetib keldim»), D2 ждём клиента, D3 идёт работа,
/// D4 клиент просит продлить, D5 расчёт и «Naqd pulni oldim», D6 готово.
///
/// Состояние берётся с сервера (departed/arrived/started/finished_at)
/// и опрашивается раз в 10 с — клиент мог попросить продление или
/// подтвердить завершение.
class DriverOrderPage extends StatefulWidget {
  const DriverOrderPage({super.key, required this.orderId, this.equipment});

  final int orderId;
  final DriverEquipment? equipment;

  @override
  State<DriverOrderPage> createState() => _DriverOrderPageState();
}

class _DriverOrderPageState extends State<DriverOrderPage> {
  final _api = DriverApi();
  DriverOrder? _o;
  Map<String, dynamic>? _client;
  bool _busy = false;
  bool _summary = false; // D5 открыт
  bool _extendShown = false;
  DriverSettings _settings = DriverSettings(const {});
  // E7: окно «Mijoz kelmadimi?» само открывается, когда ожидание вышло;
  // «Yana 5 daqiqa kutish» откладывает его.
  DateTime? _noShowSnoozeUntil;
  bool _noShowOpen = false;
  // D6: оценка клиента
  int _stars = 0;
  final Set<String> _tags = {};
  bool _rated = false;
  Timer? _poll;
  Timer? _clock;

  @override
  void initState() {
    super.initState();
    _load();
    _api.settings().then((v) {
      if (mounted) setState(() => _settings = v);
    });
    _api.myClientRating(widget.orderId).then((m) {
      if (m == null || !mounted) return;
      setState(() {
        _rated = true;
        _stars = (m['rating'] as int?) ?? 0;
        _tags.addAll((m['tags'] as List? ?? const []).cast<String>());
      });
    }).catchError((_) {});
    _poll = Timer.periodic(const Duration(seconds: 10), (_) => _load());
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      _maybeAskNoShow();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final o = await _api.order(widget.orderId);
      _client ??= await _api.client(o.clientId);
      if (!mounted) return;
      setState(() => _o = o);
      if (o.extendRequested != null && !_extendShown) {
        _extendShown = true;
        _askExtend(o);
      }
      if (o.extendRequested == null) _extendShown = false;
    } catch (_) {}
  }

  Future<void> _act(Future<void> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? get _phone => _client?['phone'] as String?;
  String get _name => (_client?['full_name'] as String?) ?? 'driver.client'.tr();

  Future<void> _call() async {
    final p = _phone;
    if (p == null) return;
    await launchUrl(Uri.parse('tel:+${p.replaceAll(RegExp(r'[^0-9]'), '')}'));
  }

  Future<void> _chat() async {
    try {
      final chatId = await _api.chatFor(widget.orderId);
      if (!mounted) return;
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TaxiChatPage(chatId: chatId, orderId: widget.orderId, name: _name, phone: _phone),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    }
  }

  Future<void> _navigate(DriverOrder o) async {
    final nav = Uri.parse('yandexnavi://build_route_on_map?lat_to=${o.lat}&lon_to=${o.lon}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    await launchUrl(Uri.parse('https://yandex.uz/maps/?rtext=~${o.lat},${o.lon}&rtt=auto'),
        mode: LaunchMode.externalApplication);
  }

  /// D4 «Mijoz vaqtni uzaytirmoqchi».
  Future<void> _askExtend(DriverOrder o) async {
    final n = o.extendRequested!;
    final perHour = o.pricePerHour;
    final extra = perHour == null ? null : perHour * n;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: CircleAvatar(
                radius: 22,
                backgroundColor: DChip.blueBg,
                child: HIcon(Icons.schedule_rounded, color: AppPalette.brand),
              ),
            ),
            const SizedBox(height: 10),
            Text('driver.extend_title'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text('driver.extend_body'.tr(args: [_name, '$n']),
                style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 12),
            DRow('driver.extra_time'.tr(), '+${'driver.hours_n'.tr(args: ['$n'])}'),
            if (extra != null) DRow('driver.extra_sum'.tr(), '+${money(extra)}'),
            if (extra != null) DRow('driver.total'.tr(), money(o.total + extra), bold: true),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: DSecondary('driver.decline'.tr(), tinted: true, onPressed: () => Navigator.of(ctx).pop(false))),
                const SizedBox(width: 10),
                Expanded(child: DPrimary('driver.accept'.tr(), onPressed: () => Navigator.of(ctx).pop(true))),
              ],
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      await _act(() => _api.approveExtend(o.id));
    } else if (ok == false) {
      await _act(() => _api.declineExtend(o.id));
    }
  }

  /// Ожидание клиента вышло (D2 → E7)?
  bool _waitOver(DriverOrder o) =>
      o.arrivedAt != null &&
      o.startedAt == null &&
      DateTime.now().difference(o.arrivedAt!) >= Duration(minutes: _settings.noShowWaitMinutes);

  void _maybeAskNoShow() {
    final o = _o;
    if (o == null || _noShowOpen || _busy || o.status != 'confirmed' || !_waitOver(o)) return;
    final until = _noShowSnoozeUntil;
    if (until != null && DateTime.now().isBefore(until)) return;
    _noShow(o);
  }

  /// E7 «Mijoz kelmadimi?». До конца ожидания — простая отмена без денег.
  Future<void> _noShow(DriverOrder o) async {
    if (_noShowOpen) return;
    _noShowOpen = true;
    final over = _waitOver(o);
    final comp = over ? _settings.compensation : 0.0;
    final mins = '${_settings.noShowWaitMinutes}';
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 22, 18, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(
                child: CircleAvatar(
                  radius: 26,
                  backgroundColor: Color(0xFFFDF3D6),
                  child: HIcon(Icons.person_outline_rounded, color: AppPalette.textPrimary, size: 28),
                ),
              ),
              const SizedBox(height: 12),
              Text('driver.no_show_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h2),
              const SizedBox(height: 8),
              Text(
                over
                    ? (comp > 0
                        ? 'driver.no_show_body_comp'.tr(args: [mins])
                        : 'driver.no_show_body_over'.tr(args: [mins]))
                    : 'driver.no_show_body_early'.tr(args: [mins]),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, height: 1.4, color: AppPalette.textSecondary),
              ),
              if (comp > 0) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: AppPalette.successSubtle,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('driver.compensation_plus'.tr(args: [money(comp)]),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14, color: AppPalette.textSuccess)),
                ),
              ],
              const SizedBox(height: 12),
              DPrimary(comp > 0 ? 'driver.cancel_with_comp'.tr() : 'driver.cancel_order'.tr(),
                  onPressed: () => Navigator.of(ctx).pop('cancel')),
              const SizedBox(height: 8),
              DSecondary(over ? 'driver.wait_5_more'.tr() : 'driver.back'.tr(),
                  tinted: true, onPressed: () => Navigator.of(ctx).pop('wait')),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop('call'),
                child: Text('driver.call_client'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
    _noShowOpen = false;
    if (!mounted) return;
    if (choice == 'cancel') {
      await _act(() => _api.noShow(o.id));
    } else if (choice == 'call') {
      _noShowSnoozeUntil = DateTime.now().add(const Duration(minutes: 5));
      await _call();
    } else if (over) {
      _noShowSnoozeUntil = DateTime.now().add(const Duration(minutes: 5));
    }
  }

  Future<void> _sendRating(DriverOrder o) async {
    if (_stars == 0 || _busy) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _busy = true);
    try {
      await _api.rateClient(o.id, _stars, _tags.toList());
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
        setState(() => _busy = false);
      }
    }
  }

  static const _ratingTags = ['on_time_pay', 'polite', 'exact_address', 'kept_waiting'];

  /// D6 «Mijozni baholang»: звёзды и плашки.
  Widget _ratingBlock() => Column(
        children: [
          Text('driver.rate_client'.tr(), style: AppTypography.bodyMedium),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _stars = i),
                  icon: HIcon(
                    i <= _stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 34,
                    color: i <= _stars ? const Color(0xFFF5B400) : AppPalette.textPlaceholder,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final t in _ratingTags)
                FilterChip(
                  label: Text('driver.rate_tag_$t'.tr()),
                  selected: _tags.contains(t),
                  showCheckmark: false,
                  selectedColor: AppPalette.brandSubtle,
                  side: BorderSide.none,
                  backgroundColor: AppPalette.page,
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: _tags.contains(t) ? AppPalette.textBrand : AppPalette.textPrimary,
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  onSelected: (v) => setState(() => v ? _tags.add(t) : _tags.remove(t)),
                ),
            ],
          ),
          if (_rated) ...[
            const SizedBox(height: 6),
            Text('driver.rated_hint'.tr(), style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
          ],
        ],
      );

  @override
  Widget build(BuildContext context) {
    final o = _o;
    if (o == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (o.status == 'completed' || (o.finishedAt != null && !_summary)) return _done(o);
    if (o.status == 'cancelled' || o.status == 'rejected') return _cancelled(o);
    if (_summary) return _summaryPage(o);
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: Stack(
        children: [
          Positioned.fill(child: _map(o)),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: AppPalette.surface,
              child: IconButton(
                icon: const HIcon(Icons.arrow_back_rounded, color: AppPalette.textPrimary),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 16,
            child: CircleAvatar(
              backgroundColor: AppPalette.surface,
              child: IconButton(
                tooltip: 'dispute.report'.tr(),
                icon: const HIcon(Icons.report_gmailerrorred_rounded, color: AppPalette.textPrimary),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OpenDisputePage(kind: 'equipment', orderId: widget.orderId, role: 'performer'))),
              ),
            ),
          ),
          Align(alignment: Alignment.bottomCenter, child: DSheet(child: _body(o))),
        ],
      ),
    );
  }

  Widget _map(DriverOrder o) {
    final p = Point(latitude: o.lat, longitude: o.lon);
    return MapOrPlaceholder(
      mapBuilder: (_) => YandexMap(
        onMapCreated: (c) => c.moveCamera(CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: 15))),
        mapObjects: [
          CircleMapObject(
            mapId: const MapObjectId('client'),
            circle: Circle(center: p, radius: o.startedAt != null ? 120 : 60),
            fillColor: (o.startedAt != null ? AppPalette.brand : AppPalette.textPrimary).withValues(alpha: .25),
            strokeColor: AppPalette.brand,
            strokeWidth: 2,
          ),
        ],
      ),
    );
  }

  Widget _clientRow() => Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: DChip.warn,
            child: Text(_name.isEmpty ? '?' : _name.characters.first.toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.w700, color: AppPalette.textPrimary)),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(_name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600))),
        ],
      );

  Widget _body(DriverOrder o) {
    // D3 · идёт работа
    if (o.startedAt != null) {
      final elapsed = DateTime.now().difference(o.startedAt!);
      final plan = Duration(hours: o.hours ?? 0);
      final left = plan - elapsed;
      final hh = elapsed.inHours.toString().padLeft(2, '0');
      final mm = (elapsed.inMinutes % 60).toString().padLeft(2, '0');
      final ss = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: DChip('driver.step_2'.tr())),
          const SizedBox(height: 6),
          Text('$hh:$mm:$ss', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: 1)),
          if (plan > Duration.zero) ...[
            Text('driver.ordered_for'.tr(args: [durationText(plan), durationText(elapsed)]),
                style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (elapsed.inSeconds / plan.inSeconds).clamp(0, 1).toDouble(),
                minHeight: 6,
                color: AppPalette.textSuccess,
                backgroundColor: AppPalette.page,
              ),
            ),
          ],
          const SizedBox(height: 10),
          DRow('driver.current_price'.tr(), money(o.total)),
          if (plan > Duration.zero)
            DRow('driver.time_left'.tr(), left.isNegative ? '0' : durationText(left)),
          DRow('driver.client'.tr(), '$_name · ${o.cash ? 'driver.pay_cash'.tr() : 'driver.pay_online'.tr()}'),
          const SizedBox(height: 10),
          Row(children: [
            DAction(icon: Icons.call_rounded, label: 'driver.call'.tr(), onTap: _call),
            const SizedBox(width: 8),
            DAction(icon: Icons.chat_bubble_outline_rounded, label: 'driver.message'.tr(), onTap: _chat),
          ]),
          const SizedBox(height: 12),
          DPrimary('driver.finish'.tr(), onPressed: () => setState(() => _summary = true)),
        ],
      );
    }
    // D2 · на месте, ждём клиента
    if (o.arrivedAt != null) {
      final waited = DateTime.now().difference(o.arrivedAt!);
      final free = const Duration(minutes: 10) - waited;
      final shown = free.isNegative ? waited : free;
      final mm = shown.inMinutes.toString().padLeft(2, '0');
      final ss = (shown.inSeconds % 60).toString().padLeft(2, '0');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(alignment: Alignment.centerLeft, child: DChip('driver.on_site'.tr())),
          const SizedBox(height: 6),
          Text('driver.waiting_client'.tr(), style: AppTypography.h2),
          Text('driver.client_notified'.tr(args: [_name]),
              style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
          const SizedBox(height: 12),
          DCard(
            color: AppPalette.page,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(free.isNegative ? 'driver.waiting'.tr() : 'driver.free_wait'.tr(),
                    style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                Text('$mm:$ss', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                Text('driver.free_wait_hint'.tr(), style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(children: [
            DAction(icon: Icons.call_rounded, label: 'driver.call'.tr(), onTap: _call),
            const SizedBox(width: 8),
            DAction(icon: Icons.chat_bubble_outline_rounded, label: 'driver.message'.tr(), onTap: _chat),
          ]),
          const SizedBox(height: 12),
          DPrimary('driver.start_work'.tr(), busy: _busy, onPressed: () => _act(() => _api.start(o.id))),
          TextButton(
            onPressed: _busy ? null : () => _noShow(o),
            child: Text('driver.no_show'.tr(), style: const TextStyle(color: AppPalette.textDanger)),
          ),
        ],
      );
    }
    // D1 · заказ принят / в пути
    final departed = o.departedAt != null;
    final type = widget.equipment?.type;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppPalette.brand, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text(departed ? 'driver.on_the_way'.tr() : 'driver.order_accepted'.tr(), style: AppTypography.h2),
          ],
        ),
        Text(orderTitle(type, o.tariff) + (o.hours != null ? ' · ${'driver.hours_n'.tr(args: ['${o.hours}'])}' : ''),
            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
        if (o.delayMinutes != null)
          Text('driver.delay_reported'.tr(args: ['${o.delayMinutes}']),
              style: const TextStyle(fontSize: 13, color: AppPalette.textDanger)),
        const SizedBox(height: 12),
        _clientRow(),
        const SizedBox(height: 10),
        Row(children: [
          DAction(icon: Icons.call_rounded, label: 'driver.call'.tr(), onTap: _call),
          const SizedBox(width: 8),
          DAction(icon: Icons.chat_bubble_outline_rounded, label: 'driver.message'.tr(), onTap: _chat),
          const SizedBox(width: 8),
          DAction(icon: Icons.navigation_rounded, label: 'driver.navigator'.tr(), onTap: () => _navigate(o), accent: true),
        ]),
        const SizedBox(height: 10),
        DAddress(o.address),
        const SizedBox(height: 12),
        departed
            ? DPrimary('driver.arrived'.tr(), busy: _busy, onPressed: () => _act(() => _api.arrive(o.id)))
            : DPrimary('driver.depart'.tr(), busy: _busy, onPressed: () => _act(() => _api.depart(o.id))),
        TextButton(
          onPressed: _busy ? null : () => _askDelay(o),
          child: Text('driver.late'.tr()),
        ),
      ],
    );
  }

  Future<void> _askDelay(DriverOrder o) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DSheet(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('driver.delay_title'.tr(), style: AppTypography.h2),
            const SizedBox(height: 8),
            for (final m in const [10, 20, 30, 60])
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('driver.delay_n'.tr(args: ['$m'])),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    await _act(() => _api.delay(o.id, minutes));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('driver.delay_sent'.tr())));
  }

  /// D5 · «Ishni yakunlash — hisob».
  Widget _summaryPage(DriverOrder o) => Scaffold(
        backgroundColor: AppPalette.page,
        appBar: AppBar(
          backgroundColor: AppPalette.page,
          title: Text('driver.finish'.tr()),
          leading: IconButton(icon: const HIcon(Icons.arrow_back_rounded), onPressed: () => setState(() => _summary = false)),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('driver.bill'.tr(), style: AppTypography.h3),
                  const SizedBox(height: 6),
                  if (o.tariff != null) DRow('driver.tariff'.tr(), tariffName(o.tariff)),
                  if (o.hours != null) DRow('driver.work_time'.tr(), 'driver.hours_n'.tr(args: ['${o.hours}'])),
                  DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                  const Divider(),
                  DRow('driver.total'.tr(), money(o.total), bold: true),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (o.cash)
              DCard(
                color: const Color(0xFFFDF3D6),
                child: Row(
                  children: [
                    const HIcon(Icons.payments_outlined),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('driver.take_cash'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text('driver.take_cash_hint'.tr(args: [money(o.total)]),
                              style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DPrimary(
              o.cash ? 'driver.cash_taken_finish'.tr() : 'driver.finish'.tr(),
              busy: _busy,
              onPressed: () async {
                await _act(() => _api.finish(o.id));
                if (mounted) setState(() => _summary = false);
              },
            ),
          ),
        ),
      );

  /// D6 · «Ish yakunlandi» + «Mijozni baholang». Прокручивается: на
  /// маленьком экране звёзды и плашки не влезают вместе с суммой.
  Widget _done(DriverOrder o) => Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
                  children: [
                    const Center(
                      child: CircleAvatar(
                        radius: 36,
                        backgroundColor: AppPalette.textSuccess,
                        child: HIcon(Icons.check_rounded, color: Colors.white, size: 44),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('driver.work_done'.tr(), textAlign: TextAlign.center, style: AppTypography.h1),
                    Text(_name, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.textSecondary)),
                    const SizedBox(height: 16),
                    DCard(
                      color: AppPalette.page,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('driver.your_earning'.tr(),
                              style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                          Text('+${money(o.earning)}',
                              style: const TextStyle(
                                  fontSize: 26, fontWeight: FontWeight.w700, color: AppPalette.textSuccess)),
                          Text(
                            // Деньги двигает подтверждение клиента (или авто через 10 мин):
                            // до него комиссия ещё не списана — говорим в будущем времени
                            o.status != 'completed'
                                ? 'driver.commission_pending'.tr(args: [money(o.commission)])
                                : o.cash
                                    ? 'driver.commission_from_balance'.tr(args: [money(o.commission)])
                                    : 'driver.commission_held'.tr(args: [money(o.commission)]),
                            style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    if (o.status != 'completed') ...[
                      const SizedBox(height: 12),
                      Text('driver.wait_client'.tr(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                    ],
                    const SizedBox(height: 24),
                    _ratingBlock(),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DPrimary('driver.ready'.tr(), busy: _busy, onPressed: () => _sendRating(o)),
              ),
            ],
          ),
        ),
      );

  /// E1 «Mijoz buyurtmani bekor qildi» (и отмена владельцем, в т.ч. E7).
  /// Компенсация показывается, только если сервер её действительно провёл.
  Widget _cancelled(DriverOrder o) {
    final byOwner = o.cancelledBy == 'owner';
    final noShow = o.cancelReason == 'client_no_show';
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              DCard(
                padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(
                      child: CircleAvatar(
                        radius: 28,
                        backgroundColor: DChip.redBg,
                        child: HIcon(Icons.close_rounded, color: AppPalette.textDanger, size: 32),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      noShow
                          ? 'driver.no_show_done'.tr()
                          : (byOwner ? 'driver.you_cancelled'.tr() : 'driver.client_cancelled'.tr()),
                      textAlign: TextAlign.center,
                      style: AppTypography.h2,
                    ),
                    if (o.compensation > 0) ...[
                      const SizedBox(height: 8),
                      Text(
                        byOwner
                            ? 'driver.comp_added_noshow'.tr()
                            : 'driver.comp_added_cancel'.tr(args: [_name]),
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14, height: 1.4, color: AppPalette.textSecondary),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: AppPalette.successSubtle,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('driver.compensation_plus'.tr(args: [money(o.compensation)]),
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 14, color: AppPalette.textSuccess)),
                      ),
                    ],
                    const SizedBox(height: 16),
                    DPrimary('driver.wait_new'.tr(), onPressed: () => Navigator.of(context).pop()),
                  ],
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
