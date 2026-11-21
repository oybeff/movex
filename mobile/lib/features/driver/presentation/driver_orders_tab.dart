import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/constants/equipment_types.dart';
import '../../../core/models/equipment_request_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/equipment_request_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/error_handler.dart';
import '../../../core/widgets/map_or_placeholder.dart';
import '../../requests/presentation/pages/incoming_order_page.dart';
import '../../taxi/data/taxi_geo.dart';
import '../../taxi/presentation/widgets/taxi_ui.dart' show formatSum;
import '../data/driver_api.dart';

/// «Buyurtmalar» приложения водителя (макет Шерзатбека, 21.11.2026):
/// карта, переключатель «Onlayn», входящие заказы и живой заказ с
/// кнопками по шагам — «Yo'lga chiqdim» → «Ishni boshladim» → «Yakunlash».
///
/// Push ещё не подключён (нет проекта Firebase), поэтому, пока водитель
/// онлайн и приложение открыто, сервер опрашивается раз в 10 секунд.
/// Оффлайн — не опрашиваем вовсе и новые заказы не показываем.
class DriverOrdersTab extends StatefulWidget {
  const DriverOrdersTab({super.key});

  @override
  State<DriverOrdersTab> createState() => _DriverOrdersTabState();
}

class _DriverOrdersTabState extends State<DriverOrdersTab> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 10);
  static const _onlineKey = 'driver_online';

  final _api = DriverApi();
  final _requests = EquipmentRequestService();
  final Set<int> _seen = {};

  YandexMapController? _map;
  TaxiPlace? _here;
  bool _online = false;
  bool _loaded = false;
  bool _busy = false;
  bool _showingIncoming = false;
  int? _myId;
  Timer? _poll;

  List<QuickIncomingModel> _incoming = const [];
  DriverOrder? _active;
  Map<String, dynamic>? _client;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // В фоне не опрашиваем: батарея и трафик
    if (state == AppLifecycleState.resumed) {
      _restartPolling();
    } else {
      _poll?.cancel();
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _online = prefs.getBool(_onlineKey) ?? false;
    _myId = await AuthService().getUserId();
    if (mounted) setState(() {});
    _restartPolling();
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _here = here);
    _moveTo(here.point);
  }

  void _restartPolling() {
    _poll?.cancel();
    _refresh();
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  Future<void> _setOnline(bool v) async {
    setState(() => _online = v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onlineKey, v);
    _restartPolling();
  }

  Future<void> _refresh() async {
    final myId = _myId;
    if (myId == null) return;
    try {
      final orders = await _api.myOrders(myId);
      final active = orders.where((o) => o.active).toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      final current = active.isEmpty ? null : active.first;
      if (current != null && current.clientId != (_active?.clientId ?? -1)) {
        _client = await _api.client(current.clientId);
      }
      List<QuickIncomingModel> incoming = const [];
      // Новые заказы — только онлайн и только когда руки свободны
      if (_online && current == null) incoming = await _requests.quickIncoming();
      if (!mounted) return;
      setState(() {
        _active = current;
        _incoming = incoming;
        _loaded = true;
      });
      _maybeShowIncoming();
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  /// Новый заказ открывается сам, как у такси: «Yangi buyurtma!».
  Future<void> _maybeShowIncoming() async {
    if (_showingIncoming || !_online || _active != null) return;
    final fresh = _incoming.where((o) => !_seen.contains(o.id)).toList();
    if (fresh.isEmpty) return;
    await _openIncoming(fresh.first);
  }

  Future<void> _openIncoming(QuickIncomingModel o) async {
    _seen.add(o.id);
    _showingIncoming = true;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => IncomingOrderPage(order: o)),
    );
    _showingIncoming = false;
    if (accepted == true) await _refresh();
  }

  Future<void> _recenter() async {
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _here = here);
    _moveTo(here.point);
  }

  void _moveTo(Point p) {
    _map?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: 14)),
      animation: const MapAnimation(duration: .4),
    );
  }

  Future<void> _act(Future<void> Function() call, {String? done}) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await call();
      if (done != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
      }
      await _refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// «Manzilga yo'l olish» — Яндекс Навигатор, нет его — Яндекс Карты в браузере.
  Future<void> _navigate(DriverOrder o) async {
    final nav = Uri.parse('yandexnavi://build_route_on_map?lat_to=${o.lat}&lon_to=${o.lon}');
    if (await canLaunchUrl(nav)) {
      await launchUrl(nav);
      return;
    }
    await launchUrl(
      Uri.parse('https://yandex.uz/maps/?rtext=~${o.lat},${o.lon}&rtt=auto'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _call() async {
    final phone = _client?['phone'] as String?;
    if (phone == null || phone.isEmpty) return;
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    await launchUrl(Uri.parse('tel:+$digits'));
  }

  Future<void> _askDelay(DriverOrder o) async {
    final minutes = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Text('driver.delay_title'.tr(), style: AppTypography.h3),
            ),
            for (final m in const [10, 20, 30, 60])
              ListTile(
                title: Text('driver.delay_n'.tr(args: ['$m'])),
                onTap: () => Navigator.of(ctx).pop(m),
              ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
    if (minutes == null) return;
    await _act(() => _api.delay(o.id, minutes), done: 'driver.delay_sent'.tr());
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Stack(
      children: [
        Positioned.fill(
          child: MapOrPlaceholder(
            hintKey: 'taxi.map_web_hint',
            mapBuilder: (_) => YandexMap(
              mapObjects: _mapObjects,
              onMapCreated: (c) {
                _map = c;
                // Пока геолокация не ответила — Ташкент, а не карта мира
                _moveTo((_here ?? TaxiGeo.tashkent).point);
              },
            ),
          ),
        ),
        Positioned(
          top: top + AppSpacing.md,
          left: AppSpacing.lg,
          right: AppSpacing.lg,
          child: Row(
            children: [
              const Spacer(),
              _OnlineSwitch(online: _online, onChanged: _setOnline),
              const Spacer(),
              _RoundButton(
                icon: Icons.notifications_none_rounded,
                onTap: () => context.push('/notifications'),
              ),
            ],
          ),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          left: AppSpacing.lg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _RoundButton(icon: Icons.my_location_rounded, onTap: _recenter),
              const SizedBox(height: AppSpacing.md),
              _panel(),
            ],
          ),
        ),
      ],
    );
  }

  List<MapObject> get _mapObjects {
    final out = <MapObject>[];
    final here = _here;
    if (here != null) {
      out.add(CircleMapObject(
        mapId: const MapObjectId('me'),
        circle: Circle(center: here.point, radius: 40),
        strokeColor: Colors.white,
        strokeWidth: 3,
        fillColor: AppPalette.brand,
        zIndex: 2,
      ));
    }
    final o = _active;
    if (o != null) {
      out.add(CircleMapObject(
        mapId: const MapObjectId('client'),
        circle: Circle(center: Point(latitude: o.lat, longitude: o.lon), radius: 60),
        strokeColor: Colors.white,
        strokeWidth: 3,
        fillColor: AppPalette.textDanger,
        zIndex: 2,
      ));
      if (here != null) {
        out.add(PolylineMapObject(
          mapId: const MapObjectId('line'),
          polyline: Polyline(points: [here.point, Point(latitude: o.lat, longitude: o.lon)]),
          strokeColor: AppPalette.brand,
          strokeWidth: 3,
          dashLength: 6,
          gapLength: 5,
        ));
      }
    }
    return out;
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.floating,
        ),
        child: child,
      );

  Widget _panel() {
    if (!_loaded) return _card(const Center(child: CircularProgressIndicator()));
    final o = _active;
    if (o != null) return _card(_activeOrder(o));
    if (!_online) {
      return _card(Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('driver.offline_title'.tr(), style: AppTypography.h3),
          const SizedBox(height: 4),
          Text('driver.offline_body'.tr(), style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(onPressed: () => _setOnline(true), child: Text('driver.go_online'.tr())),
        ],
      ));
    }
    return _card(Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: AppPalette.accentPressed),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text('driver.new_orders'.tr(), style: AppTypography.h3)),
            Text('(${_incoming.length})', style: AppTypography.h3),
          ],
        ),
        if (_incoming.isEmpty) ...[
          const SizedBox(height: 6),
          Text('driver.waiting_orders'.tr(), style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
        ],
        for (final i in _incoming.take(3))
          InkWell(
            onTap: () => _openIncoming(i),
            child: Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(EquipmentTypes.label(i.equipmentType), style: AppTypography.bodyMedium),
                        Text(i.deliveryAddress ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
                      ],
                    ),
                  ),
                  Text("${formatSum(i.youReceive)} ${'common.currency'.tr()}",
                      style: AppTypography.bodyMedium.copyWith(color: AppPalette.textSuccess)),
                ],
              ),
            ),
          ),
      ],
    ));
  }

  Widget _activeOrder(DriverOrder o) {
    final step = o.finishedAt != null
        ? 3
        : o.startedAt != null
            ? 2
            : o.departedAt != null
                ? 1
                : 0;
    final name = _client?['full_name'] as String?;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('driver.order_n'.tr(args: ['${o.id}']), style: AppTypography.h3)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppPalette.successSubtle, borderRadius: BorderRadius.circular(99)),
              child: Text('driver.step_$step'.tr(),
                  style: AppTypography.bodyM.copyWith(color: AppPalette.textSuccess, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const Icon(Icons.place_rounded, color: AppPalette.textDanger, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(o.address ?? '—', maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTypography.bodyMedium),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                "${formatSum(o.earning)} ${'common.currency'.tr()} · ${o.cash ? 'driver.pay_cash'.tr() : 'driver.pay_online'.tr()}",
                style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary),
              ),
            ),
            if (name != null) Text(name, style: AppTypography.bodyM),
            if (_client?['phone'] != null)
              IconButton(
                onPressed: _call,
                icon: const Icon(Icons.call_rounded, color: AppPalette.brand),
                tooltip: 'driver.call'.tr(),
              ),
          ],
        ),
        if (o.extendRequested != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppPalette.accentSubtle, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('driver.extend_asked'.tr(args: ['${o.extendRequested}'])),
                Row(
                  children: [
                    TextButton(
                      onPressed: _busy ? null : () => _act(() => _api.declineExtend(o.id)),
                      child: Text('driver.decline'.tr()),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _busy ? null : () => _act(() => _api.approveExtend(o.id)),
                      child: Text('driver.approve'.tr()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        if (step < 2)
          OutlinedButton.icon(
            onPressed: () => _navigate(o),
            icon: const Icon(Icons.navigation_rounded),
            label: Text('driver.navigate'.tr()),
          ),
        const SizedBox(height: AppSpacing.sm),
        if (step == 0)
          ElevatedButton(
            onPressed: _busy ? null : () => _act(() => _api.depart(o.id)),
            child: Text('driver.depart'.tr()),
          )
        else if (step == 1)
          ElevatedButton(
            onPressed: _busy ? null : () => _act(() => _api.start(o.id)),
            child: Text('driver.start'.tr()),
          )
        else if (step == 2)
          ElevatedButton(
            onPressed: _busy ? null : () => _confirmFinish(o),
            child: Text('driver.finish'.tr()),
          )
        else
          Text('driver.wait_client'.tr(),
              textAlign: TextAlign.center, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
        if (step < 2)
          TextButton(
            onPressed: _busy ? null : () => _askDelay(o),
            child: Text('driver.late'.tr()),
          ),
      ],
    );
  }

  /// Наличные: «Yakunlash» = «деньги получил» — после него снимается
  /// залог клиента и списывается комиссия. Поэтому спрашиваем явно.
  Future<void> _confirmFinish(DriverOrder o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('driver.finish_title'.tr()),
        content: Text(o.cash
            ? 'driver.finish_cash'.tr(args: [formatSum(o.total)])
            : 'driver.finish_online'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('driver.back'.tr())),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('driver.finish'.tr())),
        ],
      ),
    );
    if (ok == true) await _act(() => _api.finish(o.id), done: 'driver.finished'.tr());
  }
}

class _OnlineSwitch extends StatelessWidget {
  const _OnlineSwitch({required this.online, required this.onChanged});

  final bool online;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = online ? AppPalette.textSuccess : AppPalette.textSecondary;
    return Material(
      color: AppPalette.surface,
      elevation: 3,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(99),
      child: InkWell(
        borderRadius: BorderRadius.circular(99),
        onTap: () => onChanged(!online),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(online ? 'driver.online'.tr() : 'driver.offline'.tr(),
                  style: AppTypography.bodyMedium.copyWith(color: color, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Switch(value: online, onChanged: onChanged, activeTrackColor: AppPalette.textSuccess),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppPalette.surface,
        shape: const CircleBorder(),
        elevation: 3,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Icon(icon, color: AppPalette.iconPrimary)),
        ),
      );
}
