import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../../core/constants/equipment_types.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../data/taxi_service.dart';
import 'taxi_ui.dart';
import '../../data/card_api.dart';
import '../pages/card_bind_page.dart';
import '../../../../core/widgets/h_icon.dart';

/// Шторки потока «как такси»: время (6), навесное (5), оплата, отмена (E6),
/// и финальная панель (10).

Future<T?> _sheet<T>(BuildContext context, Widget child) => showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(child: child),
      ),
    );

Widget _sheetHeader(BuildContext context, String title, {String? subtitle}) => Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.lg, AppSpacing.md, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTypography.h2),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTypography.subtitle),
                ],
              ],
            ),
          ),
          Material(
            color: AppPalette.brandSubtle,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: () => Navigator.of(context).pop(),
              child: const SizedBox(
                width: 36,
                height: 36,
                child: HIcon(Icons.close_rounded, size: 20, color: AppPalette.iconBrand),
              ),
            ),
          ),
        ],
      ),
    );

// ------------------------------------------------------------ 6 · Vaqt

class ScheduleResult {
  ScheduleResult(this.hours, this.at, this.comment);

  final int hours;

  /// null — «Hozir».
  final DateTime? at;
  final String? comment;
}

Future<ScheduleResult?> showScheduleSheet(
  BuildContext context, {
  required TaxiService api,
  required String type,
  required String tier,
  required int minHours,
  required int hours,
  DateTime? scheduledAt,
  String? comment,
  int? attachmentId,
}) =>
    _sheet<ScheduleResult>(
      context,
      _ScheduleSheet(
        api: api,
        type: type,
        tier: tier,
        minHours: minHours,
        hours: hours,
        scheduledAt: scheduledAt,
        comment: comment,
        attachmentId: attachmentId,
      ),
    );

class _ScheduleSheet extends StatefulWidget {
  const _ScheduleSheet({
    required this.api,
    required this.type,
    required this.tier,
    required this.minHours,
    required this.hours,
    required this.scheduledAt,
    required this.comment,
    required this.attachmentId,
  });

  final TaxiService api;
  final String type;
  final String tier;
  final int minHours;
  final int hours;
  final DateTime? scheduledAt;
  final String? comment;
  final int? attachmentId;

  @override
  State<_ScheduleSheet> createState() => _ScheduleSheetState();
}

class _ScheduleSheetState extends State<_ScheduleSheet> {
  late bool _now = widget.scheduledAt == null;
  late DateTime _at = widget.scheduledAt ??
      DateTime.now().add(const Duration(days: 1)).copyWith(hour: 8, minute: 0);
  late int _hours = widget.hours;
  late final _comment = TextEditingController(text: widget.comment ?? '');
  double? _price;

  @override
  void initState() {
    super.initState();
    _refreshPrice();
  }

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  /// «Taxminiy narx» — тоже с сервера, по той же формуле, что и заказ.
  Future<void> _refreshPrice() async {
    try {
      final q = await widget.api.tariffs(widget.type, hours: _hours, attachmentId: widget.attachmentId);
      final mine = q.where((x) => x.tier == widget.tier).firstOrNull;
      if (mounted) setState(() => _price = mine?.total);
    } catch (_) {}
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _at,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 60)),
    );
    if (d != null) setState(() => _at = _at.copyWith(year: d.year, month: d.month, day: d.day));
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_at));
    if (t != null) setState(() => _at = _at.copyWith(hour: t.hour, minute: t.minute));
  }

  String get _dateText {
    final today = DateTime.now();
    final tomorrow = today.add(const Duration(days: 1));
    bool same(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
    if (same(_at, today)) return 'taxi.today'.tr();
    if (same(_at, tomorrow)) return 'taxi.tomorrow'.tr();
    return '${_at.day.toString().padLeft(2, '0')}.${_at.month.toString().padLeft(2, '0')}.${_at.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetHeader(context, 'taxi.when_title'.tr()),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: _Segmented(
            items: ['taxi.now'.tr(), 'taxi.schedule'.tr()],
            index: _now ? 0 : 1,
            onChanged: (i) => setState(() => _now = i == 0),
          ),
        ),
        if (!_now) ...[
          const SizedBox(height: AppSpacing.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
            child: Row(
              children: [
                Expanded(child: _PickBox(label: 'taxi.date'.tr(), value: _dateText, onTap: _pickDate)),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _PickBox(
                    label: 'taxi.time'.tr(),
                    value: '${_at.hour.toString().padLeft(2, '0')}:${_at.minute.toString().padLeft(2, '0')}',
                    onTap: _pickTime,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('taxi.work_time'.tr(), style: AppTypography.bodyMedium),
                    Text('taxi.min_hours'.tr(args: ['${widget.minHours}']), style: AppTypography.captionS),
                  ],
                ),
              ),
              _StepButton(
                icon: Icons.remove_rounded,
                onTap: _hours > widget.minHours
                    ? () {
                        setState(() => _hours--);
                        _refreshPrice();
                      }
                    : null,
              ),
              SizedBox(
                width: 72,
                child: Text(
                  'taxi.hours_n'.tr(args: ['$_hours']),
                  textAlign: TextAlign.center,
                  style: AppTypography.h3,
                ),
              ),
              _StepButton(
                icon: Icons.add_rounded,
                onTap: _hours < 24
                    ? () {
                        setState(() => _hours++);
                        _refreshPrice();
                      }
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: TextField(
            controller: _comment,
            maxLength: 500,
            decoration: InputDecoration(labelText: 'taxi.comment'.tr(), counterText: ''),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: Row(
            children: [
              Text('taxi.approx_price'.tr(), style: AppTypography.subtitle),
              const Spacer(),
              Text(
                _price == null ? '—' : "${formatSum(_price!)} ${'common.currency'.tr()}",
                style: AppTypography.h3,
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 0, AppSpacing.gutter, AppSpacing.md),
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              ScheduleResult(_hours, _now ? null : _at, _comment.text.trim()),
            ),
            child: Text('taxi.save'.tr()),
          ),
        ),
      ],
    );
  }
}

/// Segmented Control из Design System: серая подложка, активный — белый.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.items, required this.index, required this.onChanged});

  final List<String> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? AppPalette.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: i == index ? AppShadows.xs : null,
                  ),
                  child: Text(
                    items[i],
                    style: AppTypography.bodyMMedium.copyWith(
                      color: i == index ? AppPalette.textPrimary : AppPalette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PickBox extends StatelessWidget {
  const _PickBox({required this.label, required this.value, required this.onTap});

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Container(
          height: AppSpacing.fieldHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTypography.captionS),
                    Text(value, style: AppTypography.bodyMedium),
                  ],
                ),
              ),
              const TaxiIcon('chevron_down', size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppPalette.page,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: HIcon(icon, color: onTap == null ? AppPalette.textDisabled : AppPalette.iconPrimary),
        ),
      ),
    );
  }
}

// ------------------------------------------------- 5 · Qo'shimcha jihoz

/// Возвращает выбранное навесное; id 0 — «без навесного».
Future<TaxiAttachment?> showAttachmentSheet(
  BuildContext context, {
  required String typeLabel,
  required List<TaxiAttachment> items,
  TaxiAttachment? selected,
}) =>
    _sheet<TaxiAttachment>(
      context,
      _AttachmentSheet(typeLabel: typeLabel, items: items, selected: selected),
    );

class _AttachmentSheet extends StatefulWidget {
  const _AttachmentSheet({required this.typeLabel, required this.items, this.selected});

  final String typeLabel;
  final List<TaxiAttachment> items;
  final TaxiAttachment? selected;

  @override
  State<_AttachmentSheet> createState() => _AttachmentSheetState();
}

class _AttachmentSheetState extends State<_AttachmentSheet> {
  late int _id = widget.selected?.id ?? _defaultId();

  /// В макете первой строкой идёт навесное с нулевой ценой («Narxga
  /// kiritilgan») — оно и есть «без доплаты», а последней «Boshqa» для
  /// того, чего нет в списке. Своей строки «Jihozsiz» в макете нет, и её
  /// заменяет «Boshqa» с тем же id 0: заказ уходит без навесного, а что
  /// нужно — человек пишет в изохе.
  int _defaultId() {
    for (final a in widget.items) {
      if (a.pricePerHour <= 0) return a.id;
    }
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final other = TaxiAttachment(id: 0, name: 'taxi.attachment_other'.tr(), pricePerHour: 0);
    final all = [...widget.items, other];
    final picked = all.firstWhere((a) => a.id == _id, orElse: () => other);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sheetHeader(
            context,
            'taxi.attachment_title'.tr(),
            subtitle: 'taxi.attachment_hint'.tr(args: [widget.typeLabel]),
          ),
          const SizedBox(height: AppSpacing.sm),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final a in all)
                  InkWell(
                    onTap: () => setState(() => _id = a.id),
                    child: Container(
                      color: a.id == _id ? AppPalette.brandSubtle : null,
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter, vertical: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: a.id == _id ? AppPalette.surface : AppPalette.page,
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            alignment: Alignment.center,
                            child: a.id == 0
                                ? const HIcon(Icons.add_circle_outline, size: 20, color: AppPalette.textPrimary)
                                : const TaxiIcon('bucket', size: 20),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(a.name, style: AppTypography.bodyMedium),
                                Text(
                                  a.id == 0
                                      ? 'taxi.attachment_other_hint'.tr()
                                      : a.pricePerHour > 0
                                          ? "+${formatSum(a.pricePerHour)} ${'common.currency'.tr()}/${'taxi.hour_short'.tr()}"
                                          : 'taxi.included'.tr(),
                                  style: AppTypography.captionS,
                                ),
                              ],
                            ),
                          ),
                          HIcon(
                            a.id == _id ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                            color: a.id == _id ? AppPalette.brand : AppPalette.borderStrong,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.gutter),
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(picked),
              child: Text('${'taxi.choose'.tr()} · ${picked.name}', maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------ K1 · оплата

/// «To'lov usuli» (макет K1, K6). Результат: 'cash', 'balance' или
/// `card:<id>`. «Bank kartasini qo'shish» открывает форму Multicard и сразу
/// выбирает новую карту (K6).
Future<String?> showPaymentSheet(BuildContext context, {required String selected, bool cardsOnly = false}) =>
    _sheet<String>(context, _PaymentSheet(selected: selected, cardsOnly: cardsOnly));

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.selected, this.cardsOnly = false});

  final String selected;

  /// E7 «Boshqa karta tanlash»: только карты.
  final bool cardsOnly;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late String _m = widget.selected;
  List<BankCard> _cards = const [];
  int? _newCard;
  double _deposit = 0; // залог за наличные, с сервера

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await CardApi().list();
      if (mounted) setState(() => _cards = c);
    } catch (_) {}
    try {
      final d = await TaxiService().cashDeposit();
      if (mounted) setState(() => _deposit = d);
    } catch (_) {}
  }

  Future<void> _add() async {
    final c = await addBankCard(context);
    if (c == null || !mounted) return;
    await _load();
    setState(() {
      _m = 'card:${c.id}';
      _newCard = c.id;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('taxi.card_added'.tr())));
    }
  }

  Widget _option(String code, Widget icon, String title, String subtitle) {
    final on = _m == code;
    return InkWell(
      onTap: () => setState(() => _m = code),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: on ? AppPalette.brandSubtle : null,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: on ? AppPalette.surface : AppPalette.page,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.bodyMedium),
                  Text(subtitle, style: AppTypography.captionS.copyWith(fontSize: 13)),
                ],
              ),
            ),
            on
                ? const TaxiIcon('radio_on', size: 22)
                : Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFFC9D0D9), width: 2),
                    ),
                  ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sheetHeader(context, 'taxi.payment_title'.tr()),
        const SizedBox(height: AppSpacing.md),
        if (!widget.cardsOnly)
          _option('cash', const TaxiIcon('cash', size: 24), 'taxi.pay_cash_full'.tr(),
              _deposit > 0 ? 'taxi.pay_cash_deposit_hint'.tr(args: [formatSum(_deposit)]) : 'taxi.pay_cash_hint'.tr()),
        for (final c in _cards)
          _option(
            'card:${c.id}',
            const TaxiIcon('menu_card', size: 22),
            c.label,
            c.id == _newCard
                ? 'taxi.card_new'.tr()
                : (c.isDefault ? 'taxi.card_main'.tr() : 'taxi.bank_card'.tr()),
          ),
        if (!widget.cardsOnly)
          _option(
            'balance',
            const HIcon(Icons.account_balance_wallet_outlined, color: AppPalette.iconPrimary),
            'taxi.pay_balance'.tr(),
            'taxi.pay_balance_hint'.tr(),
          ),
        InkWell(
          onTap: _add,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration:
                      BoxDecoration(color: AppPalette.brandSubtle, borderRadius: BorderRadius.circular(AppRadius.md)),
                  alignment: Alignment.center,
                  child: const TaxiIcon('plus_brand', size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'taxi.add_card'.tr(),
                    style: AppTypography.bodyMedium.copyWith(color: AppPalette.textBrand, fontWeight: FontWeight.w600),
                  ),
                ),
                const TaxiIcon('chevron_right', size: 18),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, AppSpacing.sm, AppSpacing.gutter, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.only(top: 1), child: TaxiIcon('lock', size: 14)),
              const SizedBox(width: 6),
              Expanded(child: Text('taxi.card_note'.tr(), style: AppTypography.captionS)),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: ElevatedButton(
            onPressed: widget.cardsOnly && !_m.startsWith('card:') ? null : () => Navigator.of(context).pop(_m),
            child: Text('taxi.done'.tr()),
          ),
        ),
      ],
    );
  }
}

/// T5 · Mablag' yetarli emas (холд при заказе не прошёл). true — выбрать
/// другую карту, false — платить наличными.
Future<bool?> showInsufficientFunds(BuildContext context, {required String cardLabel, required num amount}) =>
    showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: const BoxDecoration(color: AppPalette.dangerSubtle, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: const TaxiIcon('alert', size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('taxi.funds_title'.tr(), style: AppTypography.h3),
                        Text(cardLabel, style: AppTypography.subtitle),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text('taxi.funds_body'.tr(args: [formatSum(amount)]), style: AppTypography.subtitle),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('taxi.other_card'.tr())),
              const SizedBox(height: 12),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.brandSubtle,
                    foregroundColor: AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: Text('taxi.pay_cash_instead'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// E7 · To'lov o'tmadi (после работы). 'card' / 'cash' / 'retry'.
Future<String?> showPaymentFailed(BuildContext context, {String? cardLabel, required num amount}) =>
    showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      isDismissible: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: AppPalette.dangerSubtle, borderRadius: BorderRadius.circular(12)),
                  alignment: Alignment.center,
                  child: const TaxiIcon('alert', size: 22),
                ),
              ),
              const SizedBox(height: 12),
              Text('taxi.pay_failed_title'.tr(), style: AppTypography.h2),
              const SizedBox(height: 10),
              Text(cardLabel == null
                  ? 'taxi.pay_failed_body_any'.tr(args: [formatSum(amount)])
                  : 'taxi.pay_failed_body'.tr(args: [cardLabel, formatSum(amount)]), style: AppTypography.subtitle),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop('card'), child: Text('taxi.other_card'.tr())),
              const SizedBox(height: 12),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop('cash'),
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.brandSubtle,
                    foregroundColor: AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: Text('taxi.pay_cash_short'.tr()),
                ),
              ),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop('retry'),
                  style: TextButton.styleFrom(foregroundColor: AppPalette.textBrand, textStyle: AppTypography.buttonLarge),
                  child: Text('taxi.retry'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

/// Код из SMS для заморозки суммы на карте (если банк спросил код).
Future<String?> askCardOtp(BuildContext context) {
  final c = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppPalette.surface,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.gutter),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('taxi.sms_title'.tr(), style: AppTypography.h2),
              const SizedBox(height: 8),
              Text('taxi.sms_hold_body'.tr(), style: AppTypography.subtitle),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(counterText: ''),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(c.text.trim()), child: Text('taxi.confirm'.tr())),
            ],
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------ B3 · Vaqtni uzaytirish

/// Сколько часов добавить (макет B3). Цена часа — цена часа текущего
/// заказа, её же возьмёт сервер. [plannedEnd] — когда работа закончилась
/// бы без продления («13:30 → 15:30»).
Future<int?> showExtendSheet(
  BuildContext context, {
  required double perHour,
  required double currentTotal,
  DateTime? plannedEnd,
}) =>
    showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(
        child: _ExtendSheet(perHour: perHour, currentTotal: currentTotal, plannedEnd: plannedEnd),
      ),
    );

class _ExtendSheet extends StatefulWidget {
  const _ExtendSheet({required this.perHour, required this.currentTotal, this.plannedEnd});

  final double perHour;
  final double currentTotal;
  final DateTime? plannedEnd;

  @override
  State<_ExtendSheet> createState() => _ExtendSheetState();
}

class _ExtendSheetState extends State<_ExtendSheet> {
  int _h = 2;

  static String _hm(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  Widget _square(String icon, VoidCallback? onTap) => Material(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(width: 44, height: 44, child: Center(child: TaxiIcon(icon, size: 20))),
        ),
      );

  Widget _chip(int h) {
    final on = h == _h;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _h = h),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppPalette.brandSubtle : AppPalette.page,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: on ? AppPalette.brand : Colors.transparent, width: 1.5),
          ),
          child: Text(
            '+${'taxi.hours_n'.tr(args: ['$h'])}',
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 14,
              height: 20 / 14,
              fontWeight: FontWeight.w600,
              color: on ? AppPalette.textBrand : AppPalette.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final extra = widget.perHour * _h;
    final end = widget.plannedEnd;
    const secondary = TextStyle(
      fontFamily: AppTypography.fontFamily,
      fontSize: 13,
      height: 18 / 13,
      color: AppPalette.textSecondary,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFD3D8DF), borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 12),
          Text('taxi.extend'.tr(), style: AppTypography.h2),
          const SizedBox(height: 12),
          Text('taxi.extend_hint'.tr(), style: AppTypography.subtitle),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
            child: Row(
              children: [
                _square('minus', _h > 1 ? () => setState(() => _h--) : null),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        '+${'taxi.hours_n'.tr(args: ['$_h'])}',
                        style: const TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 22,
                          height: 28 / 22,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.textPrimary,
                        ),
                      ),
                      if (end != null)
                        Text('${_hm(end)} → ${_hm(end.add(Duration(hours: _h)))}', style: secondary),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _square('plus', _h < 12 ? () => setState(() => _h++) : null),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [_chip(1), const SizedBox(width: 8), _chip(2), const SizedBox(width: 8), _chip(4)]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Text(
                  "${'taxi.hours_n'.tr(args: ['$_h'])} × ${formatSum(widget.perHour)}",
                  style: AppTypography.subtitle,
                ),
              ),
              Text("${formatSum(extra)} ${'common.currency'.tr()}", style: AppTypography.bodyMMedium),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text('taxi.new_total'.tr(),
                    style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600, height: 20 / 16)),
              ),
              Text(
                "${formatSum(widget.currentTotal + extra)} ${'common.currency'.tr()}",
                style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700, height: 20 / 16),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(_h),
            child: Text('taxi.send_request'.tr()),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ------------------------------------------------ B1 · egasi bekor qildi

/// true — «Boshqa texnika qidirish», false — «Buyurtmani bekor qilish».
Future<bool?> showOwnerCancelledDialog(BuildContext context) => showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x730B1220),
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: Color(0xFFFDECEC), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const TaxiIcon('close', size: 28),
                ),
              ),
              const SizedBox(height: 10),
              Text('taxi.owner_cancelled_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h3),
              const SizedBox(height: 10),
              Text('taxi.owner_cancelled_body'.tr(), textAlign: TextAlign.center, style: AppTypography.subtitle),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text('taxi.search_other'.tr()),
              ),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                  ),
                  child: Text('taxi.cancel_order'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );

// ---------------------------------------------------------- E6 · отмена

/// E6 · Bekor qilishni tasdiqlash. [departed] — техника уже выехала.
/// Штрафа за отмену в проекте нет, поэтому про него не пишем.
/// E6. Возвращает выбранную причину (plans, long_wait, wrong_address,
/// other) или null — «Kutishda davom etish».
Future<String?> confirmCancel(BuildContext context, {bool departed = false}) => showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => SafeArea(child: _CancelSheet(departed: departed)),
    );

class _CancelSheet extends StatefulWidget {
  const _CancelSheet({required this.departed});

  final bool departed;

  @override
  State<_CancelSheet> createState() => _CancelSheetState();
}

class _CancelSheetState extends State<_CancelSheet> {
  static const _reasons = ['plans', 'long_wait', 'wrong_address', 'other'];
  String _reason = 'plans';

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(color: const Color(0xFFD3D8DF), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Text('taxi.cancel_title'.tr(), style: AppTypography.h2),
            const SizedBox(height: 12),
            Text(
              widget.departed ? 'taxi.cancel_body_departed'.tr() : 'taxi.cancel_body'.tr(),
              style: AppTypography.subtitle,
            ),
            const SizedBox(height: 8),
            for (final r in _reasons)
              InkWell(
                onTap: () => setState(() => _reason = r),
                child: SizedBox(
                  height: 48,
                  child: Row(
                    children: [
                      Expanded(child: Text('taxi.cancel_reason_$r'.tr(), style: AppTypography.bodyMedium)),
                      r == _reason
                          ? const TaxiIcon('radio_on', size: 22)
                          : Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFFC9D0D9), width: 2),
                              ),
                            ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('taxi.keep_waiting'.tr()),
            ),
            SizedBox(
              height: AppSpacing.buttonHeight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(_reason),
                style: TextButton.styleFrom(
                  foregroundColor: AppPalette.textDanger,
                  textStyle: AppTypography.buttonLarge,
                ),
                child: Text('taxi.yes_cancel'.tr()),
              ),
            ),
          ],
        ),
      );
}

// --------------------------------------------------- 10 · Ish yakunlandi

class DonePanel extends StatefulWidget {
  const DonePanel({
    super.key,
    required this.order,
    required this.request,
    required this.owner,
    required this.type,
    required this.onFinish,
  });

  final Map<String, dynamic>? order;
  final TaxiRequest? request;
  final Map<String, dynamic>? owner;
  final String? type;
  final Future<void> Function(int rating, String comment) onFinish;

  @override
  State<DonePanel> createState() => _DonePanelState();
}

class _DonePanelState extends State<DonePanel> {
  int _rating = 0;
  final _comment = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order ?? const {};
    final total = (o['total_amount'] as num?) ?? widget.request?.budget ?? 0;
    final hours = (o['hours'] ?? widget.request?.hours ?? 0) as int;
    final tier = (o['tariff'] ?? widget.request?.tariff ?? 'econom') as String;
    final method = (o['payment_method'] ?? widget.request?.paymentMethod) as String?;
    final cash = method == 'cash';
    // Цена часа тарифа — без навесного: оно идёт своей строкой. Раньше
    // «Tezkor · 400 000/soat» включало гидромолот 80 000.
    final att = widget.request?.attachmentPrice ?? 0;
    final perHour = hours > 0 ? total / hours - att : total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(color: AppPrimitives.green500, shape: BoxShape.circle),
            child: const HIcon(Icons.check_rounded, color: Colors.white, size: 32),
          ).animate().scale(begin: const Offset(.4, .4), duration: 600.ms, curve: Curves.elasticOut),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('taxi.done_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h2),
        Text(
          [
            EquipmentTypes.label(widget.type),
            if (widget.owner?['full_name'] != null) widget.owner!['full_name'] as String,
            if (DateTime.tryParse('${o['start_date']}') != null)
              taxiDate(DateTime.parse('${o['start_date']}')),
          ].join(' · '),
          textAlign: TextAlign.center,
          style: AppTypography.subtitle,
        ),
        const SizedBox(height: AppSpacing.lg),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Column(
            children: [
              InfoRow('taxi.tariff'.tr(),
                  "${'taxi.tier_$tier'.tr()} · ${formatSum(perHour)} ${'common.currency'.tr()}/${'taxi.hour_short'.tr()}"),
              InfoRow('taxi.work_time'.tr(), 'taxi.hours_n'.tr(args: ['$hours'])),
              if (att > 0)
                InfoRow('taxi.attachment'.tr(),
                    "${formatSum(att * hours)} ${'common.currency'.tr()}"),
              InfoRow(
                'taxi.delivery'.tr(),
                ((o['delivery_fee'] as num?) ?? 0) > 0
                    ? "${formatSum(o['delivery_fee'] as num)} ${'common.currency'.tr()}"
                    : 'taxi.free'.tr(),
              ),
              const Divider(height: 16),
              InfoRow('taxi.total'.tr(), "${formatSum(total)} ${'common.currency'.tr()}", bold: true),
              InfoRow(
                'taxi.payment'.tr(),
                cash
                    ? 'taxi.pay_cash_done'.tr()
                    : method == 'card'
                        ? 'taxi.pay_card_done'.tr()
                        : 'taxi.pay_balance_done'.tr(),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('taxi.rate_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h3),
        const SizedBox(height: AppSpacing.sm),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                onPressed: () => setState(() => _rating = i),
                icon: HIcon(
                  i <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 36,
                  color: i <= _rating ? AppPalette.accent : AppPalette.borderDefault,
                ),
              ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: TextField(
            controller: _comment,
            maxLength: 1000,
            decoration: InputDecoration(labelText: 'taxi.feedback'.tr(), counterText: ''),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: ElevatedButton(
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await widget.onFinish(_rating, _comment.text.trim());
                  },
            child: Text('taxi.finish'.tr()),
          ),
        ),
      ],
    );
  }
}
