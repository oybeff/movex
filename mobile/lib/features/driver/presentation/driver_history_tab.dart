import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/driver_api.dart';
import 'driver_order_page.dart';
import 'driver_ui.dart';

/// «Buyurtmalar» — макет 02 O1/O2: «Faol», «Rejalashtirilgan», «Tarix»;
/// тап — живой заказ открывает исполнение, завершённый — чек (O3).
class DriverHistoryTab extends StatefulWidget {
  const DriverHistoryTab({super.key});

  @override
  State<DriverHistoryTab> createState() => _DriverHistoryTabState();
}

enum _Seg { active, scheduled, history }

class _DriverHistoryTabState extends State<DriverHistoryTab> {
  final _api = DriverApi();
  _Seg _seg = _Seg.active;
  List<DriverOrder> _orders = const [];
  Map<int, DriverEquipment> _eq = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await AuthService().getUserId();
      final orders = me == null ? <DriverOrder>[] : await _api.myOrders(me);
      final eq = await _api.myEquipment();
      if (!mounted) return;
      setState(() {
        _orders = orders..sort((a, b) => b.createdAt.compareTo(a.createdAt));
        _eq = eq;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<DriverOrder> get _list => switch (_seg) {
        _Seg.active => _orders.where((o) => o.active && !o.scheduled).toList(),
        _Seg.scheduled => _orders.where((o) => o.scheduled || o.status == 'pending').toList(),
        _Seg.history => _orders.where((o) => !o.active && o.status != 'pending').toList(),
      };

  Future<void> _open(DriverOrder o) async {
    if (o.active) {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DriverOrderPage(orderId: o.id, equipment: _eq[o.equipmentId]),
      ));
    } else {
      await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => DriverReceiptPage(order: o, equipment: _eq[o.equipmentId]),
      ));
    }
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final list = _list;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('driver.tab_orders'.tr(), style: AppTypography.h1),
              const SizedBox(height: 12),
              _Segments(
                value: _seg.index,
                labels: ['driver.seg_active'.tr(), 'driver.seg_scheduled'.tr(), 'driver.seg_history'.tr()],
                onChanged: (i) => setState(() => _seg = _Seg.values[i]),
              ),
              const SizedBox(height: 12),
              if (_loading)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('driver.no_orders'.tr(),
                      textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.textSecondary)),
                )
              else
                for (final o in list) ...[
                  _OrderCard(order: o, equipment: _eq[o.equipmentId], onTap: () => _open(o)),
                  const SizedBox(height: 10),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.value, required this.labels, required this.onChanged});

  final int value;
  final List<String> labels;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: AppPalette.borderDefault.withValues(alpha: .6), borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(i),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == value ? AppPalette.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(labels[i],
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: i == value ? FontWeight.w600 : FontWeight.w400,
                          color: i == value ? AppPalette.textPrimary : AppPalette.textSecondary,
                        )),
                  ),
                ),
              ),
          ],
        ),
      );
}

(String, Color, Color) statusChip(DriverOrder o) {
  if (o.status == 'completed') return ('driver.st_done'.tr(), AppPalette.successSubtle, AppPalette.textSuccess);
  if (o.status == 'cancelled' || o.status == 'rejected') {
    return (o.cancelledBy == 'owner' ? 'driver.st_you_cancelled'.tr() : 'driver.st_client_cancelled'.tr(),
        DChip.redBg, AppPalette.textDanger);
  }
  if (o.scheduled) return ('driver.scheduled'.tr(), DChip.blueBg, AppPalette.brand);
  if (o.finishedAt != null) return ('driver.step_3'.tr(), DChip.blueBg, AppPalette.brand);
  if (o.startedAt != null) return ('driver.step_2'.tr(), AppPalette.successSubtle, AppPalette.textSuccess);
  return ('driver.step_${o.departedAt != null ? 1 : 0}'.tr(), DChip.blueBg, AppPalette.brand);
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.equipment, required this.onTap});

  final DriverOrder order;
  final DriverEquipment? equipment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final lang = context.locale.languageCode;
    final (label, bg, fg) = statusChip(o);
    final when = o.startDate == null
        ? ''
        : '${DateFormat('d MMMM', lang).format(o.startDate!)}${o.startTime != null ? ', ${o.startTime}' : ''}';
    final done = o.status == 'completed';
    return Material(
      color: AppPalette.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(when, style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary))),
                  DChip(label, bg: bg, fg: fg),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: DChip.blueBg, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.construction_rounded, size: 20, color: AppPalette.brand),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderTitle(equipment?.type, o.tariff) +
                              (o.hours != null ? ' · ${'driver.hours_n'.tr(args: ['${o.hours}'])}' : ''),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                        ),
                        Text(o.address ?? '—',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      done ? '+${money(o.earning)}' : money(o.total),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: done ? AppPalette.textSuccess : AppPalette.textPrimary,
                      ),
                    ),
                  ),
                  Text(o.cash ? 'driver.pay_cash'.tr() : 'driver.pay_online'.tr(),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                  const Icon(Icons.chevron_right_rounded, size: 18, color: AppPalette.textSecondary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// O3 · «Buyurtma tafsiloti va chek».
class DriverReceiptPage extends StatelessWidget {
  const DriverReceiptPage({super.key, required this.order, this.equipment});

  final DriverOrder order;
  final DriverEquipment? equipment;

  @override
  Widget build(BuildContext context) {
    final o = order;
    final (label, bg, fg) = statusChip(o);
    final lang = context.locale.languageCode;
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(backgroundColor: AppPalette.page, title: Text('driver.order_n'.tr(args: ['${o.id}']))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DCard(
            child: Row(
              children: [
                Expanded(
                  child: Text(DateFormat('d MMMM, HH:mm', lang).format(o.createdAt),
                      style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                ),
                DChip(label, bg: bg, fg: fg),
              ],
            ),
          ),
          const SizedBox(height: 10),
          DCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('driver.address'.tr(), style: AppTypography.h3),
                const SizedBox(height: 8),
                DAddress(o.address),
              ],
            ),
          ),
          const SizedBox(height: 10),
          DCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('driver.receipt'.tr(), style: AppTypography.h3),
                const SizedBox(height: 6),
                DRow('driver.tariff'.tr(),
                    orderTitle(equipment?.type, o.tariff) + (o.hours != null ? ' · ${'driver.hours_n'.tr(args: ['${o.hours}'])}' : '')),
                DRow('driver.price'.tr(), money(o.total)),
                DRow('driver.payment'.tr(), o.cash ? 'driver.pay_cash'.tr() : 'driver.pay_online'.tr()),
                DRow('driver.commission'.tr(), '−${money(o.commission)}'),
                const Divider(),
                DRow('driver.your_earning'.tr(), o.status == 'completed' ? money(o.earning) : '—',
                    bold: true, valueColor: AppPalette.textSuccess),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
