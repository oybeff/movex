import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/number_formatter.dart';
import '../../../core/widgets/h_icon.dart';
import '../../taxi/data/taxi_geo.dart';
import '../../taxi/presentation/pages/address_pick_page.dart';
import '../../taxi/presentation/widgets/taxi_ui.dart';
import '../data/freight_api.dart';
import 'freight_orders_page.dart';

/// «Yuk tashish» по шагам макета (Figma → Mijoz ilovasi → Katalog,
/// Y1–Y8), 24.11.2026:
///
///   Y1 марка  →  Y2 модель  →  Y3 кузов  →  Y4 груз (Y7 «sig'maydi»)
///   →  Y5 откуда/куда/когда  →  Y6 цена и подтверждение.
///   Y8 «Menga farqi yo'q» — груз сначала, машину подбираем сами.
///
/// Все цены, «свободные рядом» и проверку «влезет ли» считает сервер
/// (`/freight/quote`); здесь — только экраны.

/// Черновик заказа, который проходит через все шаги.
class FreightDraft {
  FreightDraft(this.from);

  TaxiPlace from;
  TaxiPlace? to;
  FreightVehicle? vehicle;
  String? body;
  String? cargoType;
  double? weightKg;
  double? length, width, height, volume;
  bool loader = false;
  /// Грузчик: 'hour' — по часам, 'day' — на день (цены в админке).
  String loaderMode = 'hour';
  int loaderHours = 1;
  DateTime? when; // null — «Hozir»
  String? note;
  bool cash = false;
}

const kBodyTypes = ['tent', 'open', 'van', 'isothermal', 'fridge', 'tank', 'manipulator'];
const kCargoTypes = ['construction', 'furniture', 'appliances', 'food', 'bulk', 'liquid', 'container', 'other'];

/// Какой кузов подходит грузу (Y8): мебель — в закрытый, продукты — в
/// изотермический, сыпучее — в бортовой…
String bodyFor(String? cargo, List<String> bodies) {
  final prefs = switch (cargo) {
    'furniture' || 'appliances' => ['van', 'tent'],
    'food' => ['isothermal', 'fridge', 'van'],
    'construction' || 'bulk' => ['open', 'tent'],
    'liquid' => ['tank'],
    'container' => ['open'],
    _ => ['tent', 'van', 'open'],
  };
  for (final p in prefs) {
    if (bodies.contains(p)) return p;
  }
  return bodies.isEmpty ? 'tent' : bodies.first;
}

String _sum(double v) => '${NumberFormatter.formatCurrency(v)} ${'common.currency'.tr()}';

String _t(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString().replaceAll('.', ',');

String bodyName(String? b) => b == null ? '' : 'freight.body_$b'.tr();

/// Общий каркас шага: заголовок с номером шага, список и нижняя кнопка.
class _Step extends StatelessWidget {
  const _Step({required this.title, this.subtitle, required this.children, this.button, this.onButton, this.accent = false});

  final String title;
  final String? subtitle;
  final List<Widget> children;
  final String? button;
  final VoidCallback? onButton;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Material(
                  color: AppPalette.page,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const SizedBox(width: 40, height: 40, child: HIcon(Icons.chevron_left, color: AppPalette.iconPrimary)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: AppTypography.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!, style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                  ]),
                ),
              ]),
            ),
            Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: children)),
            if (button != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accent ? AppPalette.accent : AppPalette.brand,
                      foregroundColor: accent ? AppPalette.textOnAccent : AppPalette.textOnBrand,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    onPressed: onButton,
                    child: Text(button!, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

Widget _section(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(t.toUpperCase(),
          style: AppTypography.captionSemibold.copyWith(color: AppPalette.textSecondary, letterSpacing: .4)),
    );

Widget _chip(String label, bool on, VoidCallback onTap) => Padding(
      padding: const EdgeInsets.only(right: 8, bottom: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: on,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        selectedColor: AppPalette.brandSubtle,
        backgroundColor: AppPalette.page,
        labelStyle: TextStyle(color: on ? AppPalette.brand : AppPalette.textPrimary, fontWeight: FontWeight.w500),
        side: BorderSide(color: on ? AppPalette.brand : Colors.transparent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      ),
    );

Widget _field(String label, TextEditingController c, {String? suffix, bool error = false, ValueChanged<String>? onChanged}) =>
    TextField(
      controller: c,
      onChanged: onChanged,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: error ? AppPalette.dangerSubtle : AppPalette.page,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: error ? const BorderSide(color: AppPalette.borderDanger) : BorderSide.none,
        ),
      ),
    );

double? _num(TextEditingController c) => double.tryParse(c.text.replaceAll(',', '.').trim());

/// Карточка грузовика (Y2, Y7, Y8): фото-заглушка, тоннаж, размеры, цена
/// за км, «N ta bo'sh · X km», «… so'm dan».
class _TruckCard extends StatelessWidget {
  const _TruckCard({required this.v, required this.selected, required this.onTap, this.title, this.tag});

  final FreightVehicle v;
  final bool selected;
  final VoidCallback onTap;
  final String? title;
  final String? tag;

  @override
  Widget build(BuildContext context) {
    final line = [
      '${_t(v.tonnes)} t',
      if (v.dims != null) '${v.dims} m',
      if (v.pricePerKm != null) '${NumberFormatter.formatCurrency(v.pricePerKm!)} so\'m/km',
    ].join(' · ');
    final free = v.freeDrivers > 0
        ? 'freight.free_n'.tr(args: ['${v.freeDrivers}']) + (v.nearestKm == null ? '' : ' · ${_t(v.nearestKm!)} km')
        : 'freight.free_none'.tr();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selected ? AppPalette.brandSubtle : AppPalette.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          side: BorderSide(color: selected ? AppPalette.brand : AppPalette.borderDefault, width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Container(
                width: 64,
                height: 56,
                decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.md)),
                child: TruckPhoto(iconUrl: v.iconUrl, width: 60, height: 48, background: AppPalette.page),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(
                      child: Text(title ?? v.name,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis),
                    ),
                    if (tag != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(color: AppPalette.successSubtle, borderRadius: BorderRadius.circular(6)),
                        child: Text(tag!, style: const TextStyle(fontSize: 11, color: AppPalette.textSuccess, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ]),
                  Text(line, style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                  Text('● $free',
                      style: AppTypography.captionS.copyWith(
                          color: v.freeDrivers > 0 ? AppPalette.textSuccess : AppPalette.textSecondary,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    v.minPrice == null ? 'freight.no_price'.tr() : 'freight.from_price'.tr(args: [_sum(v.minPrice!)]),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Загрузка списка машин для каталога шагов. Маршрута ещё нет — считаем от
/// точки клиента до неё же: нужны марки, кузова, свободные водители.
Future<FreightQuote> _catalog(FreightDraft d) => FreightApi().quote(
      fromLat: d.from.lat,
      fromLon: d.from.lon,
      toLat: d.from.lat,
      toLon: d.from.lon,
      body: d.body,
    );

// ===================================================================== Y1

/// Y1 · Yuk tashish 1/4 — марка. Группы по размеру, «Menga farqi yo'q».
class FreightBrandPage extends StatefulWidget {
  const FreightBrandPage({super.key, required this.from});

  final TaxiPlace from;

  @override
  State<FreightBrandPage> createState() => _FreightBrandPageState();
}

class _FreightBrandPageState extends State<FreightBrandPage> {
  late final FreightDraft _d = FreightDraft(widget.from);
  final _search = TextEditingController();
  List<FreightVehicle> _all = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
    _catalog(_d).then((q) {
      if (mounted) setState(() => _all = q.vehicles);
    }).whenComplete(() {
      if (mounted) setState(() => _loading = false);
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(String brand) {
    final models = _all.where((v) => v.brand == brand).toList();
    if (models.length == 1) {
      _d.vehicle = models.first;
      openAfterModel(context, _d);
    } else {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightModelPage(draft: _d, models: models)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = _search.text.trim().toLowerCase();
    final list = _all.where((v) =>
        q.isEmpty ||
        v.name.toLowerCase().contains(q) ||
        v.brand.toLowerCase().contains(q) ||
        v.bodyTypes.any((b) => bodyName(b).toLowerCase().contains(q)));
    final byClass = <String, Map<String, List<FreightVehicle>>>{};
    for (final v in list) {
      byClass.putIfAbsent(v.sizeClass, () => {}).putIfAbsent(v.brand, () => []).add(v);
    }
    return _Step(
      title: 'freight.title'.tr(),
      subtitle: 'freight.y1_sub'.tr(),
      children: [
        TextField(
          controller: _search,
          decoration: InputDecoration(
            hintText: 'freight.search_hint'.tr(),
            prefixIcon: const HIcon(Icons.search, color: AppPalette.iconSecondary),
            filled: true,
            fillColor: AppPalette.page,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.lg), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        Material(
          color: AppPalette.brandSubtle,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.lg),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightAutoPage(draft: _d, all: _all))),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(children: [
                const HIcon(Icons.flash_on_rounded, color: AppPalette.accentPressed),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('freight.dont_care'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    Text('freight.dont_care_hint'.tr(), style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                  ]),
                ),
              ]),
            ),
          ),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        for (final cls in const ['small', 'medium', 'large', 'trailer'])
          if (byClass[cls] != null) ...[
            _section('freight.class_$cls'.tr()),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final e in byClass[cls]!.entries)
                Material(
                  color: AppPalette.page,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    onTap: () => _open(e.key),
                    child: SizedBox(
                      width: 76,
                      height: 56,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text(e.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500), maxLines: 1),
                        Text(
                          e.value.length > 1
                              ? 'freight.n_models'.tr(args: ['${e.value.length}'])
                              : 'freight.n_bodies'.tr(args: ['${e.value.first.bodyTypes.length}']),
                          style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary),
                        ),
                      ]),
                    ),
                  ),
                ),
            ]),
          ],
      ],
    );
  }
}

/// После выбора модели: кузов (если есть выбор) или сразу груз.
void openAfterModel(BuildContext context, FreightDraft d) {
  final v = d.vehicle!;
  if (v.bodyTypes.length > 1) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightBodyPage(draft: d)));
  } else {
    d.body = v.bodyTypes.isEmpty ? null : v.bodyTypes.first;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightCargoPage(draft: d)));
  }
}

/// Открыть перевозку сразу с машиной (из «Barcha kategoriyalar»).
/// «Yetkazib berish» plitkasi (24.11.2026, Sherzodbek): kichik mashinalar —
/// Damas, Labo, Porter (1 t gacha). Oqim o'sha «Yuk tashish», faqat model
/// tanlash shu mashinalar bilan boshlanadi. Narxi yo'q mashina serverdan
/// kelmaydi — hech biri bo'lmasa, oddiy «Yuk tashish» ochiladi.
const smallDeliveryMaxKg = 1000;

Future<void> openSmallDelivery(BuildContext context, TaxiPlace from) async {
  final d = FreightDraft(from);
  final q = await _catalog(d);
  final models = q.vehicles.where((v) => v.capacityKg <= smallDeliveryMaxKg).toList()
    ..sort((a, b) => a.capacityKg.compareTo(b.capacityKg));
  if (!context.mounted) return;
  if (models.isEmpty) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightBrandPage(from: from)));
    return;
  }
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightModelPage(draft: d, models: models)));
}

Future<void> openFreightWithVehicle(BuildContext context, TaxiPlace from, String code) async {
  final d = FreightDraft(from);
  final q = await _catalog(d);
  final v = q.vehicles.where((x) => x.code == code).firstOrNull;
  if (!context.mounted) return;
  if (v == null) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightBrandPage(from: from)));
    return;
  }
  d.vehicle = v;
  openAfterModel(context, d);
}

// ===================================================================== Y2

/// Y2 · 2/4 — модель выбранной марки, фильтр по тоннажу.
class FreightModelPage extends StatefulWidget {
  const FreightModelPage({super.key, required this.draft, required this.models});

  final FreightDraft draft;
  final List<FreightVehicle> models;

  @override
  State<FreightModelPage> createState() => _FreightModelPageState();
}

class _FreightModelPageState extends State<FreightModelPage> {
  String _filter = 'all';
  FreightVehicle? _picked;

  bool _pass(FreightVehicle v) => switch (_filter) {
        '1-2' => v.tonnes <= 2,
        '3-5' => v.tonnes > 2 && v.tonnes <= 5,
        '5+' => v.tonnes > 5,
        _ => true,
      };

  @override
  Widget build(BuildContext context) {
    final list = widget.models.where(_pass).toList();
    final p = _picked ?? (list.isEmpty ? null : list.first);
    return _Step(
      title: widget.models.first.brand,
      subtitle: 'freight.y2_sub'.tr(),
      button: p == null ? null : 'freight.continue_with'.tr(args: [p.name]),
      onButton: p == null
          ? null
          : () {
              widget.draft.vehicle = p;
              openAfterModel(context, widget.draft);
            },
      children: [
        Wrap(children: [
          for (final f in const ['all', '1-2', '3-5', '5+'])
            _chip(f == 'all' ? 'catalog.all'.tr() : '$f t', _filter == f, () => setState(() => _filter = f)),
        ]),
        for (final v in list) _TruckCard(v: v, selected: v == p, onTap: () => setState(() => _picked = v)),
      ],
    );
  }
}

// ===================================================================== Y3

/// Y3 · 3/4 — тип кузова. Кузова, которых нет у модели, — серые.
class FreightBodyPage extends StatefulWidget {
  const FreightBodyPage({super.key, required this.draft});

  final FreightDraft draft;

  @override
  State<FreightBodyPage> createState() => _FreightBodyPageState();
}

class _FreightBodyPageState extends State<FreightBodyPage> {
  late String? _body = widget.draft.body ?? widget.draft.vehicle!.bodyTypes.first;

  @override
  Widget build(BuildContext context) {
    final v = widget.draft.vehicle!;
    return _Step(
      title: v.name,
      subtitle: 'freight.y3_sub'.tr(),
      button: 'freight.continue_with'.tr(args: [bodyName(_body).toLowerCase()]),
      onButton: _body == null
          ? null
          : () {
              widget.draft.body = _body;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightCargoPage(draft: widget.draft)));
            },
      children: [
        Container(
          height: 110,
          decoration: BoxDecoration(color: AppPalette.brandSubtle, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: const Center(child: HIcon(Icons.local_shipping_outlined, color: AppPalette.iconBrand, size: 64)),
        ),
        const SizedBox(height: 12),
        for (final b in kBodyTypes)
          Builder(builder: (context) {
            final ok = v.bodyTypes.contains(b);
            return Opacity(
              opacity: ok ? 1 : .45,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: _body == b ? AppPalette.brandSubtle : AppPalette.surface,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: ListTile(
                  onTap: ok ? () => setState(() => _body = b) : null,
                  leading: const HIcon(Icons.local_shipping_outlined, color: AppPalette.iconSecondary),
                  trailing: HIcon(_body == b ? Icons.radio_button_checked : Icons.radio_button_off,
                      color: _body == b ? AppPalette.brand : AppPalette.iconSecondary),
                  title: Text(bodyName(b), style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(ok ? 'freight.body_${b}_hint'.tr() : 'freight.body_not_here'.tr(),
                      style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                ),
              ),
            );
          }),
      ],
    );
  }
}

// ============================================================= Y4 + Y7

/// Y4 · 4/4 — тип груза, вес, размеры, грузчик. Не влезает — Y7:
/// красное «Bu mashinaga sig'maydi» и подходящие варианты.
class FreightCargoPage extends StatefulWidget {
  const FreightCargoPage({super.key, required this.draft});

  final FreightDraft draft;

  @override
  State<FreightCargoPage> createState() => _FreightCargoPageState();
}

class _FreightCargoPageState extends State<FreightCargoPage> {
  final _kg = TextEditingController();
  final _l = TextEditingController();
  final _w = TextEditingController();
  final _h = TextEditingController();
  String _type = 'construction';
  bool _loader = false;
  String _loaderMode = 'hour';
  int _loaderHours = 1;
  double _loaderHourFee = 0, _loaderDayFee = 0;
  List<FreightVehicle> _all = const [];
  FreightVehicle? _alt;

  FreightDraft get d => widget.draft;

  @override
  void initState() {
    super.initState();
    _catalog(d).then((q) {
      if (mounted) {
        setState(() {
          _all = q.vehicles;
          _loaderHourFee = q.loaderHourFee;
          _loaderDayFee = q.loaderDayFee;
        });
      }
    }).catchError((_) {});
  }

  bool _fits(FreightVehicle v) =>
      v.fitsCargo(kg: _num(_kg), l: _num(_l), w: _num(_w), h: _num(_h));

  @override
  Widget build(BuildContext context) {
    final v = d.vehicle!;
    final ok = _fits(v);
    final hasData = _num(_kg) != null || _num(_l) != null;
    final alts = _all
        .where((x) => x.code != v.code && x.price != null || x.code != v.code)
        .where((x) => x.code != v.code && _fits(x) && (d.body == null || x.bodyTypes.contains(d.body)))
        .take(3)
        .toList();
    final next = ok ? v : _alt;
    return _Step(
      title: 'freight.y4_title'.tr(),
      subtitle: 'freight.y4_sub'.tr(),
      button: next == null
          ? 'freight.continue'.tr()
          : (ok ? 'freight.continue'.tr() : 'freight.continue_with'.tr(args: ['${next.name} · ${bodyName(d.body)}'])),
      onButton: !ok && _alt == null
          ? null
          : () {
              d.vehicle = next;
              d.cargoType = _type;
              d.weightKg = _num(_kg);
              d.length = _num(_l);
              d.width = _num(_w);
              d.height = _num(_h);
              d.loader = _loader;
              d.loaderMode = _loaderMode;
              d.loaderHours = _loaderHours;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightRoutePage(draft: d)));
            },
      children: [
        _section('freight.cargo_type'.tr()),
        Wrap(children: [
          for (final c in kCargoTypes) _chip('freight.cargo_$c'.tr(), _type == c, () => setState(() => _type = c)),
        ]),
        const SizedBox(height: 6),
        _field('freight.weight'.tr(), _kg, suffix: 'kg', error: hasData && !ok, onChanged: (_) => setState(() {})),
        _section('freight.dims'.tr()),
        Row(children: [
          Expanded(child: _field('freight.len'.tr(), _l, suffix: 'm', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: _field('freight.wid'.tr(), _w, suffix: 'm', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: _field('freight.hei'.tr(), _h, suffix: 'm', onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 12),
        if (hasData && ok)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.successSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('✓ ${'freight.fits'.tr(args: ['${v.name} ${bodyName(d.body).toLowerCase()}'])}',
                  style: const TextStyle(color: AppPalette.textSuccess, fontWeight: FontWeight.w600)),
              Text('freight.fits_hint'.tr(args: ['${_t(v.tonnes)} t', v.dims ?? '—']),
                  style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
            ]),
          ),
        if (hasData && !ok) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.dangerSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('freight.not_fit'.tr(), style: const TextStyle(color: AppPalette.textDanger, fontWeight: FontWeight.w600)),
              Text('freight.not_fit_hint'.tr(args: ['${v.name} ${bodyName(d.body).toLowerCase()}', '${_t(v.tonnes)} t', v.dims ?? '—']),
                  style: AppTypography.captionS.copyWith(color: AppPalette.textPrimary)),
            ]),
          ),
          _section('freight.alternatives'.tr()),
          if (alts.isEmpty)
            Text('freight.no_alternatives'.tr(), style: const TextStyle(color: AppPalette.textSecondary)),
          for (final a in alts)
            _TruckCard(
              v: a,
              title: '${a.name} · ${bodyName(d.body).toLowerCase()}',
              selected: _alt == a,
              onTap: () => setState(() => _alt = a),
            ),
        ],
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _loader,
          onChanged: (x) => setState(() => _loader = x),
          title: Text('freight.loader'.tr(), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('freight.loader_hint'.tr()),
        ),
        if (_loader) ...[
          Wrap(children: [
            _chip('freight.loader_hourly'.tr(args: [_sum(_loaderHourFee)]), _loaderMode == 'hour',
                () => setState(() => _loaderMode = 'hour')),
            _chip('freight.loader_daily'.tr(args: [_sum(_loaderDayFee)]), _loaderMode == 'day',
                () => setState(() => _loaderMode = 'day')),
          ]),
          if (_loaderMode == 'hour')
            Row(children: [
              Expanded(child: Text('freight.loader_hours'.tr(), style: const TextStyle(fontWeight: FontWeight.w600))),
              IconButton(
                onPressed: _loaderHours > 1 ? () => setState(() => _loaderHours--) : null,
                icon: const Icon(Icons.remove_circle_outline),
              ),
              Text('$_loaderHours', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              IconButton(
                onPressed: _loaderHours < 24 ? () => setState(() => _loaderHours++) : null,
                icon: const Icon(Icons.add_circle_outline),
              ),
            ]),
          Text(
            'freight.loader_total'.tr(args: [
              _sum(_loaderMode == 'day' ? _loaderDayFee : _loaderHourFee * _loaderHours),
            ]),
            style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary),
          ),
        ],
      ],
    );
  }
}

// ===================================================================== Y8

/// Y8 · «Menga farqi yo'q» — груз, вес, объём → подходящие машины по цене.
class FreightAutoPage extends StatefulWidget {
  const FreightAutoPage({super.key, required this.draft, required this.all});

  final FreightDraft draft;
  final List<FreightVehicle> all;

  @override
  State<FreightAutoPage> createState() => _FreightAutoPageState();
}

class _FreightAutoPageState extends State<FreightAutoPage> {
  final _kg = TextEditingController();
  final _m3 = TextEditingController();
  String _type = 'furniture';
  FreightVehicle? _picked;

  @override
  Widget build(BuildContext context) {
    final kg = _num(_kg), m3 = _num(_m3);
    final list = widget.all.where((v) => v.minPrice != null && v.fitsCargo(kg: kg, m3: m3)).toList()
      ..sort((a, b) => a.minPrice!.compareTo(b.minPrice!));
    final p = _picked != null && list.contains(_picked) ? _picked : (list.isEmpty ? null : list.first);
    return _Step(
      title: 'freight.y8_title'.tr(),
      subtitle: 'freight.y8_sub'.tr(),
      button: p == null ? null : 'freight.continue_with'.tr(args: ['${p.name} ${bodyName(bodyFor(_type, p.bodyTypes)).toLowerCase()}']),
      onButton: p == null
          ? null
          : () {
              final d = widget.draft
                ..vehicle = p
                ..body = bodyFor(_type, p.bodyTypes)
                ..cargoType = _type
                ..weightKg = kg
                ..volume = m3;
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightRoutePage(draft: d)));
            },
      children: [
        Wrap(children: [
          for (final c in const ['furniture', 'construction', 'food', 'other'])
            _chip('freight.cargo_$c'.tr(), _type == c, () => setState(() => _type = c)),
        ]),
        Row(children: [
          Expanded(child: _field('freight.weight'.tr(), _kg, suffix: 'kg', onChanged: (_) => setState(() {}))),
          const SizedBox(width: 8),
          Expanded(child: _field('freight.volume'.tr(), _m3, suffix: 'm³', onChanged: (_) => setState(() {}))),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.md)),
          child: Text('freight.y8_info'.tr(args: [bodyName(bodyFor(_type, kBodyTypes)).toLowerCase()]),
              style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
        ),
        _section('freight.matching'.tr(args: ['${list.length}'])),
        for (var i = 0; i < list.length; i++)
          _TruckCard(
            v: list[i],
            title: '${list[i].name} · ${bodyName(bodyFor(_type, list[i].bodyTypes)).toLowerCase()}',
            tag: i == 0 ? 'freight.cheapest'.tr() : null,
            selected: list[i] == p,
            onTap: () => setState(() => _picked = list[i]),
          ),
      ],
    );
  }
}

// ===================================================================== Y5

/// Y5 · Qayerdan — qayerga, когда, комментарий водителю.
class FreightRoutePage extends StatefulWidget {
  const FreightRoutePage({super.key, required this.draft});

  final FreightDraft draft;

  @override
  State<FreightRoutePage> createState() => _FreightRoutePageState();
}

class _FreightRoutePageState extends State<FreightRoutePage> {
  final _note = TextEditingController();
  String _when = 'now';
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  double? _km;

  FreightDraft get d => widget.draft;

  Future<void> _pick(bool from) async {
    final place = await Navigator.of(context).push<TaxiPlace>(
      MaterialPageRoute(builder: (_) => AddressPickPage(from: d.from, forSaving: true)),
    );
    if (place == null || !mounted) return;
    setState(() => from ? d.from = place : d.to = place);
    _distance();
  }

  Future<void> _distance() async {
    final to = d.to;
    if (to == null) return;
    try {
      final q = await FreightApi().quote(fromLat: d.from.lat, fromLon: d.from.lon, toLat: to.lat, toLon: to.lon);
      if (mounted) setState(() => _km = q.distanceKm);
    } catch (_) {}
  }

  DateTime? get _scheduled {
    if (_when == 'now') return null;
    final base = _when == 'today'
        ? DateTime.now()
        : _when == 'tomorrow'
            ? DateTime.now().add(const Duration(days: 1))
            : _date;
    return DateTime(base.year, base.month, base.day, _time.hour, _time.minute);
  }

  @override
  Widget build(BuildContext context) {
    final v = d.vehicle!;
    return _Step(
      title: 'freight.y5_title'.tr(),
      subtitle: '${v.name}${d.body == null ? '' : ' · ${bodyName(d.body).toLowerCase()}'}',
      button: 'freight.see_price'.tr(),
      onButton: d.to == null
          ? null
          : () {
              d.when = _scheduled;
              d.note = _note.text.trim().isEmpty ? null : _note.text.trim();
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => FreightConfirmPage(draft: d)));
            },
      children: [
        Container(
          decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Column(children: [
            ListTile(
              leading: const HIcon(Icons.radio_button_checked, color: AppPalette.brand),
              title: Text('freight.pickup'.tr(), style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
              subtitle: Text(d.from.address ?? d.from.label, style: const TextStyle(fontSize: 15, color: AppPalette.textPrimary)),
              onTap: () => _pick(true),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const HIcon(Icons.flag_outlined, color: AppPalette.iconPrimary),
              title: Text('freight.dropoff'.tr(), style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
              subtitle: Text(d.to == null ? 'freight.choose_address'.tr() : (d.to!.address ?? d.to!.label),
                  style: TextStyle(fontSize: 15, color: d.to == null ? AppPalette.textBrand : AppPalette.textPrimary)),
              onTap: () => _pick(false),
            ),
          ]),
        ),
        if (_km != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: AppPalette.brandSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Text('freight.route_line'.tr(args: [_t(double.parse(_km!.toStringAsFixed(1))), '${(_km! * 1.9 + 3).round()}']),
                style: AppTypography.captionS),
          ),
        ],
        _section('freight.when'.tr()),
        Wrap(children: [
          for (final w in const ['now', 'today', 'tomorrow', 'date'])
            _chip('freight.when_$w'.tr(), _when == w, () async {
              if (w == 'date') {
                final picked = await showDatePicker(
                  context: context,
                  firstDate: DateTime.now(),
                  lastDate: DateTime.now().add(const Duration(days: 60)),
                  initialDate: _date,
                );
                if (picked == null) return;
                _date = picked;
              }
              setState(() => _when = w);
            }),
        ]),
        if (_when != 'now')
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const HIcon(Icons.calendar_today_outlined, size: 18),
                label: Text(DateFormat('d-MMMM', context.locale.languageCode).format(_scheduled!)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final t = await showTimePicker(context: context, initialTime: _time);
                  if (t != null) setState(() => _time = t);
                },
                icon: const HIcon(Icons.schedule_rounded, size: 18),
                label: Text(_time.format(context)),
              ),
            ),
          ]),
        const SizedBox(height: 12),
        TextField(
          controller: _note,
          decoration: InputDecoration(
            labelText: 'freight.note_driver'.tr(),
            hintText: 'freight.note_driver_hint'.tr(),
            filled: true,
            fillColor: AppPalette.page,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.md), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}

// ===================================================================== Y6

/// Y6 · Narx va buyurtmani tasdiqlash.
class FreightConfirmPage extends StatefulWidget {
  const FreightConfirmPage({super.key, required this.draft});

  final FreightDraft draft;

  @override
  State<FreightConfirmPage> createState() => _FreightConfirmPageState();
}

class _FreightConfirmPageState extends State<FreightConfirmPage> {
  FreightQuote? _q;
  bool _sending = false;
  String? _error;

  FreightDraft get d => widget.draft;

  FreightVehicle? get _v => _q?.vehicles.where((x) => x.code == d.vehicle!.code).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final q = await FreightApi().quote(
        fromLat: d.from.lat,
        fromLon: d.from.lon,
        toLat: d.to!.lat,
        toLon: d.to!.lon,
        body: d.body,
        weightKg: d.weightKg,
        length: d.length,
        width: d.width,
        height: d.height,
        loader: d.loader,
        loaderMode: d.loaderMode,
        loaderHours: d.loaderHours,
      );
      if (mounted) setState(() => _q = q);
    } catch (_) {
      if (mounted) setState(() => _error = 'errors.something_went_wrong'.tr());
    }
  }

  Future<void> _send() async {
    final v = _v;
    if (v == null) return;
    setState(() => _sending = true);
    try {
      await FreightApi().create({
        'vehicle_code': v.code,
        if (d.body != null) 'body_type': d.body,
        if (d.cargoType != null) 'cargo_type': d.cargoType,
        if (d.weightKg != null) 'cargo_tonnes': d.weightKg! / 1000,
        if (d.length != null) 'cargo_length_m': d.length,
        if (d.width != null) 'cargo_width_m': d.width,
        if (d.height != null) 'cargo_height_m': d.height,
        if (d.volume != null) 'cargo_volume_m3': d.volume,
        'needs_loader': d.loader,
        if (d.loader) 'loader_mode': d.loaderMode,
        if (d.loader && d.loaderMode == 'hour') 'loader_hours': d.loaderHours,
        if (d.when != null) 'scheduled_at': d.when!.toUtc().toIso8601String(),
        if (d.note != null) 'cargo_note': d.note,
        'from_address': d.from.address ?? d.from.label,
        'from_latitude': d.from.lat,
        'from_longitude': d.from.lon,
        'to_address': d.to!.address ?? d.to!.label,
        'to_latitude': d.to!.lat,
        'to_longitude': d.to!.lon,
        if (v.hourly) 'hours': v.hours ?? v.minHours,
        'payment_method': d.cash ? 'cash' : 'balance',
      });
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FreightOrdersPage()));
    } on DioException catch (e) {
      final data = e.response?.data;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data is Map && data['detail'] is String ? data['detail'] as String : 'errors.something_went_wrong'.tr()),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(color: bold ? AppPalette.textPrimary : AppPalette.textSecondary,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
          const SizedBox(width: 12),
          Expanded(child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final v = _v;
    final q = _q;
    final km = q?.distanceKm ?? 0;
    final cargo = [
      if (d.cargoType != null) 'freight.cargo_${d.cargoType}'.tr(),
      if (d.weightKg != null) '${_t(d.weightKg!)} kg',
    ].join(' · ');
    final dims = d.length == null ? null : [d.length, d.width, d.height].whereType<double>().map(_t).join(' × ');
    final when = d.when == null
        ? 'freight.when_now'.tr()
        : DateFormat('d-MMMM, HH:mm', context.locale.languageCode).format(d.when!);
    return _Step(
      title: 'freight.y6_title'.tr(),
      button: v?.price == null ? null : 'freight.confirm'.tr(),
      accent: true,
      onButton: _sending || v?.price == null ? null : _send,
      children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: AppPalette.textDanger)),
        if (q == null && _error == null) const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
        if (v != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.brandSubtle, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Row(children: [
              const HIcon(Icons.local_shipping_outlined, color: AppPalette.iconBrand, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${v.name}${d.body == null ? '' : ' · ${bodyName(d.body).toLowerCase()}'}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${_t(v.tonnes)} t${v.dims == null ? '' : ' · ${v.dims} m'}',
                      style: AppTypography.captionS.copyWith(color: AppPalette.textSecondary)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(children: [
              _row('freight.cargo_route'.tr(), '', bold: true),
              if (cargo.isNotEmpty) _row('freight.cargo'.tr(), cargo),
              if (dims != null) _row('freight.dims_short'.tr(), '$dims m'),
              _row('freight.from'.tr(), d.from.address ?? d.from.label),
              _row('freight.to'.tr(), d.to!.address ?? d.to!.label),
              _row('freight.time'.tr(), when),
              _row('freight.distance'.tr(), '${_t(double.parse(km.toStringAsFixed(1)))} km'),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Column(children: [
              _row('freight.price'.tr(), '', bold: true),
              if (v.hourly)
                _row('freight.hours_n'.tr(args: ['${v.hours ?? v.minHours}']),
                    _sum((v.price ?? 0) - (d.loader ? q!.loaderFee : 0)))
              else ...[
                _row('freight.min_order'.tr(), _sum(v.baseFee)),
                if (v.pricePerKm != null)
                  _row('${_t(double.parse(km.toStringAsFixed(1)))} km × ${NumberFormatter.formatCurrency(v.pricePerKm!)} so\'m',
                      _sum((v.price ?? 0) - v.baseFee - (d.loader ? q!.loaderFee : 0))),
              ],
              _row(
                  d.loader
                      ? '${'freight.loader'.tr()} · ${d.loaderMode == 'day' ? 'freight.loader_day_short'.tr() : 'freight.hours_n'.tr(args: ['${d.loaderHours}'])}'
                      : 'freight.loader'.tr(),
                  d.loader ? _sum(q!.loaderFee) : '—'),
            ]),
          ),
          const SizedBox(height: 12),
          Wrap(children: [
            _chip('freight.pay_wallet'.tr(), !d.cash, () => setState(() => d.cash = false)),
            _chip('freight.pay_cash'.tr(), d.cash, () => setState(() => d.cash = true)),
          ]),
          Row(children: [
            Expanded(child: Text('freight.total'.tr(), style: AppTypography.h3)),
            Text(v.price == null ? 'freight.no_price'.tr() : _sum(v.price!), style: AppTypography.h2),
          ]),
        ],
      ],
    );
  }
}
