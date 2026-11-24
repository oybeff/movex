import 'dart:async';

import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/constants/equipment_types.dart';
import '../../../core/models/equipment_request_model.dart';
import '../../../core/models/user_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/equipment_request_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/app_logo.dart';
import '../../../core/widgets/map_or_placeholder.dart';
import '../../owner_home/presentation/pages/my_equipment_page.dart';
import '../../taxi/data/taxi_geo.dart';
import '../data/delivery_api.dart';
import '../data/driver_api.dart';
import 'delivery_incoming_page.dart';
import '../../freight/data/freight_api.dart';
import 'freight_driver_pages.dart';
import 'delivery_order_page.dart';
import 'delivery_setup_page.dart';
import 'driver_equipment_step.dart';
import 'driver_incoming_page.dart';
import 'driver_order_page.dart';
import 'driver_ui.dart';
import 'driver_verification_page.dart';
import '../../../core/widgets/h_icon.dart';

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
  // E2: пропуски подряд и до когда водитель снят с линии за них
  static const _missedKey = 'driver_missed_in_row';
  static const _pausedUntilKey = 'driver_paused_until';
  static const _maxMissed = 3;
  static const _pause = Duration(minutes: 15);

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
  int _missed = 0;
  DateTime? _pausedUntil;
  // E3: последний опрос сервера не дошёл — сети нет
  bool _netDown = false;

  // Доставка стройматериалов (23.11.2026): свой профиль машины, свои
  // входящие и активная поездка — рядом с заказами техники.
  final _delivery = DeliveryApi();
  DeliveryProfile? _dProfile;
  List<DeliveryIncoming> _dIncoming = const [];
  List<DeliveryOrder> _dOrders = const [];
  final Set<int> _dSeen = {};

  // «Yuk tashish» (24.11.2026): те же водители, свои заказы А→Б.
  final _freight = FreightApi();
  List<FreightIncoming> _fIncoming = const [];
  List<FreightOrder> _fOrders = const [];
  final Set<int> _fSeen = {};

  FreightOrder? get _activeFreight {
    final live = _fOrders.where((o) => o.busyForDriver).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return live.isEmpty ? null : live.first;
  }

  bool get _isDeliveryDriver => _dProfile?.registered ?? false;

  DeliveryOrder? get _activeDelivery {
    final live = _dOrders.where((o) => o.active).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return live.isEmpty ? null : live.first;
  }

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
    _missed = prefs.getInt(_missedKey) ?? 0;
    final paused = prefs.getString(_pausedUntilKey);
    _pausedUntil = paused == null ? null : DateTime.tryParse(paused);
    final since = prefs.getString(_onlineSinceKey);
    _onlineSince = since == null ? null : DateTime.tryParse(since);
    try {
      _me = await AuthService().getCurrentUser();
    } catch (_) {}
    try {
      _equipment = await _api.myEquipment();
    } catch (_) {}
    await _loadDeliveryProfile();
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

  Future<void> _loadDeliveryProfile() async {
    try {
      _dProfile = await _delivery.profile();
    } catch (_) {}
  }

  /// «Yuk mashinam»: машина и что возит. После сохранения — сразу в опрос.
  Future<void> _openDeliverySetup() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const DeliverySetupPage()),
    );
    if (saved != true) return;
    await _loadDeliveryProfile();
    if (mounted) setState(() {});
    _refresh();
  }

  /// Нет ни техники, ни грузовика — спросить, с чего начать.
  Future<String?> _askWhatYouHave() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('driver.what_you_have'.tr(), style: AppTypography.h2),
              const SizedBox(height: 12),
              ListTile(
                leading: const HIcon(Icons.construction_rounded, color: AppPalette.brand),
                title: Text('driver.have_equipment'.tr()),
                subtitle: Text('driver.have_equipment_hint'.tr()),
                onTap: () => Navigator.of(ctx).pop('equipment'),
              ),
              ListTile(
                leading: const HIcon(Icons.local_shipping_outlined, color: AppPalette.brand),
                title: Text('driver.have_truck'.tr()),
                subtitle: Text('driver.have_truck_hint'.tr()),
                onTap: () => Navigator.of(ctx).pop('truck'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadVerification() async {
    try {
      _verification = await _api.verification();
    } catch (_) {}
  }

  /// Регистрация водителя по макету 00: нет техники — R4, затем документы.
  Future<void> _startVerification() async {
    if (_equipment.isEmpty && !_isDeliveryDriver) {
      final what = await _askWhatYouHave();
      if (what == null || !mounted) return;
      if (what == 'truck') {
        await _openDeliverySetup();
        if (!_isDeliveryDriver || !mounted) return;
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const DriverVerificationPage()));
        await _loadVerification();
        if (mounted) setState(() {});
        return;
      }
    }
    if (_equipment.isEmpty && !_isDeliveryDriver) {
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
    if (!v && _isDeliveryDriver) {
      _delivery.heartbeat(online: false).catchError((_) {});
    }
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
      List<DeliveryIncoming> dIncoming = const [];
      List<DeliveryOrder> dOrders = _dOrders;
      if (_isDeliveryDriver) {
        // Точка водителя — для подбора по радиусу от склада. Ошибка опроса
        // доставки не должна ломать заказы техники.
        try {
          if (_online) {
            // Водитель едет — точка с прошлого раза устарела. Последняя
            // известная — дёшево и без ожидания спутников.
            final pos = await Geolocator.getLastKnownPosition();
            if (pos != null) _here = TaxiPlace(pos.latitude, pos.longitude);
          }
          await _delivery.heartbeat(online: _online, lat: _here?.lat, lon: _here?.lon);
          dOrders = await _delivery.orders();
        } catch (_) {}
        try {
          _fOrders = await _freight.driverOrders();
        } catch (_) {}
      }
      final busy = orders.any((o) => o.active && !o.scheduled && o.finishedAt == null) ||
          dOrders.any((o) => o.active) ||
          _fOrders.any((o) => o.busyForDriver);
      if (_online && !busy) incoming = await _requests.quickIncoming();
      List<FreightIncoming> fIncoming = const [];
      if (_online && !busy && _isDeliveryDriver) {
        try {
          dIncoming = await _delivery.incoming();
        } catch (_) {}
        try {
          fIncoming = await _freight.incoming();
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _incoming = incoming;
        _dIncoming = dIncoming;
        _fIncoming = fIncoming;
        _dOrders = dOrders;
        _loaded = true;
        _netDown = false;
      });
      _maybeShowIncoming();
    } catch (e) {
      // E3: нет связи — только сетевые ошибки; ответ сервера с ошибкой —
      // это не «нет интернета»
      final net = e is DioException &&
          (e.type == DioExceptionType.connectionError ||
              e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              e.type == DioExceptionType.sendTimeout);
      if (mounted) {
        setState(() {
          _loaded = true;
          _netDown = net;
        });
      }
    }
  }

  Future<void> _maybeShowIncoming() async {
    if (_showingIncoming || !_online || _active != null || _activeDelivery != null || _activeFreight != null) {
      return;
    }
    final fresh = _incoming.where((o) => !_seen.contains(o.id)).toList();
    if (fresh.isNotEmpty) {
      await _openIncoming(fresh.first);
      return;
    }
    final dFresh = _dIncoming.where((o) => !_dSeen.contains(o.id)).toList();
    if (dFresh.isNotEmpty) {
      await _openDeliveryIncoming(dFresh.first);
      return;
    }
    final fFresh = _fIncoming.where((o) => !_fSeen.contains(o.id)).toList();
    if (fFresh.isNotEmpty) await _openFreightIncoming(fFresh.first);
  }

  Future<void> _openFreightIncoming(FreightIncoming o) async {
    _fSeen.add(o.id);
    _showingIncoming = true;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => FreightIncomingPage(order: o)),
    );
    _showingIncoming = false;
    await _countMissed(accepted == null);
    await _refresh();
    final a = _activeFreight;
    if (accepted == true && a != null && mounted) await _openFreight(a);
  }

  Future<void> _openFreight(FreightOrder o) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightDriverOrderPage(order: o)));
    await _refresh();
  }

  Future<void> _openDeliveryIncoming(DeliveryIncoming o) async {
    _dSeen.add(o.id);
    _showingIncoming = true;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => DeliveryIncomingPage(order: o)),
    );
    _showingIncoming = false;
    await _countMissed(accepted == null);
    await _refresh();
    final a = _activeDelivery;
    if (accepted == true && a != null && mounted) await _openDelivery(a);
  }

  Future<void> _openDelivery(DeliveryOrder o) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => DeliveryOrderPage(order: o)));
    await _refresh();
  }

  /// Активная доставка стройматериала вместо листа «ждём заказы».
  Widget _activeDeliveryCard(DeliveryOrder o) {
    final toPickup = o.deliveryStatus == 'accepted';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('driver.delivery_active'.tr(), style: AppTypography.h2),
        const SizedBox(height: 4),
        Text(
          toPickup ? 'driver.delivery_go_pickup'.tr() : 'driver.delivery_go_client'.tr(),
          style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary),
        ),
        const SizedBox(height: 4),
        Text((toPickup ? o.pickupAddress : o.deliveryAddress) ?? '—',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        DPrimary('driver.open'.tr(), onPressed: () => _openDelivery(o)),
      ],
    );
  }

  Future<void> _openIncoming(QuickIncomingModel o) async {
    _seen.add(o.id);
    _showingIncoming = true;
    final accepted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(fullscreenDialog: true, builder: (_) => DriverIncomingPage(order: o)),
    );
    _showingIncoming = false;
    await _countMissed(accepted == null);
    await _refresh();
    if (accepted == true && mounted) {
      final a = _active;
      if (a != null) await _openOrder(a);
    }
  }

  /// E2: не ответил на заказ — счётчик подряд; ответил (взял или отказал) —
  /// сброс. На третьем пропуске водитель на 15 минут уходит с линии: иначе
  /// заказы гуляли бы по спящим телефонам, а клиент ждал.
  Future<void> _countMissed(bool missed) async {
    final prefs = await SharedPreferences.getInstance();
    if (!missed) {
      _missed = 0;
      await prefs.setInt(_missedKey, 0);
      return;
    }
    _missed++;
    await prefs.setInt(_missedKey, _missed);
    if (_missed >= _maxMissed) {
      _missed = 0;
      await prefs.setInt(_missedKey, 0);
      _pausedUntil = DateTime.now().add(_pause);
      await prefs.setString(_pausedUntilKey, _pausedUntil!.toIso8601String());
      await _setOnline(false);
    }
    if (!mounted) return;
    await _missedSheet(paused: _pausedUntil != null && DateTime.now().isBefore(_pausedUntil!));
  }

  Future<void> _missedSheet({required bool paused}) async {
    final stay = await showModalBottomSheet<bool>(
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
                decoration: BoxDecoration(color: DChip.warn, borderRadius: BorderRadius.circular(24)),
                child: const HIcon(Icons.schedule_rounded, color: AppPalette.textPrimary),
              ),
            ),
            const SizedBox(height: 12),
            Text('driver.e2_title'.tr(), style: AppTypography.h2),
            const SizedBox(height: 4),
            Text(
              paused
                  ? 'driver.e2_paused'.tr(args: ['${_pause.inMinutes}'])
                  : 'driver.e2_body'.tr(args: ['$_maxMissed', '${_pause.inMinutes}']),
              style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary),
            ),
            if (!paused) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
                child: Text('driver.e2_counter'.tr(args: ['$_missed', '$_maxMissed']),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
            const SizedBox(height: 14),
            if (paused)
              DPrimary('driver.ok'.tr(), onPressed: () => Navigator.of(ctx).pop(false))
            else
              Row(children: [
                Expanded(child: DSecondary('driver.go_offline'.tr(), tinted: true, onPressed: () => Navigator.of(ctx).pop(false))),
                const SizedBox(width: 10),
                Expanded(child: DPrimary('driver.stay_online'.tr(), onPressed: () => Navigator.of(ctx).pop(true))),
              ]),
          ],
        ),
      ),
    );
    if (!paused && stay == false && mounted) await _setOnline(false);
  }

  /// «Ishga chiqish»: снят с линии за пропуски (E2) или выключена геолокация (E4).
  Future<void> _goOnline() async {
    final until = _pausedUntil;
    if (until != null && DateTime.now().isBefore(until)) {
      final left = until.difference(DateTime.now()).inMinutes + 1;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('driver.e2_wait'.tr(args: ['$left']))),
      );
      return;
    }
    if (!await _locationReady()) {
      if (!mounted) return;
      final fixed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => const _LocationOffPage()),
      );
      if (fixed != true || !await _locationReady()) return;
      _recenter();
    }
    await _setOnline(true);
  }

  static Future<bool> _locationReady() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return false;
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always || p == LocationPermission.whileInUse;
    } catch (_) {
      // Платформа без геолокации (веб) — не мешаем
      return true;
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
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(99),
                    boxShadow: AppShadows.xs,
                  ),
                  child: const AppLogo(kind: AppLogoKind.horizontal, height: 20),
                ),
                const Spacer(),
                _OnlinePill(online: _online, onTap: () => _online ? _setOnline(false) : _goOnline()),
                const SizedBox(width: 8),
                _Round(icon: Icons.notifications_none_rounded, onTap: () => context.push('/notifications')),
              ],
            ),
          ),
          if (_netDown)
            Positioned(
              top: top + 60,
              left: 16,
              right: 16,
              child: Material(
                color: const Color(0xFFE5484D),
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      const HIcon(Icons.sync_problem_rounded, color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('driver.e3_banner'.tr(),
                                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            Text('driver.e3_banner_sub'.tr(),
                                style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
    final d = _activeDelivery;
    if (d != null) return _activeDeliveryCard(d);
    final f = _activeFreight;
    if (f != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('driver.freight_active'.tr(), style: AppTypography.h2),
          const SizedBox(height: 4),
          Text(f.status == 'accepted' ? (f.fromAddress ?? '—') : (f.toAddress ?? '—'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          DPrimary('driver.open'.tr(), onPressed: () => _openFreight(f)),
        ],
      );
    }
    if (_netDown && _online) return _netSheet();
    return _online ? _onlineSheet() : _offlineSheet();
  }

  /// E3 «Aloqa tiklanishini kutyapmiz»: опрос продолжается сам.
  Widget _netSheet() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('driver.e3_title'.tr(), style: AppTypography.h2),
        const SizedBox(height: 4),
        Text('driver.e3_body'.tr(), style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
        const SizedBox(height: 14),
        DSecondary('driver.retry'.tr(), onPressed: _refresh),
      ],
    );
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
                    child: const HIcon(Icons.construction_rounded, color: AppPalette.brand),
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
                  const HIcon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _truckTile(),
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
          onPressed: (eq == null && !_isDeliveryDriver) || !(_verification?.approved ?? false) ? null : _goOnline,
        ),
      ],
    );
  }

  /// «Yuk mashinam»: зарегистрирован — машина и номер, нет — предложение.
  Widget _truckTile() {
    final p = _dProfile;
    final reg = p?.registered ?? false;
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _openDeliverySetup,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: DChip.blueBg, borderRadius: BorderRadius.circular(10)),
                child: const HIcon(Icons.local_shipping_outlined, color: AppPalette.brand),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reg ? (p!.vehicleName ?? '') : 'driver.delivery_add'.tr(),
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    Text(
                      reg
                          ? [p!.plate, 'driver.delivery_cats_n'.tr(args: ['${p.categories.length}'])]
                              .whereType<String>()
                              .join(' · ')
                          : 'driver.delivery_add_hint'.tr(),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary),
                    ),
                  ],
                ),
              ),
              const HIcon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
            ],
          ),
        ),
      ),
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
          HIcon(red ? Icons.error_outline_rounded : Icons.verified_user_outlined,
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
                    const HIcon(Icons.bolt_rounded, color: AppPalette.brand, size: 20),
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
          child: SizedBox(width: 40, height: 40, child: HIcon(icon, size: 22, color: AppPalette.iconPrimary)),
        ),
      );
}

/// E4 «Joylashuvni yoqing»: без GPS водителя не видно на карте и ближние
/// заказы к нему не идут. Возвращает true, если человек пошёл включать.
class _LocationOffPage extends StatelessWidget {
  const _LocationOffPage();

  Future<void> _open(BuildContext context) async {
    try {
      final service = await Geolocator.isLocationServiceEnabled();
      if (!service) {
        await Geolocator.openLocationSettings();
      } else {
        var p = await Geolocator.checkPermission();
        if (p == LocationPermission.denied) p = await Geolocator.requestPermission();
        if (p == LocationPermission.deniedForever) await Geolocator.openAppSettings();
      }
    } catch (_) {}
    if (context.mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Spacer(),
                Center(
                  child: Container(
                    width: 88,
                    height: 88,
                    decoration: const BoxDecoration(color: DChip.blueBg, shape: BoxShape.circle),
                    child: const HIcon(Icons.location_off_outlined, size: 40, color: AppPalette.brand),
                  ),
                ),
                const SizedBox(height: 20),
                Text('driver.e4_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h1),
                const SizedBox(height: 8),
                Text('driver.e4_body'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, height: 1.4, color: AppPalette.textSecondary)),
                const Spacer(flex: 2),
                DPrimary('driver.e4_open'.tr(), onPressed: () => _open(context)),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('driver.e4_later'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ),
        ),
      );
}
