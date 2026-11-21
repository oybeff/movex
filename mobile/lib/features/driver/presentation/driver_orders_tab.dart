import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/constants/equipment_types.dart';
import '../../../core/models/equipment_request_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/equipment_request_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/map_or_placeholder.dart';
import '../../owner_home/presentation/pages/my_equipment_page.dart';
import '../../taxi/data/taxi_geo.dart';
import '../data/driver_api.dart';
import 'driver_equipment_step.dart';
import 'driver_incoming_page.dart';
import 'driver_order_page.dart';
import 'driver_ui.dart';
import 'driver_verification_page.dart';

/// «Asosiy» приложения водителя — макет 01: H1 «Siz oflaynsiz»,
/// H2 «Buyurtmalar kutilmoqda», живой заказ — карточкой «Faol buyurtma».
///
/// Push ещё не подключён (нет проекта Firebase), поэтому, пока водитель
/// онлайн и приложение открыто, сервер опрашивается раз в 10 секунд.
/// Онлайн живёт только на телефоне: сервер про него не знает.
class DriverOrdersTab extends StatefulWidget {
  const DriverOrdersTab({super.key});

  @override
  State<DriverOrdersTab> createState() => _DriverOrdersTabState();
}

class _DriverOrdersTabState extends State<DriverOrdersTab> with WidgetsBindingObserver {
  static const _pollEvery = Duration(seconds: 10);
  static const _onlineKey = 'driver_online';
  static const _onlineSinceKey = 'driver_online_since';

  final _api = DriverApi();
  final _requests = EquipmentRequestService();
  final Set<int> _seen = {};

  YandexMapController? _map;
  TaxiPlace? _here;
  bool _online = false;
  DateTime? _onlineSince;
  bool _loaded = false;
  bool _showingIncoming = false;
  UserModel? _me;
  Timer? _poll;

  List<QuickIncomingModel> _incoming = const [];
  List<DriverOrder> _orders = const [];
  Map<int, DriverEquipment> _equipment = const {};
  DriverVerification? _verification;

  DriverOrder? get _active {
    // Работа закончена и ждёт только подтверждения клиента — водитель
    // уже свободен, такой заказ не держит его и не прячет новые
    final live = _orders.where((o) => o.active && !o.scheduled && o.finishedAt == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return live.isEmpty ? null : live.first;
  }

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
    if (state == AppLifecycleState.resumed) {
      _restartPolling();
    } else {
      _poll?.cancel();
    }
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _online = prefs.getBool(_onlineKey) ?? false;
    final since = prefs.getString(_onlineSinceKey);
    _onlineSince = since == null ? null : DateTime.tryParse(since);
    try {
      _me = await AuthService().getCurrentUser();
    } catch (_) {}
    try {
      _equipment = await _api.myEquipment();
    } catch (_) {}
    await _loadVerification();
    // Проверка не пройдена — водитель офлайн, что бы ни сохранилось раньше
    if (_verification != null && !_verification!.approved && _online) await _setOnline(false);
    if (mounted) setState(() {});
    _restartPolling();
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _here = here);
    _moveTo(here.point);
  }

  Future<void> _loadVerification() async {
    try {
      _verification = await _api.verification();
    } catch (_) {}
  }

  /// Регистрация водителя по макету 00: нет техники — R4, затем документы.
  Future<void> _startVerification() async {
    if (_equipment.isEmpty) {
      final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const DriverEquipmentStep()),
      );
      if (added != true || !mounted) return;
      try {
        _equipment = await _api.myEquipment();
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverVerificationPage()));
    await _loadVerification();
    if (mounted) setState(() {});
  }

  void _restartPolling() {
    _poll?.cancel();
    _refresh();
    _poll = Timer.periodic(_pollEvery, (_) => _refresh());
  }

  Future<void> _setOnline(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_onlineKey, v);
    if (v) {
      _onlineSince = DateTime.now();
      await prefs.setString(_onlineSinceKey, _onlineSince!.toIso8601String());
    } else {
      _onlineSince = null;
      await prefs.remove(_onlineSinceKey);
    }
    setState(() => _online = v);
    _restartPolling();
  }

  Future<void> _refresh() async {
    final me = _me?.id ?? await AuthService().getUserId();
    if (me == null) return;
    try {
      final orders = await _api.myOrders(me);
      // Ждём решения админа — подхватываем его без перезапуска приложения
      if (!(_verification?.approved ?? true)) await _loadVerification();
      List<QuickIncomingModel> incoming = const [];
      final busy = orders.any((o) => o.active && !o.scheduled && o.finishedAt == null);
      if (_online && !busy) incoming = await _requests.quickIncoming();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _incoming = incoming;
        _loaded = true;
      });
      _maybeShowIncoming();
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

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
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => DriverIncomingPage(order: o)),
    );
    _showingIncoming = false;
    await _refresh();
    if (accepted == true && mounted) {
      final a = _active;
      if (a != null) await _openOrder(a);
    }
  }

  Future<void> _openOrder(DriverOrder o) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DriverOrderPage(orderId: o.id, equipment: _equipment[o.equipmentId]),
    ));
    await _refresh();
  }

  void _moveTo(Point p) {
    _map?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: p, zoom: 14)),
      animation: const MapAnimation(duration: .4),
    );
  }

  Future<void> _recenter() async {
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _here = here);
    _moveTo(here.point);
  }

  // --------------------------------------------------------- цифры дня

  List<DriverOrder> get _todayDone {
    final now = DateTime.now();
    final day = DateTime(now.year, now.month, now.day);
    return _orders.where((o) => o.status == 'completed' && !o.updatedAt.isBefore(day)).toList();
  }

  double get _todayEarning => _todayDone.fold(0, (s, o) => s + o.earning);

  String get _initials {
    final parts = (_me?.fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapOrPlaceholder(
              hintKey: 'taxi.map_web_hint',
              mapBuilder: (_) => YandexMap(
                mapObjects: _mapObjects,
                onMapCreated: (c) {
                  _map = c;
                  _moveTo((_here ?? TaxiGeo.tashkent).point);
                },
              ),
            ),
          ),
          Positioned(
            top: top + 8,
            left: 16,
            right: 16,
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppPalette.brand,
                  child: Text(_initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                _OnlinePill(online: _online, onTap: () => _setOnline(!_online)),
                const Spacer(),
                _Round(icon: Icons.notifications_none_rounded, onTap: () => context.push('/notifications')),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: 16, bottom: 12),
                  child: _Round(icon: Icons.my_location_rounded, onTap: _recenter),
                ),
                DSheet(child: _sheet()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MapObject> get _mapObjects {
    final out = <MapObject>[];
    final here = _here;
    if (here != null) {
      if (_online) {
        out.add(CircleMapObject(
          mapId: const MapObjectId('halo'),
          circle: Circle(center: here.point, radius: 300),
          strokeWidth: 0,
          strokeColor: Colors.transparent,
          fillColor: AppPalette.brand.withValues(alpha: .12),
        ));
      }
      out.add(CircleMapObject(
        mapId: const MapObjectId('me'),
        circle: Circle(center: here.point, radius: 30),
        strokeColor: Colors.white,
        strokeWidth: 3,
        fillColor: AppPalette.brand,
        zIndex: 2,
      ));
    }
    return out;
  }

  Widget _sheet() {
    if (!_loaded) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    final a = _active;
    if (a != null) return _activeCard(a);
    return _online ? _onlineSheet() : _offlineSheet();
  }

  /// H1 · «Siz oflaynsiz».
  Widget _offlineSheet() {
    final eq = _equipment.values.isEmpty ? null : _equipment.values.first;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('driver.offline_title'.tr(), style: AppTypography.h2),
        const SizedBox(height: 2),
        Text('driver.offline_body'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
        const SizedBox(height: 12),
        Material(
          color: AppPalette.page,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              if (eq == null) return _startVerification();
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyEquipmentPage()));
              try {
                _equipment = await _api.myEquipment();
                if (mounted) setState(() {});
              } catch (_) {}
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: DChip.blueBg, borderRadius: BorderRadius.circular(10)),
                    child: const Icon(Icons.construction_rounded, color: AppPalette.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          eq == null ? 'driver.add_equipment'.tr() : [eq.model, EquipmentTypes.label(eq.type)].whereType<String>().join(' '),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        if (eq?.plate != null) ...[
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              border: Border.all(color: AppPalette.textPrimary),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(eq!.plate!, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          DStat(money(_todayEarning), 'driver.today'.tr()),
          const SizedBox(width: 8),
          DStat('${_todayDone.length}', 'driver.orders_count'.tr()),
          const SizedBox(width: 8),
          DStat('${_orders.where((o) => o.scheduled).length}', 'driver.scheduled_short'.tr()),
        ]),
        const SizedBox(height: 12),
        if (_verification != null && !_verification!.approved) ...[
          _verificationCard(_verification!),
          const SizedBox(height: 12),
        ],
        DPrimary(
          'driver.go_online'.tr(),
          onPressed: eq == null || !(_verification?.approved ?? false) ? null : () => _setOnline(true),
        ),
      ],
    );
  }

  /// E5 «Hujjatlaringiz tekshirilmoqda» и его соседи: что мешает выйти на линию.
  Widget _verificationCard(DriverVerification v) {
    final (String title, String body, String? action) = switch (v.status) {
      'pending' => ('driver.e5_pending_title'.tr(), 'driver.e5_pending_body'.tr(), null),
      'rejected' => ('driver.e5_rejected_title'.tr(), 'driver.e5_rejected_body'.tr(), 'driver.reupload'.tr()),
      _ => (
          _equipment.isEmpty ? 'driver.e5_start_title'.tr() : 'driver.e5_docs_title'.tr(),
          'driver.e5_docs_body'.tr(),
          _equipment.isEmpty ? 'driver.add_equipment'.tr() : 'driver.upload_docs'.tr(),
        ),
    };
    final red = v.status == 'rejected';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: red ? DChip.redBg : DChip.blueBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(red ? Icons.error_outline_rounded : Icons.verified_user_outlined,
              color: red ? AppPalette.textDanger : AppPalette.brand),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(body, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
          if (action != null)
            TextButton(onPressed: _startVerification, child: Text(action))
          else
            TextButton(onPressed: _startVerification, child: Text('driver.open'.tr())),
        ],
      ),
    );
  }

  /// H2 · «Buyurtmalar kutilmoqda».
  Widget _onlineSheet() {
    final since = _onlineSince;
    final online = since == null ? '—' : durationText(DateTime.now().difference(since));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppPalette.textSuccess, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Text('driver.waiting_orders'.tr(), style: AppTypography.h2),
          ],
        ),
        const SizedBox(height: 2),
        Text('driver.nearby_n'.tr(args: ['${_incoming.length}']),
            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
        const SizedBox(height: 12),
        Row(children: [
          DStat(money(_todayEarning), 'driver.today'.tr()),
          const SizedBox(width: 8),
          DStat('${_todayDone.length}', 'driver.orders_count'.tr()),
          const SizedBox(width: 8),
          DStat(online, 'driver.online'.tr()),
        ]),
        for (final i in _incoming.take(3)) ...[
          const SizedBox(height: 8),
          Material(
            color: DChip.blueBg,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openIncoming(i),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.bolt_rounded, color: AppPalette.brand, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('${orderTitle(i.equipmentType, i.tariff)} · ${i.deliveryAddress ?? ''}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, color: AppPalette.brand, fontWeight: FontWeight.w500)),
                    ),
                    Text(money(i.youReceive),
                        style: const TextStyle(fontSize: 13, color: AppPalette.brand, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 12),
        DSecondary('driver.stop_work'.tr(), onPressed: () => _setOnline(false)),
      ],
    );
  }

  /// Живой заказ — карточка, по тапу экран исполнения (D1–D5).
  Widget _activeCard(DriverOrder o) {
    final step = o.finishedAt != null
        ? 3
        : o.startedAt != null
            ? 2
            : o.departedAt != null
                ? 1
                : 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text('driver.active_order'.tr(), style: AppTypography.h2)),
            DChip('driver.step_$step'.tr()),
          ],
        ),
        const SizedBox(height: 4),
        Text(orderTitle(_equipment[o.equipmentId]?.type, o.tariff),
            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
        const SizedBox(height: 10),
        DAddress(o.address),
        const SizedBox(height: 8),
        DRow('driver.you_get_short'.tr(), money(o.earning), valueColor: AppPalette.textSuccess),
        const SizedBox(height: 10),
        DPrimary('driver.open_order'.tr(), onPressed: () => _openOrder(o)),
      ],
    );
  }
}

class _OnlinePill extends StatelessWidget {
  const _OnlinePill({required this.online, required this.onTap});

  final bool online;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppPalette.surface,
        elevation: 2,
        shadowColor: Colors.black26,
        borderRadius: BorderRadius.circular(99),
        child: InkWell(
          borderRadius: BorderRadius.circular(99),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: online ? AppPalette.textSuccess : AppPalette.textPlaceholder,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(online ? 'driver.online'.tr() : 'driver.offline'.tr(),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      );
}

class _Round extends StatelessWidget {
  const _Round({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppPalette.surface,
        shape: const CircleBorder(),
        elevation: 2,
        shadowColor: Colors.black26,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 40, height: 40, child: Icon(icon, size: 22, color: AppPalette.iconPrimary)),
        ),
      );
}
