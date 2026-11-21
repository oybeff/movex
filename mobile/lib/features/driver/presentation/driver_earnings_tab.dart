import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../taxi/presentation/widgets/taxi_ui.dart' show formatSum;
import '../data/driver_api.dart';

/// «Daromad» (макет): заработок за неделю / месяц / год, столбики по дням
/// или месяцам, число заказов и комиссия, баланс и вывод на карту.
///
/// Считается по завершённым заказам: сумма заказа минус комиссия — ровно
/// то, что сервер зачисляет владельцу (у наличных — то, что осталось у
/// него на руках после списания комиссии с баланса).
class DriverEarningsTab extends StatefulWidget {
  const DriverEarningsTab({super.key});

  @override
  State<DriverEarningsTab> createState() => _DriverEarningsTabState();
}

enum _Period { week, month, year }

class _DriverEarningsTabState extends State<DriverEarningsTab> {
  final _api = DriverApi();
  _Period _period = _Period.week;
  List<DriverOrder> _done = const [];
  Map<String, dynamic>? _balance;
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
      if (!mounted) return;
      setState(() {
        _done = orders.where((o) => o.status == 'completed').toList();
        _balance = bal;
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
      _Period.week => today.subtract(Duration(days: today.weekday - 1)),
      _Period.month => DateTime(now.year, now.month),
      _Period.year => DateTime(now.year),
    };
  }

  /// Столбики: неделя — 7 дней, месяц — по неделям (до 5), год — 12 месяцев.
  List<double> _bars(List<DriverOrder> list) {
    final from = _from;
    switch (_period) {
      case _Period.week:
        final b = List<double>.filled(7, 0);
        for (final o in list) {
          b[(o.updatedAt.difference(from).inDays).clamp(0, 6)] += o.earning;
        }
        return b;
      case _Period.month:
        final b = List<double>.filled(5, 0);
        for (final o in list) {
          b[((o.updatedAt.day - 1) ~/ 7).clamp(0, 4)] += o.earning;
        }
        return b;
      case _Period.year:
        final b = List<double>.filled(12, 0);
        for (final o in list) {
          b[o.updatedAt.month - 1] += o.earning;
        }
        return b;
    }
  }

  String _barLabel(int i, String lang) {
    switch (_period) {
      case _Period.week:
        return DateFormat.E(lang).format(_from.add(Duration(days: i)));
      case _Period.month:
        return '${i * 7 + 1}';
      case _Period.year:
        return DateFormat.MMM(lang).format(DateTime(2000, i + 1));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode;
    final list = _done.where((o) => !o.updatedAt.isBefore(_from)).toList();
    final total = list.fold<double>(0, (s, o) => s + o.earning);
    final commission = list.fold<double>(0, (s, o) => s + o.commission);
    final bars = _bars(list);
    final maxBar = bars.fold<double>(0, (m, v) => v > m ? v : m);
    final bal = _balance;
    double n(String k) => (bal?[k] as num?)?.toDouble() ?? double.tryParse('${bal?[k]}') ?? 0;
    final withdrawable = (n('balance') - n('frozen_balance') - n('bonus_balance')).clamp(0, double.infinity);

    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(title: Text('driver.tab_earnings'.tr()), centerTitle: true),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            SegmentedButton<_Period>(
              segments: [
                ButtonSegment(value: _Period.week, label: Text('driver.week'.tr())),
                ButtonSegment(value: _Period.month, label: Text('driver.month'.tr())),
                ButtonSegment(value: _Period.year, label: Text('driver.year'.tr())),
              ],
              selected: {_period},
              showSelectedIcon: false,
              onSelectionChanged: (s) => setState(() => _period = s.first),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(20)),
              child: Column(
                children: [
                  Text("${formatSum(total)} ${'common.currency'.tr()}", style: AppTypography.h1),
                  const SizedBox(height: AppSpacing.lg),
                  SizedBox(
                    height: 160,
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
                                    getTitlesWidget: (v, _) => Text(
                                      _barLabel(v.toInt(), lang),
                                      style: AppTypography.bodyM.copyWith(fontSize: 11, color: AppPalette.textSecondary),
                                    ),
                                  ),
                                ),
                              ),
                              barGroups: [
                                for (var i = 0; i < bars.length; i++)
                                  BarChartGroupData(x: i, barRods: [
                                    BarChartRodData(
                                      toY: bars[i],
                                      width: _period == _Period.year ? 12 : 22,
                                      color: AppPalette.brand,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                  ]),
                              ],
                            ),
                          ),
                  ),
                  const Divider(height: 32),
                  Row(
                    children: [
                      Expanded(child: _stat('driver.orders_count'.tr(), '${list.length}')),
                      Expanded(
                        child: _stat('driver.commission'.tr(), "${formatSum(commission)} ${'common.currency'.tr()}"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('driver.balance'.tr(), style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
                  Text("${formatSum(n('balance'))} ${'common.currency'.tr()}", style: AppTypography.h2),
                  Text('driver.withdrawable'.tr(args: [formatSum(withdrawable)]),
                      style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
                  const SizedBox(height: AppSpacing.md),
                  ElevatedButton(
                    onPressed: () async {
                      await context.push('/payout');
                      _load();
                    },
                    child: Text('driver.withdraw'.tr()),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
          const SizedBox(height: 2),
          Text(value, style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600)),
        ],
      );
}
