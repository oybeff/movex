import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/driver_api.dart';
import 'driver_ui.dart';

/// «Daromad» — макет 04 P1: сколько можно вывести и кнопка «Pul yechish»,
/// заработок за день / неделю / месяц со столбиками, последние транзакции.
///
/// Заработок — по завершённым заказам: сумма минус комиссия, ровно то,
/// что сервер зачисляет владельцу.
class DriverEarningsTab extends StatefulWidget {
  const DriverEarningsTab({super.key});

  @override
  State<DriverEarningsTab> createState() => _DriverEarningsTabState();
}

enum _Period { day, week, month }

class _DriverEarningsTabState extends State<DriverEarningsTab> {
  final _api = DriverApi();
  _Period _period = _Period.week;
  List<DriverOrder> _done = const [];
  Map<String, dynamic>? _balance;
  List<Map<String, dynamic>> _tx = const [];
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
      final bal = await _api.balance();
      List<Map<String, dynamic>> tx = const [];
      try {
        tx = await _api.transactions();
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _done = orders.where((o) => o.status == 'completed').toList();
        _balance = bal;
        _tx = tx;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  DateTime get _from {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.day => today,
      _Period.week => today.subtract(Duration(days: today.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
    };
  }

  /// День — по 4 часа (6 столбиков), неделя — 7 дней, месяц — по неделям.
  List<double> _bars(List<DriverOrder> list) {
    final from = _from;
    switch (_period) {
      case _Period.day:
        final b = List<double>.filled(6, 0);
        for (final o in list) {
          b[(o.updatedAt.hour ~/ 4).clamp(0, 5)] += o.earning;
        }
        return b;
      case _Period.week:
        final b = List<double>.filled(7, 0);
        for (final o in list) {
          b[o.updatedAt.difference(from).inDays.clamp(0, 6)] += o.earning;
        }
        return b;
      case _Period.month:
        final b = List<double>.filled(5, 0);
        for (final o in list) {
          b[((o.updatedAt.day - 1) ~/ 7).clamp(0, 4)] += o.earning;
        }
        return b;
    }
  }

  String _barLabel(int i, String lang) => switch (_period) {
        _Period.day => '${i * 4}',
        _Period.week => DateFormat.E(lang).format(_from.add(Duration(days: i))),
        _Period.month => '${i * 7 + 1}',
      };

  double _n(String k) => (_balance?[k] as num?)?.toDouble() ?? double.tryParse('${_balance?[k]}') ?? 0;

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final list = _done.where((o) => !o.updatedAt.isBefore(_from)).toList();
    final total = list.fold<double>(0, (s, o) => s + o.earning);
    final hours = list.fold<int>(0, (s, o) => s + (o.hours ?? 0));
    final bars = _bars(list);
    final maxBar = bars.fold<double>(0, (m, v) => v > m ? v : m);
    final peak = maxBar <= 0 ? -1 : bars.indexOf(maxBar);
    final withdrawable = (_n('balance') - _n('frozen_balance') - _n('bonus_balance')).clamp(0, double.infinity);

    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('driver.tab_earnings'.tr(), style: AppTypography.h1),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: const LinearGradient(colors: [Color(0xFF162438), Color(0xFF2A5DAB)]),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('driver.withdrawable_label'.tr(), style: const TextStyle(fontSize: 13, color: Colors.white70)),
                    const SizedBox(height: 2),
                    Text(money(withdrawable),
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white)),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('driver.balance'.tr(), style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              Text(money(_n('balance')), style: const TextStyle(fontSize: 14, color: Colors.white)),
                            ],
                          ),
                        ),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: AppPalette.accent,
                            foregroundColor: AppPalette.textPrimary,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            textStyle: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: () async {
                            await context.push('/payout');
                            _load();
                          },
                          child: Text('driver.withdraw'.tr()),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<_Period>(
                segments: [
                  ButtonSegment(value: _Period.day, label: Text('driver.today'.tr())),
                  ButtonSegment(value: _Period.week, label: Text('driver.week'.tr())),
                  ButtonSegment(value: _Period.month, label: Text('driver.month'.tr())),
                ],
                selected: {_period},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _period = s.first),
              ),
              const SizedBox(height: 12),
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('driver.period_${_period.name}'.tr(),
                        style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                    Text(money(total), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 150,
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : BarChart(
                              BarChartData(
                                maxY: maxBar <= 0 ? 1 : maxBar * 1.15,
                                gridData: const FlGridData(show: false),
                                borderData: FlBorderData(show: false),
                                barTouchData: BarTouchData(enabled: false),
                                titlesData: FlTitlesData(
                                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  bottomTitles: AxisTitles(
                                    sideTitles: SideTitles(
                                      showTitles: true,
                                      reservedSize: 22,
                                      getTitlesWidget: (v, _) => Text(_barLabel(v.toInt(), lang),
                                          style: const TextStyle(fontSize: 11, color: AppPalette.textSecondary)),
                                    ),
                                  ),
                                ),
                                barGroups: [
                                  for (var i = 0; i < bars.length; i++)
                                    BarChartGroupData(x: i, barRods: [
                                      BarChartRodData(
                                        toY: bars[i] <= 0 ? maxBar * .04 : bars[i],
                                        width: 24,
                                        color: i == peak ? AppPalette.brand : const Color(0xFFC9DBF2),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ]),
                                ],
                              ),
                            ),
                    ),
                    const SizedBox(height: 8),
                    Text('driver.period_stats'.tr(args: ['${list.length}', '$hours']),
                        style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              DCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('driver.transactions'.tr(), style: AppTypography.h3),
                    if (_tx.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Text('driver.no_transactions'.tr(),
                            style: const TextStyle(color: AppPalette.textSecondary)),
                      ),
                    for (final t in _tx.take(10)) _txRow(t, lang),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Знак суммы по типу: зачисления «+», списания «−».
  Widget _txRow(Map<String, dynamic> t, String lang) {
    final type = '${t['type']}';
    final amount = (t['amount'] as num?)?.toDouble() ?? double.tryParse('${t['amount']}') ?? 0;
    const minus = {'payment', 'withdrawal', 'payout', 'listing_fee'};
    final out = minus.contains(type);
    final at = DateTime.tryParse('${t['created_at']}')?.toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: out ? DChip.blueBg : AppPalette.successSubtle,
            child: Icon(out ? Icons.north_east_rounded : Icons.south_west_rounded,
                size: 18, color: out ? AppPalette.brand : AppPalette.textSuccess),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${t['description'] ?? type}', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                if (at != null)
                  Text(DateFormat('d MMM, HH:mm', lang).format(at),
                      style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
              ],
            ),
          ),
          Text('${out ? '−' : '+'}${money(amount)}',
              style: TextStyle(fontWeight: FontWeight.w600, color: out ? AppPalette.textPrimary : AppPalette.textSuccess)),
        ],
      ),
    );
  }
}
