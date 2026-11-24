import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/utils/number_formatter.dart';
import '../data/freight_api.dart';
import '../../support/presentation/support_pages.dart';
import '../../../core/widgets/h_icon.dart';

/// Заказы «Yuk tashish» клиента: статус, кто везёт, отмена до погрузки,
/// «Yakunlash» — после погрузки (тогда водитель получает деньги).
class FreightOrdersPage extends StatefulWidget {
  const FreightOrdersPage({super.key});

  @override
  State<FreightOrdersPage> createState() => _FreightOrdersPageState();
}

class _FreightOrdersPageState extends State<FreightOrdersPage> {
  final _api = FreightApi();
  List<FreightOrder> _orders = const [];
  bool _loading = true;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _api.myOrders();
      if (mounted) setState(() => _orders = list);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _act(FreightOrder o, Future<FreightOrder> Function(int) action, String question) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(question),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.back'.tr())),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('common.confirm'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy.add(o.id));
    try {
      await action(o.id);
      await _load();
    } on DioException catch (e) {
      final d = e.response?.data;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(d is Map && d['detail'] is String ? d['detail'] as String : 'errors.something_went_wrong'.tr()),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(o.id));
    }
  }

  String _sum(double v) => '${NumberFormatter.formatCurrency(v)} ${'common.currency'.tr()}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text('freight.my_orders'.tr(), style: AppTypography.h3),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _orders.isEmpty
                  ? ListView(children: [
                      Padding(padding: const EdgeInsets.all(32), child: Text('freight.empty'.tr(), textAlign: TextAlign.center)),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _orders.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => _card(_orders[i]),
                    ),
            ),
    );
  }

  Widget _card(FreightOrder o) {
    final busy = _busy.contains(o.id);
    final body = o.bodyType == null ? null : 'freight.body_${o.bodyType}'.tr();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Text('#${o.id} · ${[o.vehicleName, body].whereType<String>().join(', ')}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: o.active ? AppPalette.brandSubtle : AppPalette.page,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('freight.st_${o.status}'.tr(),
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: o.active ? AppPalette.brand : AppPalette.textSecondary)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${o.fromAddress ?? '—'}  →  ${o.toAddress ?? '—'}', style: const TextStyle(color: AppPalette.textSecondary)),
          Text(
            [
              '${o.distanceKm.toStringAsFixed(1)} km',
              if (o.tonnes != null) '${o.tonnes} t',
              if (o.hours != null) 'freight.hours_n'.tr(args: ['${o.hours}']),
              o.cash ? 'freight.pay_cash'.tr() : 'freight.pay_wallet'.tr(),
            ].join(' · '),
            style: const TextStyle(color: AppPalette.textSecondary, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(_sum(o.price), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          if (o.driverName != null) ...[
            const Divider(height: 20),
            Row(children: [
              const HIcon(Icons.local_shipping_outlined, color: AppPalette.brand),
              const SizedBox(width: 8),
              Expanded(
                child: Text([o.driverName, o.driverPlate].whereType<String>().join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (o.driverPhone != null && o.active)
                IconButton(
                  tooltip: 'freight.call_driver'.tr(),
                  icon: const HIcon(Icons.call_outlined, color: AppPalette.brand),
                  onPressed: () => launchUrl(Uri.parse('tel:+${o.driverPhone!.replaceAll(RegExp(r'[^0-9]'), '')}')),
                ),
            ]),
          ],
          if (o.status == 'searching' || o.status == 'accepted') ...[
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: busy ? null : () => _act(o, _api.cancel, 'freight.cancel_q'.tr()),
              child: Text('freight.cancel'.tr()),
            ),
          ],
          if (o.status == 'loaded' || o.status == 'arrived') ...[
            const SizedBox(height: 8),
            if (o.cash)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('freight.pay_driver_cash'.tr(args: [_sum(o.price)])),
              ),
            FilledButton(
              onPressed: busy ? null : () => _act(o, _api.finish, 'freight.finish_q'.tr()),
              child: Text('freight.finish'.tr()),
            ),
          ],
          if (o.status != 'searching' && o.status != 'cancelled')
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => OpenDisputePage(kind: 'freight', orderId: o.id))),
                icon: const HIcon(Icons.report_gmailerrorred_rounded, size: 18),
                label: Text('dispute.report'.tr()),
              ),
            ),
        ],
      ),
    );
  }
}
