import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/constants/equipment_types.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/app_logo.dart';
import '../../../../core/widgets/map_or_placeholder.dart';
import '../../data/taxi_geo.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_map_layer.dart';
import '../widgets/taxi_sheets.dart';
import '../widgets/taxi_ui.dart';
import 'address_pick_page.dart';
import '../../data/app_status.dart';
import '../../../../core/services/equipment_catalog.dart';
import 'catalog_all_page.dart';
import '../../../../core/widgets/h_icon.dart';
import '../../../freight/presentation/freight_flow.dart';
import '../../../../core/services/permission_service.dart';
import 'package:dio/dio.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../support/presentation/support_pages.dart';
import '../../data/card_api.dart';
import 'taxi_chat_page.dart';
import 'taxi_profile_page.dart';
import '../../../materials/presentation/pages/materials_catalog_page.dart';

/// Главная клиента — заказ техники «как такси» (второй макет, клиентский
/// файл, «Buyurtma oqimi — qadam-baqadam»):
///
///   1 откуда/куда → 3 тип → 4 тариф (+5 навесное, 6 время) → 7 поиск →
///   8 техника найдена → 10 работа завершена, оценка.
///
/// Под капотом — быстрый заказ сервера (mode='quick'): заявка уходит
/// владельцам рядом, первый взявший получает заказ. Цену считает сервер
/// по тарифу админа. Живой карты с машиной нет — решение от 12.11.2026.
class TaxiHomePage extends StatefulWidget {
  const TaxiHomePage({super.key});

  @override
  State<TaxiHomePage> createState() => _TaxiHomePageState();
}

/// confirm — B4: владелец нажал «Yakunlash», клиент подтверждает.
/// notFound — E4: за время поиска никто не взял.
enum _Step { route, type, tariff, searching, notFound, active, confirm, done }

class _TaxiHomePageState extends State<TaxiHomePage> {
  final _api = TaxiService();
  YandexMapController? _map;

  _Step _step = _Step.route;
  bool _busy = false;

  /// Единственная точка заказа — куда нужна техника. Откуда она приедет,
  /// клиенту безразлично (правки 19.11.2026): по умолчанию его
  /// местоположение, булавку можно сдвинуть или найти другой адрес.
  /// В заявку уходит как delivery_*; origin_* больше не отправляется.
  TaxiPlace _from = TaxiGeo.tashkent;
  List<TaxiPlace> _recent = const [];
  List<SavedAddress> _saved = const []; // Pr4: на главной первыми
  Timer? _addressDebounce;

  List<String> _types = const [];
  String? _type;

  List<TariffQuote> _quotes = const [];
  String _tier = 'econom';
  int? _hours;
  List<TaxiAttachment> _attachments = const [];
  TaxiAttachment? _attachment;
  DateTime? _scheduledAt; // null — «Hozir»
  String? _comment;
  String _payment = 'cash'; // cash | balance | card:<id>
  BankCard? _card; // выбранная карта — для подписи и E7

  TaxiRequest? _request;
  Map<String, dynamic>? _order;
  Map<String, dynamic>? _owner;
  TaxiExecutor? _exec;
  Timer? _poll;
  Timer? _clock; // экран 9: таймер работы тикает раз в секунду
  bool _delayDismissed = false; // B2: нажали «Kutaman»
  String? _attachmentName; // B4: строка навесного
  bool _offline = false; // E2: на главной — плашка и приглушение
  bool _netLost = false; // E2 на остальных шагах — жёлтая полоса сверху
  Timer? _netWatch; // пока нет сети — пробуем каждые 5 секунд
  bool _outOfArea = false; // E3
  bool _activeBanner = false; // E5: есть живой заказ, клиент на главной
  int _surge = 0; // E4: «+10% narx» за каждый повторный поиск
  AppStatus? _status;

  // Карта шагов 3–10 (кадры макета): метки А/Б, линия маршрута, техника,
  // круги поиска. Объекты пересобираются, когда меняется _mapStateKey.
  List<MapObject> _mapObjects = const [];
  String? _mapKey;
  final _sheetKey = GlobalKey();
  Offset? _pulseAt; // шаг 7: где на экране точка «откуда»
  bool _justFound = false; // шаг 8 только что открылся — «нашли!»
  Timer? _foundTimer;

  /// Часы по умолчанию. В макете было «Hozir · 4 soat», но Шерзодбек
  /// 22.11.2026 попросил заказ от 1 часа: сервер сам поднимает до минимума
  /// тарифа (`min_hours` в admin/tariffs.php), так что здесь — наименьшее.
  static const _defaultHours = 1;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _poll?.cancel();
    _clock?.cancel();
    _addressDebounce?.cancel();
    _foundTimer?.cancel();
    _netWatch?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _from = here);
    _moveMap(here);
    // E1: геолокации нет — центр Ташкента не выдаём за адрес человека,
    // «Qayerdan» остаётся «Manzilni kiriting» (макет), пока он не выберет.
    if (!TaxiGeo.denied) _resolveFromAddress();
    _askNotificationsOnce();
    _pickDefaultCard();
    // Иконки и названия типов из админки — не ждём, плитки обновятся сами.
    EquipmentCatalog.load(context.locale.languageCode).then((ok) {
      if (ok && mounted) setState(() {});
    });
    _status = AppStatus.last ?? await AppStatus.fetch();
    try {
      final types = await _api.tariffTypes();
      if (mounted) {
        setState(() {
          _types = types;
          _offline = false;
        });
      }
    } on DioException catch (e) {
      // E2: нет сети — главная остаётся, но приглушена, и есть «Qayta urinish»
      if (_isNetErr(e)) _lostNetwork();
      return;
    } catch (_) {}
    await _resume();
  }

  static bool _isNetErr(Object e) =>
      e is DioException &&
      (e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.sendTimeout);

  /// E2: сеть пропала. На главной — плашка из макета, на остальных шагах —
  /// полоса «Qayta ulanmoqda…». Как только сервер ответил — всё убирается
  /// само, без «Qayta urinish» («Ulanish tiklangach … yangilanadi»).
  void _lostNetwork() {
    if (!mounted) return;
    setState(() {
      if (_step == _Step.route) _offline = true;
      _netLost = true;
    });
    _netWatch ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        await AppStatus.fetch();
        _netWatch?.cancel();
        _netWatch = null;
        if (!mounted) return;
        final wasHome = _offline;
        setState(() {
          _offline = false;
          _netLost = false;
        });
        if (wasHome) _init();
      } catch (_) {}
    });
  }

  void _netBack() {
    if (_netLost && mounted) setState(() => _netLost = false);
  }

  /// Sukut bo'yicha to'lov har doim NAQD PULDA qoladi:
  /// foydalanuvchidan buyurtma berish paytida SMS-kod so'ramasligi va
  /// kartadagi pulni oldindan muzlatmasligi uchun.
  Future<void> _pickDefaultCard() async {
    // Avtomatik kartaga o'tkazilmaydi — sukut bo'yicha 'cash'.
  }

  /// Android 13+ и iOS: «Texnika yo'lda» и «Ish yakunlandi» приходят
  /// уведомлением — спрашиваем один раз после геолокации. Отказ не
  /// повторяем: дальше это баннер U5 в «Bildirishnomalar».
  Future<void> _askNotificationsOnce() async {
    if (MapOrPlaceholder.isWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool('notif_asked') ?? false) return;
      await prefs.setBool('notif_asked', true);
      await Permission.notification.request();
    } catch (_) {}
  }

  /// E1: «Ruxsat berish». Отказ навсегда — только через настройки телефона.
  Future<void> _askLocation() async {
    final r = await PermissionService.requestLocationPermission();
    if (!r.isGranted) {
      await PermissionService.openSettings();
      return;
    }
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _from = here);
    _moveMap(here);
    _resolveFromAddress();
  }

  /// E5: тап по плашке «Ekskavator yo'lda» — к живому заказу.
  void _openActive() {
    setState(() {
      _activeBanner = false;
      if (_order == null) {
        _step = _Step.searching;
      } else {
        _step = _order?['finished_at'] != null ? _Step.confirm : _Step.active;
      }
    });
    _startPolling();
  }

  /// E5 «Faol buyurtma bor»: вернувшись в приложение, клиент видит свой
  /// заказ, а не пустую главную.
  Future<void> _loadSaved() async {
    try {
      final a = await ProfileApi().addresses();
      if (mounted) setState(() => _saved = a);
    } catch (_) {}
  }

  Future<void> _resume() async {
    _loadSaved();
    try {
      final mine = await _api.myRequests();
      if (!mounted) return;
      // Последние три РАЗНЫХ адреса: один объект заказывают много раз
      final seen = <String>{};
      _recent = [
        for (final r in mine.where((r) => r.isTariff && r.toLat != null && r.toAddress != null))
          if (seen.add(r.toAddress!.trim().toLowerCase())) TaxiPlace(r.toLat!, r.toLon!, r.toAddress),
      ].take(3).toList();
      final last = mine.where((r) => r.isTariff).firstOrNull;
      if (last == null) return;
      // E5: вернувшись, клиент видит главную и плашку своего заказа
      if (last.status == 'open' || last.status == 'awaiting_payment') {
        setState(() {
          _request = last;
          _type = last.equipmentType;
          _order = null;
          _activeBanner = true;
        });
      } else if (last.status == 'assigned' && last.orderId != null) {
        _request = last;
        _type = last.equipmentType;
        await _loadOrder(last.orderId!);
        final status = _order?['status'];
        if (status == 'confirmed' && mounted) setState(() => _activeBanner = true);
      }
    } catch (_) {}
  }

  void _moveMap(TaxiPlace p) {
    _map?.moveCamera(
      CameraUpdate.newCameraPosition(CameraPosition(target: p.point, zoom: 15)),
      animation: const MapAnimation(duration: 0.4),
    );
  }

  Future<void> _resolveFromAddress() async {
    final at = _from;
    var a = await TaxiGeo.addressAt(at);
    // Первый запрос после запуска MapKit бывает пустым — ещё одна попытка,
    // иначе «Qayerdan» оставалось «Mening joylashuvim», пока карту не сдвинешь.
    if (a == null && mounted) {
      await Future<void>.delayed(const Duration(seconds: 2));
      a = await TaxiGeo.addressAt(at);
    }
    // Пока искали, человек мог сдвинуть карту — старый адрес не нужен.
    if (mounted && a != null && _from.lat == at.lat && _from.lon == at.lon) {
      setState(() => _from = _from.withAddress(a));
    }
  }

  // ------------------------------------------------------------- шаги

  /// «Manzil» — поиск другого адреса; найденный сразу ведёт к выбору техники.
  Future<void> _pickPlace() async {
    final place = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => AddressPickPage(from: _from, recent: _recent, forSaving: true)),
    );
    if (place == null || !mounted) return;
    _choosePlace(place);
  }

  /// Точка выбрана (поиск, «So'nggi manzillar» или «Davom etish» под
  /// булавкой). E3: вне зоны — остаёмся на главной с предупреждением.
  void _choosePlace(TaxiPlace place) {
    final outside = _status != null && !_status!.inArea(place.lat, place.lon);
    setState(() {
      _from = place;
      _outOfArea = outside;
      if (!outside) _step = _Step.type;
    });
    _moveMap(place);
  }

  Future<void> _pickType(String type) async {
    if (type == 'materials') {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const MaterialsCatalogPage()),
      );
      return;
    }
    // «Yuk tashish» — перевозка груза клиента А→Б на грузовике (24.11.2026),
    // а не самосвал по часам, как было.
    // Шаги Y1–Y8 макета: марка → модель → кузов → груз → маршрут → цена.
    if (type == 'freight') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightBrandPage(from: _from)));
      return;
    }
    if (type.startsWith('truck:')) {
      openFreightWithVehicle(context, _from, type.substring(6));
      return;
    }
    setState(() {
      _surge = 0;
      _type = type;
      _busy = true;
      _attachment = null;
      _hours = null;
    });
    try {
      final results = await Future.wait([
        _api.tariffs(
          type,
          hours: _defaultHours,
          latitude: _from.lat,
          longitude: _from.lon,
        ),
        _api.attachments(type),
      ]);
      if (!mounted) return;
      final quotes = results[0] as List<TariffQuote>;
      final atts = results[1] as List<TaxiAttachment>;
      _netBack();
      setState(() {
        _quotes = quotes;
        _attachments = atts;
        // Макет: по умолчанию выбрано навесное «в цене» («Oddiy kovsh»),
        // если админ такое завёл. Платное само не выбирается никогда.
        _attachment = atts.where((a) => a.pricePerHour == 0).firstOrNull;
        _tier = quotes.isNotEmpty ? quotes.first.tier : 'econom';
        _step = _Step.tariff;
      });
    } catch (e) {
      _isNetErr(e) ? _lostNetwork() : _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadQuotes() async {
    if (_type == null) return;
    try {
      final quotes = await _api.tariffs(
        _type!,
        hours: _hours ?? _defaultHours,
        attachmentId: _attachment?.id,
        latitude: _from.lat,
        longitude: _from.lon,
      );
      if (mounted) setState(() => _quotes = quotes);
      _netBack();
    } catch (e) {
      _isNetErr(e) ? _lostNetwork() : _toast(getErrorMessage(e));
    }
  }

  TariffQuote? get _quote => _quotes.where((q) => q.tier == _tier).firstOrNull;

  Future<void> _openSchedule() async {
    final q = _quote;
    if (q == null || _type == null) return;
    final result = await showScheduleSheet(
      context,
      api: _api,
      type: _type!,
      tier: _tier,
      minHours: q.minHours,
      hours: q.hours,
      scheduledAt: _scheduledAt,
      comment: _comment,
      attachmentId: _attachment?.id,
    );
    if (result == null || !mounted) return;
    setState(() {
      _hours = result.hours;
      _scheduledAt = result.at;
      _comment = result.comment;
    });
    _reloadQuotes();
  }

  Future<void> _openAttachments() async {
    final picked = await showAttachmentSheet(
      context,
      typeLabel: EquipmentTypes.label(_type),
      items: _attachments,
      selected: _attachment,
    );
    if (picked == null || !mounted) return;
    setState(() => _attachment = picked.id == 0 ? null : picked);
    _reloadQuotes();
  }

  Future<void> _openPayment({bool cardsOnly = false}) async {
    final m = await showPaymentSheet(context, selected: _payment, cardsOnly: cardsOnly);
    if (m == null || !mounted) return;
    BankCard? card;
    if (m.startsWith('card:')) {
      try {
        final id = int.parse(m.substring(5));
        card = (await CardApi().list()).where((c) => c.id == id).firstOrNull;
      } catch (_) {}
    }
    if (mounted) {
      setState(() {
        _payment = m;
        _card = card;
      });
    }
  }

  /// Подпись способа оплаты в сводках: «Naqd», «Uzcard •• 9012», «Balans».
  String get _payName =>
      _payLabel((_order?['payment_method'] ?? _request?.paymentMethod ?? _payMethod) as String);

  /// Подпись по методу: «Naqd», «Uzcard •• 8829», «Balans». Раньше сводка
  /// поиска решала «наличные или нет» отдельно и при оплате картой
  /// показывала «Naqd».
  String _payLabel(String method) => switch (method) {
        'cash' => 'taxi.pay_cash'.tr(),
        'card' => _card?.label ?? 'taxi.bank_card'.tr(),
        _ => 'taxi.pay_balance'.tr(),
      };

  String get _payMethod => _payment.startsWith('card:') ? 'card' : _payment;
  int? get _cardId => _payment.startsWith('card:') ? int.tryParse(_payment.substring(5)) : null;

  Future<void> _placeOrder() async {
    final q = _quote;
    if (q == null || _type == null) return;
    setState(() => _busy = true);
    try {
      final req = await _api.createOrder(
        equipmentType: _type!,
        tariff: _tier,
        hours: q.hours,
        start: _scheduledAt ?? DateTime.now(),
        toLat: _from.lat,
        toLon: _from.lon,
        toAddress: _from.address,
        attachmentId: _attachment?.id,
        paymentMethod: _payMethod,
        comment: _comment,
        surgePercent: _surge,
        cardId: _cardId,
      );
      if (!mounted) return;
      // Банк попросил SMS-код, чтобы заморозить сумму на карте
      if (req.status == 'awaiting_payment') {
        final otp = await askCardOtp(context);
        if (otp == null || otp.isEmpty) {
          await _api.cancelRequest(req.id);
          return;
        }
        await CardApi().confirmOtp(req.id, otp);
        if (!mounted) return;
      }
      final to = _from;
      setState(() {
        _request = req;
        _step = _Step.searching;
        // «So'nggi manzillar» — без перезапуска приложения
        _recent = [
          to,
          ..._recent.where((p) => (p.address ?? '').toLowerCase() != (to.address ?? '').toLowerCase()),
        ].take(3).toList();
      });
      _startPolling();
    } catch (e) {
      // T5: на карте не хватило денег для заморозки
      if (apiStatus(e) == 402 && _payMethod == 'card' && mounted) {
        setState(() => _busy = false);
        final other = await showInsufficientFunds(context,
            cardLabel: _card?.label ?? 'taxi.bank_card'.tr(), amount: _quote?.total ?? 0);
        if (!mounted || other == null) return;
        if (other) {
          await _openPayment();
        } else {
          setState(() {
            _payment = 'cash';
            _card = null;
          });
        }
        return;
      }
      _isNetErr(e) ? _lostNetwork() : _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ---------------------------------------------------- поиск и заказ

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _tick());
  }

  Future<void> _tick() async {
    try {
      if (_step == _Step.searching && _request != null) {
        final r = await _api.getRequest(_request!.id);
        if (!mounted) return;
        _request = r;
        if (r.status == 'assigned' && r.orderId != null) {
          await _loadOrder(r.orderId!);
          if (!mounted) return;
          taxiHaptic(strong: true);
          setState(() {
            _step = _Step.active;
            _justFound = true;
          });
          _foundTimer?.cancel();
          _foundTimer = Timer(const Duration(seconds: 6), () {
            if (mounted) setState(() => _justFound = false);
          });
        } else if (r.status == 'expired' || r.status == 'cancelled') {
          _poll?.cancel();
          setState(() => _step = _Step.notFound);
        }
      } else if (_step == _Step.active && _order != null) {
        final o = await _api.getOrder(_order!['id'] as int);
        if (!mounted) return;
        setState(() => _order = o);
        _syncClock();
        if (o['status'] == 'completed') {
          _poll?.cancel();
          _clock?.cancel();
          setState(() => _step = _Step.done);
        } else if (o['finished_at'] != null) {
          // Владелец нажал «Yakunlash» — B4, подтверждает клиент.
          _clock?.cancel();
          _clock = null;
          setState(() => _step = _Step.confirm);
        } else if (o['status'] == 'cancelled') {
          _poll?.cancel();
          if (o['cancelled_by'] == 'owner') {
            _ownerCancelled();
          } else {
            _toast('taxi.order_cancelled'.tr());
            _reset();
          }
        }
      } else if (_step == _Step.confirm && _order != null) {
        // Через 10 минут без ответа сервер подтверждает сам.
        final o = await _api.getOrder(_order!['id'] as int);
        if (!mounted) return;
        setState(() => _order = o);
        if (o['status'] == 'completed') {
          _poll?.cancel();
          setState(() => _step = _Step.done);
        }
      }
      _netBack();
    } catch (e) {
      // Сеть пропала — полоса сверху, следующий тик попробует снова.
      if (_isNetErr(e)) _lostNetwork();
    }
  }

  Future<void> _loadOrder(int orderId) async {
    final o = await _api.getOrder(orderId);
    TaxiExecutor? ex;
    try {
      ex = await _api.executor(orderId);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _order = o;
      _exec = ex;
      _owner = ex?.name == null ? null : {'full_name': ex!.name};
    });
    _syncClock();
    _loadAttachmentName();
  }

  Future<void> _loadAttachmentName() async {
    final id = _request?.attachmentId;
    if (id == null || _type == null || _attachmentName != null) return;
    try {
      final list = await _api.attachments(_type!);
      final a = list.where((a) => a.id == id).firstOrNull;
      if (a != null && mounted) setState(() => _attachmentName = a.name);
    } catch (_) {}
  }

  /// B1: владелец отменил. «Boshqa texnika qidirish» — та же заявка
  /// заново (тип, тариф, часы, адреса, навесное, оплата).
  Future<void> _ownerCancelled() async {
    final again = await showOwnerCancelledDialog(context);
    if (!mounted) return;
    final r = _request;
    if (again != true || r == null || r.toLat == null) {
      _reset();
      return;
    }
    await _recreateFrom(r);
  }

  /// Та же заявка заново (B1 «Boshqa texnika qidirish», E4 «Qayta qidirish»):
  /// тип, тариф, часы, адреса, навесное, оплата — из прошлой заявки, плюс
  /// текущая надбавка [_surge].
  Future<void> _recreateFrom(TaxiRequest r) async {
    setState(() {
      _busy = true;
      _order = null;
      _exec = null;
      _owner = null;
      _delayDismissed = false;
    });
    try {
      final req = await _api.createOrder(
        equipmentType: r.equipmentType,
        tariff: r.tariff ?? _tier,
        hours: r.hours ?? _defaultHours,
        start: DateTime.now(),
        toLat: r.toLat!,
        toLon: r.toLon!,
        toAddress: r.toAddress,
        // старые заявки с двумя точками повторяются как были
        fromLat: r.fromLat,
        fromLon: r.fromLon,
        fromAddress: r.fromAddress,
        attachmentId: r.attachmentId,
        paymentMethod: r.paymentMethod,
        surgePercent: _surge,
        cardId: r.paymentMethod == 'card' ? _cardId : null,
      );
      if (!mounted) return;
      setState(() {
        _request = req;
        _step = _Step.searching;
      });
      _startPolling();
    } catch (e) {
      _toast(getErrorMessage(e));
      _reset();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// B4 «Tasdiqlash va to'lash» → экран 10 (оценка).
  Future<void> _confirmWork() async {
    final id = _order?['id'] as int?;
    if (id == null) return;
    setState(() => _busy = true);
    try {
      try {
        await _api.setOrderStatus(id, 'completed');
      } catch (e) {
        if (apiDetail(e) != 'card_payment_failed') rethrow;
        // E7: заморозка на карте пропала — клиент выбирает, как заплатить
        if (mounted) setState(() => _busy = false);
        if (!await _payFailed(id)) return;
      }
      final o = await _api.getOrder(id);
      if (!mounted) return;
      _poll?.cancel();
      setState(() {
        _order = o;
        _step = _Step.done;
      });
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// E7 · To'lov o'tmadi. true — заказ оплачен (картой или наличными).
  Future<bool> _payFailed(int orderId) async {
    while (true) {
      if (!mounted) return false;
      final total = (_order?['total_amount'] as num?) ?? 0;
      final choice = await showPaymentFailed(context, cardLabel: _card?.label, amount: total);
      if (choice == null || !mounted) return false;
      try {
        if (choice == 'cash') {
          await CardApi().payCash(orderId);
          return true;
        }
        var cardId = _cardId;
        if (choice == 'card' || cardId == null) {
          await _openPayment(cardsOnly: true);
          cardId = _cardId;
          if (cardId == null) continue;
        }
        await CardApi().payCard(orderId, cardId);
        return true;
      } catch (e) {
        if (apiDetail(e) != 'card_payment_failed') _toast(getErrorMessage(e));
      }
    }
  }

  /// B4 «Muammo bor» → B5. После жалобы заказ сам не подтвердится.
  Future<void> _reportProblem() async {
    final id = _order?['id'] as int?;
    if (id == null) return;
    final sent = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => OpenDisputePage(kind: 'equipment', orderId: id)),
    );
    if (sent == true) {
      try {
        final o = await _api.getOrder(id);
        if (mounted) setState(() => _order = o);
      } catch (_) {}
    }
  }

  /// Таймер экрана 9 нужен только пока идёт работа.
  void _syncClock() {
    final running = _order?['started_at'] != null &&
        _order?['finished_at'] == null &&
        _order?['status'] == 'confirmed';
    if (running && _clock == null) {
      _clock = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!running) {
      _clock?.cancel();
      _clock = null;
    }
  }

  Future<void> _cancelSearch() async {
    if (_request == null) return;
    final reason = await confirmCancel(context);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await _api.cancelRequest(_request!.id, reason: reason);
      _poll?.cancel();
      if (mounted) setState(() => _step = _Step.tariff);
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancelOrder() async {
    if (_order == null) return;
    final reason = await confirmCancel(context, departed: _order?['departed_at'] != null);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      await _api.setOrderStatus(_order!['id'] as int, 'cancelled', reason: reason);
      _poll?.cancel();
      _reset();
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Экран 10, «Tayyor»: клиент подтверждает конец работы (деньги
  /// двигаются на сервере) и, если поставил звёзды, оставляет отзыв.
  Future<void> _finish(int rating, String comment) async {
    final id = _order?['id'] as int?;
    if (id != null && _order?['status'] == 'confirmed') {
      try {
        await _api.setOrderStatus(id, 'completed');
      } catch (e) {
        _toast(getErrorMessage(e));
        return;
      }
    }
    final eqId = _order?['equipment_id'] as int?;
    if (rating > 0 && eqId != null) {
      try {
        await _api.review(equipmentId: eqId, rating: rating, comment: comment);
      } catch (_) {}
    }
    _reset();
  }

  void _reset() {
    _poll?.cancel();
    _clock?.cancel();
    _clock = null;
    if (!mounted) return;
    setState(() {
      _step = _Step.route;
      _type = null;
      _request = null;
      _order = null;
      _exec = null;
      _owner = null;
      _attachment = null;
      _hours = null;
      _scheduledAt = null;
      _comment = null;
      _delayDismissed = false;
      _attachmentName = null;
      _surge = 0;
      _outOfArea = false;
      _activeBanner = false;
      _justFound = false;
      _pulseAt = null;
    });
    // Карта стояла над местом работ — вернуть её к точке заказа, иначе
    // булавка и адрес в «Manzil» показывали разные места.
    _moveMap(_from);
  }

  /// Профиль → «Buyurtmalarim»: «Kuzatish» возвращает к живому заказу,
  /// «Qayta buyurtma» открывает тот же тип, тариф и адрес на шаге 4.
  Future<void> _openProfile() async {
    final nav = await Navigator.of(context).push<TaxiNav>(
      MaterialPageRoute(builder: (_) => const TaxiProfilePage()),
    );
    if (nav == null || !mounted) return;
    final r = nav.repeat;
    if (r == null) {
      await _resume();
      _moveMap(_from);
      return;
    }
    setState(() {
      // Старые заказы: место работ было в «Qayerdan» (origin), новые — в delivery
      if (r.fromLat != null) {
        _from = TaxiPlace(r.fromLat!, r.fromLon!, r.fromAddress);
      } else if (r.toLat != null) {
        _from = TaxiPlace(r.toLat!, r.toLon!, r.toAddress);
      }
      _payment = r.paymentMethod;
    });
    await _pickType(r.equipmentType);
    if (!mounted) return;
    setState(() {
      if (r.tariff != null && _quotes.any((q) => q.tier == r.tariff)) _tier = r.tariff!;
      _attachment = _attachments.where((a) => a.id == r.attachmentId).firstOrNull ?? _attachment;
      _hours = r.hours;
    });
    _reloadQuotes();
  }

  void _back() {
    setState(() {
      switch (_step) {
        case _Step.tariff:
          _step = _Step.type;
        case _Step.type:
          _step = _Step.route;
        default:
          break;
      }
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // --------------------------------------------------------------- вид

  // ------------------------------------------------------------ карта

  String get _mapStateKey {
    if (_step == _Step.route) return 'route';
    final o = _order;
    return [
      _step.name, _from.lat, _from.lon, _from.address,
      _exec?.lat, _exec?.destLat, _exec?.etaMinutes, o?['departed_at'] != null, o?['arrived_at'] != null, o?['started_at'] != null,
    ].join('|');
  }

  /// Куда едет техника (кадр 8). У старых заявок это origin («Qayerdan»),
  /// у новых — единственная точка, delivery.
  Point get _workPoint => _exec?.destLat != null
      ? Point(latitude: _exec!.destLat!, longitude: _exec!.destLon!)
      : (_request?.fromLat != null
          ? Point(latitude: _request!.fromLat!, longitude: _request!.fromLon!)
          : (_request?.toLat != null
              ? Point(latitude: _request!.toLat!, longitude: _request!.toLon!)
              : _from.point));

  /// Метки и линии под текущий шаг; потом камера — так, чтобы всё было
  /// видно над шторкой.
  Future<void> _refreshMap() async {
    final step = _step;
    if (step == _Step.route) {
      if (_mapObjects.isNotEmpty || _pulseAt != null) {
        setState(() {
          _mapObjects = const [];
          _pulseAt = null;
        });
      }
      return;
    }
    final objs = <MapObject>[];
    var fit = <Point>[];
    // «Yetib keldim» bosilgan — texnika joyida: yo'l chizig'i va «5 daq»
    // endi yolg'on bo'lardi, xarita 9-kadrdagidek joyni ko'rsatadi.
    final started = _order?['started_at'] != null || _order?['arrived_at'] != null;
    try {
      if (step == _Step.searching || step == _Step.notFound) {
        // Кадр 7: точка и расходящиеся круги. E4: те же круги, но застывшие
        objs.add((await TaxiMarkers.pointA(null)).at('a', _from.point, z: 2));
        if (step == _Step.notFound) {
          for (final r in const [350.0, 700.0]) {
            objs.add(CircleMapObject(
              mapId: MapObjectId('ring_$r'),
              circle: Circle(center: _from.point, radius: r),
              strokeWidth: 0,
              strokeColor: Colors.transparent,
              fillColor: AppPalette.brand.withValues(alpha: .07),
            ));
          }
        }
        fit = [_from.point];
      } else if (step == _Step.active && !started) {
        // Кадр 8: техника, пунктир до адреса, плашка «12 daq»
        final eta = _exec?.etaMinutes;
        final work = _workPoint;
        objs.add((await TaxiMarkers.pointA(
          eta != null ? 'taxi.minutes_n'.tr(args: ['$eta']) : null,
          darkLabel: true,
        )).at('a', work, z: 2));
        fit = [work];
        if (_exec?.lat != null) {
          final eq = Point(latitude: _exec!.lat!, longitude: _exec!.lon!);
          final line = await TaxiRoute.between(eq, work);
          objs.add(PolylineMapObject(
            mapId: const MapObjectId('eq_line'),
            polyline: Polyline(points: line),
            strokeColor: AppPalette.brand,
            strokeWidth: 4,
            dashLength: 6,
            gapLength: 5,
            zIndex: 1,
          ));
          objs.add((await TaxiMarkers.equipment(null)).at('eq', eq, z: 3));
          fit = [...line, work];
        }
      } else if (step == _Step.active || step == _Step.confirm || step == _Step.done) {
        // Кадр 9: техника на месте работ
        final at = _workPoint;
        objs.add(CircleMapObject(
          mapId: const MapObjectId('zone'),
          circle: Circle(center: at, radius: 90),
          strokeColor: AppPalette.textSuccess.withValues(alpha: .55),
          strokeWidth: 1.5,
          fillColor: AppPalette.textSuccess.withValues(alpha: .10),
        ));
        objs.add((await TaxiMarkers.equipment(null)).at('eq', at, z: 3));
        fit = [at];
      } else {
        // Кадры 3–6 и E4: одна точка — куда нужна техника
        objs.add((await TaxiMarkers.pointA(_from.address == null ? null : _from.label)).at('a', _from.point, z: 2));
        fit = [_from.point];
      }
    } catch (_) {
      // Картинка метки не собралась — без меток, но с камерой
    }
    if (!mounted || step != _step) return;
    setState(() => _mapObjects = objs);
    await _fit(fit);
    if (step == _Step.searching) _updatePulse();
  }

  /// Камера показывает [pts] в части экрана над шторкой.
  Future<void> _fit(List<Point> pts) async {
    final map = _map;
    if (map == null || pts.isEmpty || !mounted) return;
    final mq = MediaQuery.of(context);
    final dpr = mq.devicePixelRatio;
    final sheet = _sheetKey.currentContext?.size?.height ?? mq.size.height * .5;
    final top = mq.padding.top + 72;
    final bottom = math.max(mq.size.height - sheet - 24, top + 120);
    final rect = ScreenRect(
      topLeft: ScreenPoint(x: 32 * dpr, y: top * dpr),
      bottomRight: ScreenPoint(x: (mq.size.width - 32) * dpr, y: bottom * dpr),
    );
    final BoundingBox box;
    if (pts.length == 1) {
      final p = pts.first;
      box = BoundingBox(
        northEast: Point(latitude: p.latitude + .004, longitude: p.longitude + .005),
        southWest: Point(latitude: p.latitude - .004, longitude: p.longitude - .005),
      );
    } else {
      box = TaxiRoute.bounds(pts);
    }
    try {
      await map.moveCamera(
        CameraUpdate.newGeometry(Geometry.fromBoundingBox(box), focusRect: rect),
        animation: const MapAnimation(duration: .6),
      );
    } catch (_) {}
  }

  Future<void> _updatePulse() async {
    final p = await _map?.getScreenPoint(_from.point);
    if (!mounted || p == null || _step != _Step.searching) return;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    setState(() => _pulseAt = Offset(p.x / dpr, p.y / dpr));
  }

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final key = _mapStateKey;
    if (key != _mapKey) {
      _mapKey = key;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshMap();
      });
    }
    final canGoBack = _step == _Step.type || _step == _Step.tariff;
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
                  _moveMap(_from);
                },
                onCameraPositionChanged: (pos, reason, finished) {
                  if (_step == _Step.searching && finished) _updatePulse();
                  // Точку «откуда» двигает только сам человек и только на
                  // первом шаге — дальше карта лишь фон.
                  if (_step != _Step.route || reason != CameraUpdateReason.gestures) return;
                  _from = TaxiPlace(pos.target.latitude, pos.target.longitude);
                  if (finished) {
                    _addressDebounce?.cancel();
                    _addressDebounce = Timer(const Duration(milliseconds: 300), _resolveFromAddress);
                  }
                },
              ),
            ),
          ),
          if (_step == _Step.route && !MapOrPlaceholder.isWeb) _centerPin(),
          if (_step == _Step.searching && _pulseAt != null)
            Positioned(
              left: _pulseAt!.dx - 120,
              top: _pulseAt!.dy - 120,
              child: const SearchPulse(size: 240),
            ),
          Positioned(
            top: top + AppSpacing.sm,
            left: AppSpacing.gutter,
            // Макет: на первом шаге слева сверху — профиль (нижнего меню у
            // клиента нет), дальше — «назад».
            child: canGoBack
                ? MapIconButton(icon: 'back', label: 'auth.back'.tr(), onTap: _back)
                : _step == _Step.route
                    ? MapIconButton(
                        icon: 'profile',
                        label: 'profile.title'.tr(),
                        onTap: _openProfile,
                      )
                    : const SizedBox.shrink(),
          ),
          if (_step == _Step.route)
            Positioned(
              top: top + AppSpacing.sm,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                    boxShadow: AppShadows.card,
                    border: Border.all(color: AppPalette.borderDefault.withValues(alpha: 0.6)),
                  ),
                  child: const AppLogo(
                    kind: AppLogoKind.horizontal,
                    height: 24,
                  ),
                ),
              ),
            ),
          if (_step == _Step.route && !MapOrPlaceholder.isWeb)
            Positioned(
              right: AppSpacing.gutter,
              bottom: MediaQuery.of(context).padding.bottom + 300,
              child: MapIconButton(
                icon: 'locate',
                label: 'taxi.my_location'.tr(),
                onTap: () async {
                  final here = await TaxiGeo.current();
                  if (!mounted) return;
                  setState(() => _from = here);
                  _moveMap(here);
                  _resolveFromAddress();
                },
              ),
            ),
          if (_step == _Step.confirm)
            const Positioned.fill(child: ColoredBox(color: Color(0x730B1220))),
          // Кадр 10 — отдельный белый экран с крестиком, не шторка над картой
          if (_step == _Step.done)
            Positioned.fill(
              child: ColoredBox(
                color: AppPalette.surface,
                child: SafeArea(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, AppSpacing.gutter, 0),
                          child: Semantics(
                            button: true,
                            label: 'common.close'.tr(),
                            child: TaxiRoundButton(icon: 'close', onTap: () => _finish(0, '')),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.lg),
                          child: _panel(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_offline) const Positioned.fill(child: ColoredBox(color: Color(0xCCE9ECF0))),
          if (_step == _Step.route)
            Positioned(
              top: top + 58,
              left: AppSpacing.gutter,
              right: AppSpacing.gutter,
              child: _offline
                  ? _notice(
                      icon: 'wifi_off',
                      iconBg: AppPalette.dangerSubtle,
                      title: 'taxi.offline_title'.tr(),
                      body: 'taxi.offline_body'.tr(),
                    )
                  : _activeBanner
                      ? _activeNotice()
                      : TaxiGeo.denied
                          ? _notice(
                              icon: 'location_off',
                              iconBg: AppPalette.page,
                              title: 'taxi.location_off_title'.tr(),
                              body: 'taxi.location_off_body'.tr(),
                              action: SizedBox(
                                height: 36,
                                child: ElevatedButton(
                                  onPressed: _askLocation,
                                  style: ElevatedButton.styleFrom(
                                    minimumSize: const Size(0, 36),
                                    padding: const EdgeInsets.symmetric(horizontal: 16),
                                    textStyle: AppTypography.bodyMMedium.copyWith(fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
                                  ),
                                  child: Text('taxi.allow'.tr()),
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
            ),
          if (_netLost && !_offline)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: const Color(0xFFFFF6E0),
                padding: EdgeInsets.fromLTRB(AppSpacing.gutter, top + 8, AppSpacing.gutter, 8),
                child: Row(
                  children: [
                    const TaxiIcon('wifi_off', size: 18),
                    const SizedBox(width: 8),
                    Expanded(child: Text('taxi.chat_offline'.tr(), style: AppTypography.captionS.copyWith(
                      color: AppPalette.textPrimary, fontWeight: FontWeight.w500))),
                  ],
                ),
              ).animate().slideY(begin: -1, duration: 250.ms),
            ),
          if (_showDelay) Positioned(top: top + 58, left: AppSpacing.gutter, right: AppSpacing.gutter, child: _delayBanner()),
          if (_step != _Step.done)
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
                child: TaxiSheet(
                  key: _sheetKey,
                  // Панель доходит до низа экрана, а отступ под полоской
                  // жестов — внутри неё (нижнего меню у клиента нет).
                  bottomInset: MediaQuery.of(context).padding.bottom,
                  child: Flexible(
                    child: SingleChildScrollView(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: KeyedSubtree(key: ValueKey(_step), child: _panel()),
                      ),
                    ),
                  ),
                ),
              ),
          ),
        ],
      ),
    );
  }

  /// Булавка «Texnika shu yerdan olinadi» в центре карты (шаг 1).
  /// Острие булавки (y = 59.5 из 62 в map_pin_a.svg) стоит ровно в
  /// центре карты — туда, по чему берётся адрес. Раньше булавку поднимал
  /// отступ 280, и «Qayerdan» показывал место на ~100 dp ниже острия.
  Widget _centerPin() => IgnorePointer(
        child: Center(
          child: Transform.translate(
            // высота колонки 26 + 6 + 62 = 94, острие на 91.5 от верха
            offset: const Offset(0, -(91.5 - 47)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 26,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppShadows.floating,
                  ),
                  child: Center(
                    widthFactor: 1,
                    child: Text(
                    'taxi.pickup_here'.tr(),
                    style: AppTypography.captionS.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  ),
                ),
                const SizedBox(height: 6),
                SvgPicture.asset('assets/icons/map_pin_a.svg', width: 44, height: 62),
              ],
            ),
          ),
        ),
      );

  Widget _panel() {
    switch (_step) {
      case _Step.route:
        return _routePanel();
      case _Step.type:
        return _typePanel();
      case _Step.tariff:
        return _tariffPanel();
      case _Step.searching:
        return _searchingPanel();
      case _Step.notFound:
        return _notFoundPanel();
      case _Step.active:
        return _activePanel();
      case _Step.confirm:
        return _confirmPanel();
      case _Step.done:
        return DonePanel(
          order: _order,
          request: _request,
          owner: _owner,
          type: _type,
          onFinish: _finish,
        );
    }
  }

  // 1 · Bosh ekran (+ E2 приглушение, E3 вне зоны)
  Widget _routePanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Opacity(opacity: _offline ? .45 : 1, child: IgnorePointer(ignoring: _offline, child: _routeContent())),
          if (_outOfArea && !_offline) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFFFFF6E0), borderRadius: BorderRadius.circular(AppRadius.lg)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const TaxiIcon('alert', size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('taxi.out_of_area_title'.tr(),
                              style: AppTypography.bodyMMedium.copyWith(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text(
                            'taxi.out_of_area_body'.tr(args: [_status?.areaName(context.locale.languageCode) ?? '']),
                            style: const TextStyle(
                              fontFamily: AppTypography.fontFamily,
                              fontSize: 13,
                              height: 18 / 13,
                              color: AppPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: ElevatedButton(onPressed: null, child: Text('taxi.continue'.tr())),
            ),
          ],
          if (_offline) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: _init,
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.brandSubtle,
                    foregroundColor: AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: Text('taxi.retry'.tr()),
                ),
              ),
            ),
          ],
        ],
      );

  Widget _routeContent() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SheetTitle('taxi.where_needed'.tr()),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppPalette.page,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: Column(
                children: [
                  AddressRow(
                    isFrom: true,
                    label: 'taxi.address'.tr(),
                    value: _from.address ?? (TaxiGeo.denied ? 'taxi.enter_address'.tr() : 'taxi.my_location'.tr()),
                    placeholder: _from.address == null && TaxiGeo.denied,
                    onTap: _pickPlace,
                  ),
                ],
              ),
            ),
          ),
          // Точка под булавкой — «Davom etish». Без геолокации адреса ещё
          // нет: сначала его надо найти, кнопка ведёт в поиск.
          if (!_outOfArea) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: ElevatedButton(
                onPressed: (_from.address == null && TaxiGeo.denied) ? _pickPlace : () => _choosePlace(_from),
                child: Text('taxi.continue'.tr()),
              ),
            ),
          ],
          if (_places.isNotEmpty && !_outOfArea) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Text('taxi.recent'.tr(), style: AppTypography.h3),
            ),
            for (final e in _places)
              InkWell(
                onTap: () => _choosePlace(e.place),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
                  child: SizedBox(
                    height: 64,
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: const BoxDecoration(color: AppPalette.page, shape: BoxShape.circle),
                          alignment: Alignment.center,
                          child: TaxiIcon(e.icon, size: 20),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                e.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium,
                              ),
                              Text(
                                e.place.address ?? '',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13,
                                  color: AppPalette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${TaxiGeo.distanceKm(_from, e.place).toStringAsFixed(1)} km',
                          style: const TextStyle(
                            fontFamily: AppTypography.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppPalette.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ],
      );

  /// Строки «So'nggi manzillar»: сохранённые (Uy, Ish…) первыми, затем
  /// последние из заказов без повторов — не больше четырёх, как в макете.
  List<({String icon, String title, TaxiPlace place})> get _places {
    final seen = <String>{};
    final out = <({String icon, String title, TaxiPlace place})>[];
    for (final a in _saved) {
      if (seen.add(a.address.trim().toLowerCase())) {
        out.add((icon: a.icon, title: a.title, place: TaxiPlace(a.lat, a.lon, a.address)));
      }
    }
    for (final p in _recent) {
      if (seen.add((p.address ?? '').trim().toLowerCase())) {
        out.add((icon: 'building', title: p.label, place: p));
      }
    }
    return out.take(4).toList();
  }

  Widget _routeLine() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Row(
          children: [
            SvgPicture.asset('assets/brand/point_a.svg', width: 16, height: 16),
            const SizedBox(width: 6),
            Flexible(child: _routeText(_from.address == null ? 'taxi.my_location'.tr() : _from.label)),
          ],
        ),
      );

  Widget _routeText(String t) => Text(
        t,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w500,
          color: AppPalette.textSecondary,
        ),
      );

  /// Порядок плиток как в макете; остальные типы — после них.
  static const _typeOrder = [
    'excavator', 'bulldozer', 'truck_crane', 'manipulator',
    'concrete_pump', 'dump_truck', 'aerial_platform',
  ];

  List<String> get _orderedTypes {
    final types = _types.toList();
    types.sort((a, b) {
      final ia = _typeOrder.indexOf(a), ib = _typeOrder.indexOf(b);
      return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
    });
    return types;
  }

  /// «Boshqalar» → K2 «Barcha kategoriyalar»: весь справочник из админки.
  Future<void> _moreTypes() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const CatalogAllPage()),
    );
    if (picked != null && mounted) _pickType(picked);
  }

  // 3 · K1 «Bosh ekran — texnika turlari» (Figma, 24.11.2026): поиск,
  // 8 плиток, баннер «Yuk tashish», «Barcha N kategoriya», «Ko'p
  // so'raladi». Плитка «Qurilish materiallari» — пока раздел включён в
  // админке, иначе на её месте «Beton nasos», как в макете.
  Widget _typePanel() {
    final types = _orderedTypes;
    final materials = _status?.materialsEnabled ?? true;
    final tiles = <Widget>[
      TypeTile(type: 'excavator', onTap: _busy ? () {} : () => _pickType('excavator')),
      TypeTile(type: 'bulldozer', onTap: _busy ? () {} : () => _pickType('bulldozer')),
      TypeTile(type: 'truck_crane', onTap: _busy ? () {} : () => _pickType('truck_crane')),
      TypeTile(type: 'dump_truck', onTap: _busy ? () {} : () => _pickType('dump_truck')),
      TypeTile(type: 'front_loader', onTap: _busy ? () {} : () => _pickType('front_loader')),
      TypeTile(type: 'manipulator', onTap: _busy ? () {} : () => _pickType('manipulator')),
      if (materials)
        TypeTile(type: 'materials', onTap: () => _pickType('materials'))
      else
        TypeTile(type: 'concrete_pump', onTap: _busy ? () {} : () => _pickType('concrete_pump')),
      TypeTile(type: 'more', label: 'taxi.more_types'.tr(), onTap: _moreTypes),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 4) {
      final chunk = tiles.sublist(i, i + 4 > tiles.length ? tiles.length : i + 4);
      while (chunk.length < 4) {
        chunk.add(const SizedBox(width: 76));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: chunk,
      ));
    }
    final total = EquipmentCatalog.types.isEmpty ? null : EquipmentCatalog.types.length;
    // «Ko'p so'raladi» — частые запросы: подпись как в макете, ведёт в
    // настоящий поток (тип техники или грузовик).
    const popular = [
      ('JCB 3CX', 'backhoe_loader'),
      ('CAT 320', 'excavator'),
      ('25 t avtokran', 'truck_crane'),
      ('KamAZ samosval', 'dump_truck'),
      ('Hyundai Porter', 'truck:porter'),
      ('Gazel', 'truck:gazel'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle('taxi.which_equipment'.tr()),
        const SizedBox(height: 10),
        _routeLine(),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Material(
            color: AppPalette.page,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: _moreTypes,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                child: Row(children: [
                  const HIcon(Icons.search, color: AppPalette.iconSecondary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text('taxi.search_brand'.tr(),
                        style: AppTypography.bodyM.copyWith(color: AppPalette.textPlaceholder)),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        if (types.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: AppSpacing.lg),
            child: Text('taxi.no_tariffs'.tr(), style: AppTypography.subtitle),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Column(children: rows),
          ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Material(
            color: AppPalette.brandSubtle,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: InkWell(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              onTap: () => _pickType('freight'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('taxi.freight'.tr(), style: AppTypography.h3),
                      const SizedBox(height: 2),
                      Text('taxi.freight_banner'.tr(),
                          style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  const HIcon(Icons.local_shipping_outlined, color: AppPalette.iconBrand, size: 48),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: InkWell(
            onTap: _moreTypes,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Text(total == null ? 'taxi.all_categories'.tr() : 'taxi.all_categories_n'.tr(args: ['$total']),
                    style: AppTypography.bodyMMedium.copyWith(color: AppPalette.textBrand)),
                const SizedBox(width: 4),
                const HIcon(Icons.chevron_right, color: AppPalette.iconBrand, size: 20),
              ]),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 6),
          child: Text('taxi.popular'.tr(), style: AppTypography.h3),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (label, target) in popular)
              ActionChip(
                label: Text(label),
                onPressed: _busy ? null : () => _pickType(target),
                backgroundColor: AppPalette.page,
                side: BorderSide.none,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
              ),
          ]),
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(color: AppPalette.brand)),
          ),
        const SizedBox(height: 8),
      ],
    );
  }

  String _tierName(String tier) => 'taxi.tier_$tier'.tr();
  /// Подпись тарифа как в макете: «45 daqiqada keladi» (время задаёт
  /// админ), «Bugun ichida keladi» для дневного; без времени — общая.
  String _tierNote(TariffQuote q) {
    if (q.tier == 'day') return 'taxi.tier_day_note'.tr();
    if (q.etaMinutes != null) return 'taxi.arrives_in'.tr(args: ['${q.etaMinutes}']);
    return 'taxi.tier_${q.tier}_note'.tr();
  }

  /// Куда едет техника: у старых заявок — «Qayerdan» (origin), у новых — delivery.
  String _placeText(TaxiRequest? r) =>
      r?.fromAddress ?? r?.toAddress ?? _from.address ?? 'taxi.my_location'.tr();

  String get _whenText {
    final h = _quote?.hours ?? _hours ?? _defaultHours;
    final hours = 'taxi.hours_n'.tr(args: ['$h']);
    if (_scheduledAt == null) return '${'taxi.now'.tr()} · $hours';
    final d = _scheduledAt!;
    final hm = '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return '${d.day}.${d.month.toString().padLeft(2, '0')} $hm · $hours';
  }

  // 4 · Texnikani tanlash va buyurtma berish
  Widget _tariffPanel() {
    final q = _quote;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle(EquipmentTypes.label(_type)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Text('taxi.choose_tariff'.tr(), style: AppTypography.subtitle),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 152,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            itemCount: _quotes.length,
            separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.sm),
            itemBuilder: (_, i) {
              final t = _quotes[i];
              return TariffCard(
                type: _type ?? '',
                name: _tierName(t.tier),
                price: t.total,
                note: _tierNote(t),
                fast: t.tier == 'fast',
                selected: t.tier == _tier,
                onTap: () => setState(() => _tier = t.tier),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Row(
            children: [
              Expanded(child: OptionPill(icon: 'clock', text: _whenText, onTap: _openSchedule)),
              if (_attachments.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OptionPill(
                    icon: 'bucket',
                    text: _attachment?.name ?? 'taxi.attachment'.tr(),
                    onTap: _openAttachments,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Row(
            children: [
              PaymentButton(
                cash: _payment == 'cash',
                card: _payment.startsWith('card:'),
                label: _payment == 'cash'
                    ? 'taxi.pay_cash'.tr()
                    : (_card != null ? '•• ${_card!.last4}' : 'taxi.pay_balance'.tr()),
                onTap: _openPayment,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: AccentButton(
                  label: 'taxi.order'.tr(),
                  loading: _busy,
                  onPressed: q == null ? null : _placeOrder,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryCard() {
    final r = _request;
    final price = r?.budget ?? _quote?.total ?? 0;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        children: [
          Row(
            children: [
              EquipmentPhoto(_type ?? '', width: 64, height: 44, background: AppPalette.page),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${EquipmentTypes.label(_type)} · ${_tierName(r?.tariff ?? _tier)}',
                      style: AppTypography.bodyMMedium,
                    ),
                    Text(
                      "${formatSum(price)} ${'common.currency'.tr()} · ${_payLabel(r?.paymentMethod ?? _payMethod)}",
                      style: AppTypography.captionS,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoRow('taxi.address'.tr(), _placeText(r)),
          InfoRow('taxi.when'.tr(), _whenText),
        ],
      ),
    );
  }

  // 7 · Texnika qidirilmoqda
  Widget _searchingPanel() => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: ClipRRect(
              borderRadius: BorderRadius.all(Radius.circular(2)),
              child: LinearProgressIndicator(
                minHeight: 4,
                color: AppPalette.brand,
                backgroundColor: AppPalette.brandSubtle,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          SheetTitle('taxi.searching'.tr()),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 6, AppSpacing.gutter, 0),
            child: Text('taxi.searching_hint'.tr(), style: AppTypography.subtitle),
          ),
          const SizedBox(height: 14),
          _summaryCard(),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: OutlinedButton(
              onPressed: _busy ? null : _cancelSearch,
              child: Text('taxi.cancel_order'.tr()),
            ),
          ),
        ],
      );

  String get _ownerName =>
      (_exec?.name?.trim().isNotEmpty ?? false) ? _exec!.name! : 'taxi.owner'.tr();

  /// «JCB 3CX · Jasur T.» — машина и имя с инициалом фамилии (экран 9).
  String get _machineAndOwner {
    final parts = _ownerName.split(' ').where((p) => p.isNotEmpty).toList();
    final short = parts.length > 1 ? '${parts.first} ${parts[1][0]}.' : _ownerName;
    return '${_exec?.model ?? EquipmentTypes.label(_type)} · $short';
  }

  Future<void> _call() async {
    final phone = _exec?.phone;
    if (phone == null) return;
    await launchUrl(Uri.parse('tel:+${phone.replaceAll(RegExp(r'\D'), '')}'));
  }

  Future<void> _message() async {
    final id = _order?['id'] as int?;
    if (id == null) return;
    try {
      final chatId = await _api.chatFor(id);
      if (!mounted) return;
      final eta = _exec?.etaMinutes;
      final departed = _order?['departed_at'] != null;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => TaxiChatPage(
          chatId: chatId,
          orderId: id,
          name: _exec?.name,
          initials: _exec?.initials,
          phone: _exec?.phone,
          status: _order?['started_at'] != null
              ? 'taxi.in_progress'.tr()
              : _order?['arrived_at'] != null
                  ? 'taxi.arrived'.tr()
              : departed && eta != null
                  ? '${'taxi.on_the_way'.tr()} · ${'taxi.arrives_in_short'.tr(args: ['$eta'])}'
                  : (departed ? 'taxi.on_the_way'.tr() : 'taxi.found'.tr()),
          acceptedAt: DateTime.tryParse('${_order?['created_at'] ?? ''}'),
        ),
      ));
    } catch (e) {
      _toast(getErrorMessage(e));
    }
  }

  Future<void> _extend() async {
    final o = _order;
    if (o == null) return;
    final hours = (o['hours'] as int?) ?? 0;
    final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
    final perHour = hours > 0 ? total / hours : 0.0;
    final started = DateTime.tryParse('${o['started_at']}')?.toLocal();
    final add = await showExtendSheet(
      context,
      perHour: perHour,
      currentTotal: total,
      plannedEnd: started?.add(Duration(hours: hours)),
    );
    if (add == null) return;
    setState(() => _busy = true);
    try {
      final updated = await _api.extend(o['id'] as int, add);
      if (mounted) setState(() => _order = updated);
      _toast('taxi.extend_sent'.tr());
    } catch (e) {
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _activePanel() =>
      _order?['started_at'] != null ? _workingPanel() : _onTheWayPanel();

  String get _tariffLine =>
      '${_tierName((_order?['tariff'] ?? _request?.tariff ?? _tier) as String)} · '
      '${'taxi.hours_n'.tr(args: ['${_order?['hours'] ?? _request?.hours ?? ''}'])}';

  String get _priceLine {
    final cash = (_order?['payment_method'] ?? _request?.paymentMethod) == 'cash';
    return '${formatSum((_order?['total_amount'] as num?) ?? 0)} ${'common.currency'.tr()} · '
        '${cash ? 'taxi.pay_cash'.tr() : _payName}';
  }

  // 8 · Texnika topildi — yo'lda
  Widget _onTheWayPanel() {
    final departed = _order?['departed_at'] != null;
    // Haydovchi «Yetib keldim» bosgan (orders.arrived_at). Ilgari mijoz
    // bu holatni bilmasdi va texnika yonida turganda ham «5 daqiqada
    // keladi» ko'rardi.
    final arrived = _order?['arrived_at'] != null;
    final eta = _exec?.etaMinutes;
    final panel = Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_justFound && !departed) ...[
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(color: AppPalette.successSubtle, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const TaxiIcon('check_circle', size: 30),
              )
                  .animate()
                  .scale(begin: const Offset(.3, .3), duration: 650.ms, curve: Curves.elasticOut)
                  .fadeIn(duration: 200.ms),
            ),
            const SizedBox(height: 10),
          ],
          Row(
            children: [
              const TaxiIcon('status_dot', size: 10),
              const SizedBox(width: AppSpacing.sm),
              Text(
                arrived ? 'taxi.arrived'.tr() : (departed ? 'taxi.on_the_way'.tr() : 'taxi.found'.tr()),
                style: AppTypography.h2,
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            arrived
                ? 'taxi.arrived_hint'.tr()
                : (eta != null ? 'taxi.eta_minutes'.tr(args: ['$eta']) : 'taxi.found_hint'.tr()),
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(color: AppPalette.brandSubtle, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                        _exec?.initials ?? '',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textBrand,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_ownerName, style: AppTypography.bodyMedium),
                          Row(
                            children: [
                              // Звезда без числа (отзывов ещё нет) читалась как поломка
                              if (_exec?.rating != null) ...[
                                const TaxiIcon('star_fill', size: 14),
                                const SizedBox(width: 4),
                              ],
                              Text(
                                [
                                  if (_exec?.rating != null) _exec!.rating!.toStringAsFixed(1),
                                  'taxi.orders_n'.tr(args: ['${_exec?.ordersDone ?? 0}']),
                                ].join(' · '),
                                style: const TextStyle(
                                  fontFamily: AppTypography.fontFamily,
                                  fontSize: 13,
                                  color: AppPalette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Container(height: 1, color: const Color(0xFFDDE2E8)),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    EquipmentPhoto(_type ?? '', width: 64, height: 44, background: AppPalette.page),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${_exec?.model ?? ''} ${EquipmentTypes.label(_type).toLowerCase()}'.trim(),
                            style: AppTypography.bodyMMedium,
                          ),
                          if ((_exec?.plate ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppPalette.surface,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppPalette.textPrimary, width: 1.2),
                              ),
                              child: Text(
                                _exec!.plate!,
                                style: AppTypography.captionSemibold.copyWith(color: AppPalette.textPrimary),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: _ActTile(icon: 'phone', label: 'taxi.call'.tr(), onTap: _exec?.phone == null ? null : _call)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: _ActTile(icon: 'chat', label: 'taxi.message'.tr(), onTap: _message)),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActTile(
                  icon: 'close',
                  label: 'taxi.cancel'.tr(),
                  danger: true,
                  onTap: _busy ? null : _cancelOrder,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Макет, кадр 8: «Manzil» — куда едет техника, точка «Qayerdan»
          InfoRow('taxi.address'.tr(), _request?.fromAddress ?? _from.address ?? _request?.toAddress ?? '—'),
          InfoRow('taxi.tariff'.tr(), _tariffLine),
          InfoRow('taxi.price'.tr(), _priceLine),
        ],
      ),
    );
    if (!_justFound || departed) return panel;
    return panel.animate().fadeIn(duration: 250.ms).slideY(begin: .06, duration: 350.ms, curve: Curves.easeOutCubic);
  }

  // 9 · Ish jarayonida
  Widget _workingPanel() {
    final o = _order!;
    final started = DateTime.tryParse('${o['started_at']}')?.toLocal() ?? DateTime.now();
    final hours = (o['hours'] as int?) ?? 0;
    final total = (o['total_amount'] as num?)?.toDouble() ?? 0;
    final elapsed = DateTime.now().difference(started);
    final planned = Duration(hours: hours);
    final progress = planned.inSeconds == 0 ? 0.0 : (elapsed.inSeconds / planned.inSeconds).clamp(0.0, 1.0);
    final perHour = hours > 0 ? total / hours : 0.0;
    final current = (perHour * elapsed.inSeconds / 3600).clamp(0, total);
    final left = planned - elapsed;
    String two(int v) => v.toString().padLeft(2, '0');
    final timer = '${two(elapsed.inHours)}:${two(elapsed.inMinutes % 60)}:${two(elapsed.inSeconds % 60)}';
    final leftText = left.isNegative
        ? '0 ${'taxi.min_short'.tr()}'
        : 'taxi.hours_minutes'.tr(args: ['${left.inHours}', '${left.inMinutes % 60}']);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TaxiBadge('taxi.in_progress'.tr(), bg: AppPalette.successSubtle, fg: AppPalette.textSuccess),
          const SizedBox(height: AppSpacing.md),
          Text(
            timer,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 40,
              height: 48 / 40,
              fontWeight: FontWeight.w700,
              color: AppPalette.textPrimary,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          Text('taxi.elapsed_of'.tr(args: ['$hours']), style: AppTypography.subtitle),
          const SizedBox(height: AppSpacing.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              color: AppPalette.textSuccess,
              backgroundColor: AppPalette.page,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          InfoRow('taxi.current_price'.tr(), '${formatSum(current)} ${'common.currency'.tr()}'),
          InfoRow('taxi.time_left'.tr(), leftText),
          InfoRow('taxi.machine'.tr(), _machineAndOwner),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: _busy ? null : _extend,
                    style: TextButton.styleFrom(
                      backgroundColor: AppPalette.brandSubtle,
                      foregroundColor: AppPalette.textBrand,
                      textStyle: AppTypography.buttonLarge,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: Text('taxi.extend'.tr()),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Material(
                color: AppPalette.page,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  onTap: _exec?.phone == null ? null : _call,
                  child: const SizedBox(
                    width: 52,
                    height: 52,
                    child: Center(child: TaxiIcon('phone', size: 24)),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'taxi.owner_finishes_hint'.tr(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 18 / 13,
              color: AppPalette.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// Плашка над картой (E1, E2): иконка в квадрате 40, заголовок, текст.
  Widget _notice({
    required String icon,
    required Color iconBg,
    required String title,
    required String body,
    Widget? action,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: AppShadows.floating,
        ),
        child: Row(
          crossAxisAlignment: action == null ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(12)),
              alignment: Alignment.center,
              child: TaxiIcon(icon, size: 24).animate().shake(hz: 4, rotation: .06, delay: 250.ms, duration: 500.ms),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyMedium),
                  const SizedBox(height: 2),
                  Text(
                    body,
                    style: const TextStyle(
                      fontFamily: AppTypography.fontFamily,
                      fontSize: 13,
                      height: 18 / 13,
                      color: AppPalette.textSecondary,
                    ),
                  ),
                  if (action != null) ...[const SizedBox(height: 4), action],
                ],
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: 250.ms).slideY(begin: -.25, duration: 350.ms, curve: Curves.easeOutCubic);

  /// E5: «● Ekskavator yo'lda · 12 daqiqada keladi · Jasur T.»
  Widget _activeNotice() {
    final o = _order;
    final String title;
    if (o == null) {
      title = 'taxi.stage_title_searching'.tr();
    } else if (o['finished_at'] != null) {
      title = 'taxi.stage_title_awaiting_confirm'.tr();
    } else if (o['started_at'] != null) {
      title = '${EquipmentTypes.label(_type)} · ${'taxi.in_progress'.tr().toLowerCase()}';
    } else if (o['arrived_at'] != null) {
      title = 'taxi.arrived'.tr();
    } else if (o['departed_at'] != null) {
      title = 'taxi.type_on_the_way'.tr(args: [EquipmentTypes.label(_type)]);
    } else {
      title = 'taxi.found'.tr();
    }
    final parts = (_exec?.name ?? '').split(' ').where((p) => p.isNotEmpty).toList();
    final shortName = parts.isEmpty ? null : (parts.length > 1 ? '${parts.first} ${parts[1][0]}.' : parts.first);
    final eta = _exec?.etaMinutes;
    final sub = [
      if (o != null && o['departed_at'] != null && o['arrived_at'] == null && o['started_at'] == null && eta != null)
        'taxi.arrives_in'.tr(args: ['$eta']),
      if (shortName != null) shortName,
    ].join(' · ');
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      elevation: 0,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: _openActive,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(AppRadius.lg), boxShadow: AppShadows.floating),
          child: Row(
            children: [
              EquipmentPhoto(_type ?? '', width: 56, height: 40, background: AppPalette.surface),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const TaxiIcon('status_dot', size: 8),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium),
                        ),
                      ],
                    ),
                    if (sub.isNotEmpty)
                      Text(sub, style: AppTypography.captionS.copyWith(fontSize: 13, height: 18 / 13)),
                  ],
                ),
              ),
              const TaxiIcon('chevron_right', size: 20),
            ],
          ),
        ),
      ),
    );
  }

  // E4 · Bo'sh texnika topilmadi
  Widget _notFoundPanel() {
    final r = _request;
    final price = r?.budget ?? _quote?.total ?? 0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(color: AppPalette.accentSubtle, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const TaxiIcon('search', size: 22),
              ).animate().shake(hz: 3, rotation: .08, duration: 700.ms),
              const SizedBox(width: 12),
              Expanded(child: Text('taxi.not_found_title'.tr(), style: AppTypography.h2)),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'taxi.not_found_body'.tr(args: [EquipmentTypes.label(_type).toLowerCase()]),
            style: AppTypography.subtitle,
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(
              children: [
                Row(
                  children: [
                    EquipmentPhoto(_type ?? '', width: 64, height: 44, background: AppPalette.page),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${EquipmentTypes.label(_type)} · ${_tierName(r?.tariff ?? _tier)}',
                              style: AppTypography.bodyMedium.copyWith(fontSize: 15)),
                          Text(
                            "${formatSum(price)} ${'common.currency'.tr()} · ${_payLabel(r?.paymentMethod ?? _payMethod)}",
                            style: AppTypography.captionS.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoRow('taxi.address'.tr(), _placeText(r)),
                InfoRow('taxi.when'.tr(), _whenText),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: _busy || _surge >= 30
                ? null
                : () {
                    setState(() => _surge += 10);
                    final r = _request;
                    if (r != null && r.toLat != null) {
                      _recreateFrom(r);
                    } else {
                      _placeOrder();
                    }
                  },
            child: Text('taxi.search_again_surge'.tr(args: ['10'])),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _step = _Step.tariff);
                      await _openSchedule();
                    },
              style: TextButton.styleFrom(
                backgroundColor: AppPalette.brandSubtle,
                foregroundColor: AppPalette.textBrand,
                textStyle: AppTypography.buttonLarge,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
              ),
              child: Text('taxi.schedule_later'.tr()),
            ),
          ),
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: TextButton(
              onPressed: _reset,
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.textBrand,
                textStyle: AppTypography.buttonLarge,
              ),
              child: Text('taxi.cancel_order'.tr()),
            ),
          ),
        ],
      ),
    );
  }

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  // ------------------------------------------------- B2 · kechikmoqda

  bool get _showDelay =>
      _step == _Step.active &&
      !_delayDismissed &&
      _order?['delay_minutes'] != null &&
      _order?['started_at'] == null;

  Widget _delayBanner() {
    final minutes = _order!['delay_minutes'] as int;
    final reason = (_order!['delay_reason'] as String?)?.trim();
    // Новое время: принятие заказа + время подачи + опоздание.
    final accepted = DateTime.tryParse('${_order!['created_at']}')?.toLocal();
    final arrive = accepted?.add(Duration(minutes: (_exec?.etaMinutes ?? 0) + minutes));
    final body = [
      if (reason != null && reason.isNotEmpty) 'taxi.delay_reason'.tr(args: [reason]),
      if (arrive != null) 'taxi.delay_new_time'.tr(args: [_hm(arrive)]),
      'taxi.delay_cancel_free'.tr(),
    ].join(' ');
    Widget btn(String label, VoidCallback? onTap, {bool filled = false}) => SizedBox(
          height: 36,
          child: TextButton(
            onPressed: onTap,
            style: TextButton.styleFrom(
              backgroundColor: filled ? AppPalette.brandSubtle : Colors.transparent,
              foregroundColor: AppPalette.textBrand,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              textStyle: const TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                height: 18 / 14,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.1,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
            ),
            child: Text(label),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: AppShadows.floating,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(color: Color(0xFFFFF6E0), shape: BoxShape.circle),
            alignment: Alignment.center,
            child: const TaxiIcon('clock', size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('taxi.delay_title'.tr(args: ['$minutes']), style: AppTypography.bodyMedium),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 13,
                    height: 18 / 13,
                    color: AppPalette.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    btn('taxi.call'.tr(), _exec?.phone == null ? null : _call, filled: true),
                    const SizedBox(width: 8),
                    btn('taxi.wait'.tr(), () => setState(() => _delayDismissed = true)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------- B4 · yakunini tasdiqlash

  Widget _confirmPanel() {
    final o = _order ?? const {};
    final started = DateTime.tryParse('${o['started_at']}')?.toLocal();
    final finished = DateTime.tryParse('${o['finished_at']}')?.toLocal();
    final worked = started != null && finished != null ? finished.difference(started) : null;
    final hours = (o['hours'] as int?) ?? _request?.hours ?? 0;
    final attPrice = _request?.attachmentPrice ?? 0;
    final total = ((o['total_amount'] as num?) ?? 0).toDouble();
    final tariffPerHour = hours > 0 ? (total / hours - attPrice) : 0.0;
    final problem = o['problem_reported_at'] != null;
    Widget row(String l, String v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  l,
                  style: bold
                      ? AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, height: 20 / 16)
                      : AppTypography.subtitle,
                ),
              ),
              Text(
                v,
                style: bold
                    ? AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700, height: 20 / 16)
                    : AppTypography.bodyMMedium,
              ),
            ],
          ),
        );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(color: Color(0xFFE6F4F1), shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const TaxiIcon('check_circle', size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('taxi.owner_finished'.tr(), style: AppTypography.h3),
                    const SizedBox(height: 2),
                    Text(
                      [_ownerName, if (finished != null) _hm(finished)].join(' · '),
                      style: AppTypography.subtitle,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(
              children: [
                if (worked != null)
                  row('taxi.worked_time'.tr(),
                      'taxi.hours_minutes'.tr(args: ['${worked.inHours}', '${worked.inMinutes % 60}'])),
                // Тариф отдельной строкой: без неё «навесное 160 000» и
                // «к оплате 800 000» не складывались у человека в голове.
                if (hours > 0 && tariffPerHour > 0)
                  row(
                    '${_tierName((o['tariff'] ?? _request?.tariff ?? _tier) as String)} · '
                        '${'taxi.hours_n'.tr(args: ['$hours'])} × ${formatSum(tariffPerHour)}',
                    "${formatSum(tariffPerHour * hours)} ${'common.currency'.tr()}",
                  ),
                if (attPrice > 0)
                  row(_attachmentName ?? 'taxi.attachment'.tr(),
                      "${formatSum(attPrice * hours)} ${'common.currency'.tr()}"),
                row('taxi.to_pay'.tr(),
                    "${formatSum((o['total_amount'] as num?) ?? 0)} ${'common.currency'.tr()}",
                    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
            problem ? 'taxi.problem_pending'.tr() : 'taxi.auto_confirm_hint'.tr(),
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              height: 18 / 13,
              color: AppPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _busy ? null : _confirmWork,
            child: Text('taxi.confirm_and_pay'.tr()),
          ),
          SizedBox(
            height: AppSpacing.buttonHeight,
            child: TextButton(
              onPressed: _busy || problem ? null : _reportProblem,
              style: TextButton.styleFrom(
                foregroundColor: AppPalette.textBrand,
                textStyle: AppTypography.buttonLarge,
              ),
              child: Text('taxi.has_problem'.tr()),
            ),
          ),
        ],
      ),
    );
  }
}

/// Кнопка-плитка экрана 8: «Qo'ng'iroq», «Xabar», «Bekor qilish».
class _ActTile extends StatelessWidget {
  const _ActTile({required this.icon, required this.label, required this.onTap, this.danger = false});

  final String icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Column(
            children: [
              TaxiIcon(icon, size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontFamily: AppTypography.fontFamily,
                  fontSize: 13,
                  height: 18 / 13,
                  fontWeight: FontWeight.w500,
                  color: danger ? AppPalette.textDanger : AppPalette.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
