import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/constants/equipment_types.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/map_or_placeholder.dart';
import '../../data/taxi_geo.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_sheets.dart';
import '../widgets/taxi_ui.dart';
import 'address_pick_page.dart';
import '../../data/app_status.dart';
import '../../../../core/services/permission_service.dart';
import 'package:dio/dio.dart';
import 'problem_page.dart';
import '../../data/card_api.dart';
import 'taxi_chat_page.dart';
import 'taxi_profile_page.dart';

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

  TaxiPlace _from = TaxiGeo.tashkent;
  TaxiPlace? _to;
  List<TaxiPlace> _recent = const [];
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
  bool _offline = false; // E2
  bool _outOfArea = false; // E3
  bool _activeBanner = false; // E5: есть живой заказ, клиент на главной
  int _surge = 0; // E4: «+10% narx» за каждый повторный поиск
  AppStatus? _status;

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
    super.dispose();
  }

  Future<void> _init() async {
    final here = await TaxiGeo.current();
    if (!mounted) return;
    setState(() => _from = here);
    _moveMap(here);
    _resolveFromAddress();
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
      final net = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout;
      if (mounted && net) setState(() => _offline = true);
      return;
    } catch (_) {}
    await _resume();
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
  Future<void> _resume() async {
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
    final a = await TaxiGeo.addressAt(_from);
    if (mounted && a != null) setState(() => _from = _from.withAddress(a));
  }

  // ------------------------------------------------------------- шаги

  Future<void> _pickTo() async {
    final place = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => AddressPickPage(from: _from, recent: _recent)),
    );
    if (place == null || !mounted) return;
    // E3: вне зоны — остаёмся на главной с предупреждением
    final outside = _status != null && !_status!.inArea(place.lat, place.lon);
    setState(() {
      _to = place;
      _outOfArea = outside;
      if (!outside) _step = _Step.type;
    });
  }

  Future<void> _pickType(String type) async {
    setState(() {
      _surge = 0;
      _type = type;
      _busy = true;
      _attachment = null;
      _hours = null;
    });
    try {
      final results = await Future.wait([
        _api.tariffs(type),
        _api.attachments(type),
      ]);
      if (!mounted) return;
      final quotes = results[0] as List<TariffQuote>;
      final atts = results[1] as List<TaxiAttachment>;
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
      _toast(getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reloadQuotes() async {
    if (_type == null) return;
    try {
      final quotes = await _api.tariffs(_type!, hours: _hours, attachmentId: _attachment?.id);
      if (mounted) setState(() => _quotes = quotes);
    } catch (e) {
      _toast(getErrorMessage(e));
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
  String get _payName {
    final m = (_order?['payment_method'] ?? _request?.paymentMethod ?? _payMethod) as String;
    if (m == 'card') return _card?.label ?? 'taxi.bank_card'.tr();
    return m == 'cash' ? 'taxi.pay_cash'.tr() : 'taxi.pay_balance'.tr();
  }

  String get _payMethod => _payment.startsWith('card:') ? 'card' : _payment;
  int? get _cardId => _payment.startsWith('card:') ? int.tryParse(_payment.substring(5)) : null;

  Future<void> _placeOrder() async {
    final q = _quote;
    if (q == null || _type == null || _to == null) return;
    setState(() => _busy = true);
    try {
      final req = await _api.createOrder(
        equipmentType: _type!,
        tariff: _tier,
        hours: q.hours,
        start: _scheduledAt ?? DateTime.now(),
        toLat: _to!.lat,
        toLon: _to!.lon,
        toAddress: _to!.address,
        fromLat: _from.lat,
        fromLon: _from.lon,
        fromAddress: _from.address,
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
      setState(() {
        _request = req;
        _step = _Step.searching;
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
      _toast(getErrorMessage(e));
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
          if (mounted) setState(() => _step = _Step.active);
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
    } catch (_) {
      // Сеть пропала — следующий тик попробует снова.
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
        hours: r.hours ?? 4,
        start: DateTime.now(),
        toLat: r.toLat!,
        toLon: r.toLon!,
        toAddress: r.toAddress,
        fromLat: r.fromLat ?? _from.lat,
        fromLon: r.fromLon ?? _from.lon,
        fromAddress: r.fromAddress ?? _from.address,
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
      MaterialPageRoute(builder: (_) => ProblemPage(orderId: id)),
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
    final ok = await confirmCancel(context);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.cancelRequest(_request!.id);
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
    final ok = await confirmCancel(context, departed: _order?['departed_at'] != null);
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await _api.setOrderStatus(_order!['id'] as int, 'cancelled');
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
      _to = null;
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
    });
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
      return;
    }
    setState(() {
      if (r.toLat != null) _to = TaxiPlace(r.toLat!, r.toLon!, r.toAddress);
      if (r.fromLat != null) _from = TaxiPlace(r.fromLat!, r.fromLon!, r.fromAddress);
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
          _to = null;
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

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.of(context).padding.top;
    final canGoBack = _step == _Step.type || _step == _Step.tariff;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: Stack(
        children: [
          Positioned.fill(
            child: MapOrPlaceholder(
              hintKey: 'taxi.map_web_hint',
              mapBuilder: (_) => YandexMap(
                onMapCreated: (c) {
                  _map = c;
                  _moveMap(_from);
                },
                onCameraPositionChanged: (pos, reason, finished) {
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
          if (_showDelay) Positioned(top: top + 58, left: AppSpacing.gutter, right: AppSpacing.gutter, child: _delayBanner()),
          Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.78),
                child: TaxiSheet(
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
  Widget _centerPin() => IgnorePointer(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppPalette.surface,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: AppShadows.floating,
                  ),
                  child: Text(
                    'taxi.pickup_here'.tr(),
                    style: AppTypography.captionS.copyWith(
                      color: AppPalette.textPrimary,
                      fontWeight: FontWeight.w500,
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
                    label: 'taxi.from'.tr(),
                    value: _from.address ?? 'taxi.my_location'.tr(),
                    onTap: () {},
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 50),
                    child: Container(height: 1, color: const Color(0xFFDDE2E8)),
                  ),
                  AddressRow(
                    isFrom: false,
                    label: 'taxi.to'.tr(),
                    value: _to?.address ?? 'taxi.enter_address'.tr(),
                    placeholder: _to == null,
                    onTap: _pickTo,
                  ),
                ],
              ),
            ),
          ),
          if (_recent.isNotEmpty && !_outOfArea) ...[
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: Text('taxi.recent'.tr(), style: AppTypography.h3),
            ),
            for (final p in _recent)
              InkWell(
                onTap: () => setState(() {
                  _to = p;
                  _step = _Step.type;
                }),
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
                          child: const TaxiIcon('building', size: 20),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (p.address ?? '').split(',').first,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.bodyMedium,
                              ),
                              Text(
                                p.address ?? '',
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
                          '${TaxiGeo.distanceKm(_from, p).toStringAsFixed(1)} km',
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

  Widget _routeLine() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Row(
          children: [
            SvgPicture.asset('assets/brand/point_a.svg', width: 16, height: 16),
            const SizedBox(width: 6),
            Flexible(child: _routeText(_from.address ?? 'taxi.my_location'.tr())),
            const SizedBox(width: 6),
            _routeText('→'),
            const SizedBox(width: 6),
            SvgPicture.asset('assets/brand/point_b.svg', width: 16, height: 16),
            const SizedBox(width: 6),
            Flexible(child: _routeText(_to?.address ?? '')),
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

  Future<void> _moreTypes() async {
    final rest = _orderedTypes.skip(7).toList();
    if (rest.isEmpty) {
      _toast('taxi.no_more_types'.tr());
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Wrap(
            spacing: (MediaQuery.of(ctx).size.width - 2 * AppSpacing.gutter - 4 * 76) / 3,
            runSpacing: 14,
            children: [for (final t in rest) TypeTile(type: t, onTap: () => Navigator.of(ctx).pop(t))],
          ),
        ),
      ),
    );
    if (picked != null) _pickType(picked);
  }

  // 3 · Texnika turini tanlash — 4 в ряд, седьмая плитка и «Boshqalar».
  Widget _typePanel() {
    final types = _orderedTypes;
    final tiles = <Widget>[
      for (final t in types.take(7)) TypeTile(type: t, onTap: _busy ? () {} : () => _pickType(t)),
      TypeTile(type: 'more', label: 'taxi.more_types'.tr(), onTap: _moreTypes),
    ];
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 4) {
      final chunk = tiles.sublist(i, i + 4 > tiles.length ? tiles.length : i + 4);
      while (chunk.length < 4) {
        chunk.add(const SizedBox(width: 76));
      }
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 14));
      rows.add(Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: chunk));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SheetTitle('taxi.which_equipment'.tr()),
        const SizedBox(height: 14),
        _routeLine(),
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
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: AppSpacing.md),
            child: Center(child: CircularProgressIndicator(color: AppPalette.brand)),
          ),
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

  /// «8.4 km · ~20 daq» — от точки «откуда» до «куда».
  String get _routeMeta {
    if (_to == null) return '';
    final km = TaxiGeo.distanceKm(_from, _to!);
    final min = (km / 25 * 60).round().clamp(5, 999);
    return '${km.toStringAsFixed(1)} km · ~${'taxi.minutes_n'.tr(args: ['$min'])}';
  }

  String get _whenText {
    final h = _quote?.hours ?? _hours ?? 4;
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
        SheetTitle(
          EquipmentTypes.label(_type),
          trailing: Text(
            _routeMeta,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppPalette.textSecondary,
            ),
          ),
        ),
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
    final cash = (r?.paymentMethod ?? _payment) == 'cash';
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
                      "${formatSum(price)} ${'common.currency'.tr()} · ${cash ? 'taxi.pay_cash'.tr() : _payName}",
                      style: AppTypography.captionS,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          InfoRow('taxi.from'.tr(), r?.fromAddress ?? _from.address ?? 'taxi.my_location'.tr()),
          InfoRow('taxi.to'.tr(), r?.toAddress ?? _to?.address ?? '—'),
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
    final eta = _exec?.etaMinutes;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const TaxiIcon('status_dot', size: 10),
              const SizedBox(width: AppSpacing.sm),
              Text(departed ? 'taxi.on_the_way'.tr() : 'taxi.found'.tr(), style: AppTypography.h2),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            eta != null ? 'taxi.eta_minutes'.tr(args: ['$eta']) : 'taxi.found_hint'.tr(),
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
                              const TaxiIcon('star_fill', size: 14),
                              const SizedBox(width: 4),
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
          InfoRow('taxi.address'.tr(), _request?.toAddress ?? _to?.address ?? '—'),
          InfoRow('taxi.tariff'.tr(), _tariffLine),
          InfoRow('taxi.price'.tr(), _priceLine),
        ],
      ),
    );
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
              child: TaxiIcon(icon, size: 24),
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
      );

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
    } else if (o['departed_at'] != null) {
      title = 'taxi.type_on_the_way'.tr(args: [EquipmentTypes.label(_type)]);
    } else {
      title = 'taxi.found'.tr();
    }
    final parts = (_exec?.name ?? '').split(' ').where((p) => p.isNotEmpty).toList();
    final shortName = parts.isEmpty ? null : (parts.length > 1 ? '${parts.first} ${parts[1][0]}.' : parts.first);
    final eta = _exec?.etaMinutes;
    final sub = [
      if (o != null && o['departed_at'] != null && o['started_at'] == null && eta != null)
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
    final cash = (r?.paymentMethod ?? _payment) == 'cash';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('taxi.not_found_title'.tr(), style: AppTypography.h2),
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
                            "${formatSum(price)} ${'common.currency'.tr()} · ${cash ? 'taxi.pay_cash'.tr() : _payName}",
                            style: AppTypography.captionS.copyWith(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                InfoRow('taxi.from'.tr(), r?.fromAddress ?? _from.address ?? 'taxi.my_location'.tr()),
                InfoRow('taxi.to'.tr(), r?.toAddress ?? _to?.address ?? '—'),
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
