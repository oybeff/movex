import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/equipment_types.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_sheets.dart';
import '../widgets/taxi_ui.dart';
import 'order_detail_page.dart';

/// M1 · Buyurtmalarim (faol), M2 · (tarix), B6 · пусто, B7 · загрузка.
///
/// Закрывается с [TaxiNav], если главной надо показать живой заказ или
/// заказать то же самое снова.
class OrdersPage extends StatefulWidget {
  const OrdersPage({super.key});

  @override
  State<OrdersPage> createState() => _OrdersPageState();
}

class _OrdersPageState extends State<OrdersPage> {
  final _api = TaxiService();
  List<OrderCard>? _cards; // null — B7, идёт загрузка
  bool _history = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // После первого кадра: _load читает context.locale и показывает
    // SnackBar, а из initState это падало (в debug список был всегда пуст).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load() async {
    try {
      final cards = await _api.clientCards(context.locale.languageCode);
      if (mounted) setState(() => _cards = cards);
    } catch (e) {
      if (!mounted) return;
      setState(() => _cards = const []);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    }
  }

  List<OrderCard> get _active => (_cards ?? const []).where((c) => c.isActive).toList();
  List<OrderCard> get _past {
    final l = (_cards ?? const <OrderCard>[]).where((c) => !c.isActive).toList();
    DateTime at(OrderCard c) => c.startAt ?? c.createdAt ?? DateTime(2000);
    l.sort((a, b) => at(b).compareTo(at(a)));
    return l;
  }

  Future<void> _cancel(OrderCard c) async {
    final reason = await confirmCancel(context);
    if (reason == null) return;
    setState(() => _busy = true);
    try {
      if (c.isRequest) {
        await _api.cancelRequest(c.requestId!, reason: reason);
      } else {
        await _api.setOrderStatus(c.orderId!, 'cancelled', reason: reason);
      }
      await _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(getErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openDetail(OrderCard c) async {
    if (c.isRequest) return;
    final nav = await Navigator.of(context).push<TaxiNav>(
      MaterialPageRoute(builder: (_) => OrderDetailPage(card: c)),
    );
    if (nav != null && mounted) Navigator.of(context).pop(nav);
  }

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    final list = _history ? _past : _active;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.my_orders'.tr()),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
              child: _Tabs(
                left: cards == null || _active.isEmpty
                    ? 'taxi.tab_active'.tr()
                    : 'taxi.tab_active_n'.tr(args: ['${_active.length}']),
                right: 'taxi.tab_history'.tr(),
                rightOn: _history,
                onChanged: (v) => setState(() => _history = v),
              ),
            ),
            Expanded(
              child: cards == null
                  ? const _Skeleton()
                  : list.isEmpty
                      ? _Empty(
                          // Tarixda buyurtma bor, faollari yo'q: «Hali buyurtma
                          // yo'q» yolg'on bo'lardi.
                          title: cards.isNotEmpty && !_history
                              ? 'taxi.no_active_orders_title'.tr()
                              : 'taxi.no_orders_title'.tr(),
                          onOrder: () => Navigator.of(context).popUntil((r) => r.isFirst),
                        )
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView(
                            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 24),
                            children: _history ? _historyList(list) : _activeList(list),
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _activeList(List<OrderCard> list) => [
        for (final c in list) ...[
          _CardView(
            card: c,
            subtitle: [
              if (c.startAt != null) taxiDate(c.startAt!, withTime: true),
              if (c.hours != null) 'taxi.hours_n'.tr(args: ['${c.hours}']),
            ].join(' · '),
            amount: c.total,
            action: c.stage == 'scheduled' || c.stage == 'searching'
                ? SmallButton('taxi.cancel'.tr(), ghost: true, onTap: _busy ? null : () => _cancel(c))
                : SmallButton('taxi.track'.tr(), onTap: () => Navigator.of(context).pop(const TaxiNav.track())),
            onTap: () => _openDetail(c),
          ),
          const SizedBox(height: 12),
        ],
      ];

  List<Widget> _historyList(List<OrderCard> list) {
    final out = <Widget>[];
    String? month;
    for (final c in list) {
      final d = c.startAt ?? c.createdAt ?? DateTime.now();
      final m = '${'taxi.month_name_${d.month}'.tr()} ${d.year}';
      if (m != month) {
        month = m;
        if (out.isNotEmpty) out.add(const SizedBox(height: 4));
        out
          ..add(GroupLabel(m))
          ..add(const SizedBox(height: 12));
      }
      final cancelled = c.stage == 'cancelled';
      out
        ..add(_CardView(
          card: c,
          subtitle: [
            taxiDate(d),
            cancelled ? 'taxi.cancelled_lower'.tr() : 'taxi.hours_n'.tr(args: ['${c.hours ?? ''}']),
          ].join(' · '),
          amount: cancelled ? 0 : c.total,
          action: cancelled
              ? null
              : SmallButton('taxi.repeat_short'.tr(),
                  onTap: () => Navigator.of(context).pop(TaxiNav.repeat(c.asRequest()))),
          onTap: () => _openDetail(c),
        ))
        ..add(const SizedBox(height: 12));
    }
    return out;
  }
}

/// Переключатель «Faol / Tarix» (фон #E4E8EE, активный — белый с тенью).
class _Tabs extends StatelessWidget {
  const _Tabs({required this.left, required this.right, required this.rightOn, required this.onChanged});

  final String left;
  final String right;
  final bool rightOn;
  final ValueChanged<bool> onChanged;

  Widget _tab(String t, bool on, VoidCallback onTap) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? AppPalette.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              boxShadow: on ? AppShadows.card : null,
            ),
            child: Text(
              t,
              style: TextStyle(
                fontFamily: AppTypography.fontFamily,
                fontSize: 14,
                height: 20 / 14,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                color: on ? AppPalette.textPrimary : AppPalette.textSecondary,
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: const Color(0xFFE4E8EE), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            _tab(left, !rightOn, () => onChanged(false)),
            const SizedBox(width: 4),
            _tab(right, rightOn, () => onChanged(true)),
          ],
        ),
      );
}

/// Карточка заказа M1/M2.
class _CardView extends StatelessWidget {
  const _CardView({
    required this.card,
    required this.subtitle,
    required this.amount,
    required this.action,
    required this.onTap,
  });

  final OrderCard card;
  final String subtitle;
  final double amount;
  final Widget? action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = [EquipmentTypes.label(card.type), if ((card.model ?? '').isNotEmpty) card.model!].join(' · ');
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(12)),
                    alignment: Alignment.center,
                    child: EquipmentPhoto(card.type, width: 44, height: 44, background: AppPalette.page),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: cardTitleStyle),
                        const SizedBox(height: 2),
                        Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: cardSubStyle),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  TaxiBadge.stage(card.stage),
                ],
              ),
              const SizedBox(height: 12),
              Container(height: 1, color: AppPalette.borderDefault),
              const SizedBox(height: 12),
              if ((card.fromAddress ?? '').isNotEmpty) ...[
                _Point('point_a', card.fromAddress!),
                const SizedBox(height: 6),
              ],
              _Point('point_b', card.toAddress ?? '—'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      "${formatSum(amount)} ${'common.currency'.tr()}",
                      style: const TextStyle(
                        fontFamily: AppTypography.fontFamily,
                        fontSize: 16,
                        height: 22 / 16,
                        fontWeight: FontWeight.w700,
                        color: AppPalette.textPrimary,
                      ),
                    ),
                  ),
                  if (action != null) action!,
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

const cardTitleStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 15,
  height: 20 / 15,
  fontWeight: FontWeight.w600,
  color: AppPalette.textPrimary,
);

const cardSubStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 13,
  height: 18 / 13,
  color: AppPalette.textSecondary,
);

class _Point extends StatelessWidget {
  const _Point(this.icon, this.text);

  final String icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          TaxiIcon(icon, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTypography.bodyM),
          ),
        ],
      );
}

/// B6 · Buyurtmalar yo'q.
class _Empty extends StatelessWidget {
  const _Empty({required this.title, required this.onOrder});

  final String title;
  final VoidCallback onOrder;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 24),
        children: [
          const SizedBox(height: 24),
          Center(
            child: Container(
              width: 112,
              height: 112,
              decoration: const BoxDecoration(color: Color(0x0F316DC8), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(color: AppPalette.brandSubtle, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const TaxiIcon('orders', size: 36),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(title, textAlign: TextAlign.center, style: AppTypography.h2),
          const SizedBox(height: 10),
          Text(
            'taxi.no_orders_body'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 15,
              height: 22 / 15,
              color: AppPalette.textSecondary,
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(onPressed: onOrder, child: Text('taxi.order_equipment'.tr())),
        ],
      );
}

/// B7 · Yuklanmoqda: три карточки-заглушки, каждая бледнее.
class _Skeleton extends StatelessWidget {
  const _Skeleton();

  Widget _bar(double w, double h, {double r = 6}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: const Color(0xFFE7EBF0), borderRadius: BorderRadius.circular(r)),
      );

  Widget _card(double opacity) => Opacity(
        opacity: opacity,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _bar(52, 52, r: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [_bar(150, 14), const SizedBox(height: 8), _bar(100, 12)],
                    ),
                  ),
                  _bar(64, 22, r: 11),
                ],
              ),
              const SizedBox(height: 12),
              _bar(220, 12),
              const SizedBox(height: 12),
              _bar(180, 12),
              const SizedBox(height: 12),
              _bar(110, 18),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 12, AppSpacing.gutter, 0),
        children: [_card(1), const SizedBox(height: 12), _card(.75), const SizedBox(height: 12), _card(.5)],
      );
}
