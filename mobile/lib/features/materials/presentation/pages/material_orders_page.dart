import 'package:dio/dio.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/material_types.dart';
import '../../../../core/models/material_model.dart';
import '../../../../core/services/material_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/number_formatter.dart';
import '../../../../core/widgets/h_icon.dart';

/// Заказы стройматериалов: у клиента — свои покупки, у продавца
/// ([asSeller]) — пришедшие заказы.
///
/// До 23.11.2026 такого экрана не было вовсе: заказать можно было, а
/// подтвердить продавцу и нажать «Yetkazildi» клиенту — негде, и деньги
/// висели в заморозке. Теперь:
///  - продавец принимает или отклоняет; принятый заказ уходит водителям;
///  - клиент видит, кто везёт (имя, номер машины, телефон), отменяет,
///    пока товар не погружен, и подтверждает получение.
class MaterialOrdersPage extends StatefulWidget {
  const MaterialOrdersPage({super.key, this.asSeller = false});

  final bool asSeller;

  @override
  State<MaterialOrdersPage> createState() => _MaterialOrdersPageState();
}

class _MaterialOrdersPageState extends State<MaterialOrdersPage> {
  final _service = MaterialService();
  List<MaterialOrderModel> _orders = const [];
  bool _loading = true;
  bool _failed = false;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await _service.getOrders(asSeller: widget.asSeller);
      if (!mounted) return;
      setState(() {
        _orders = list;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  Future<void> _act(MaterialOrderModel o, Future<MaterialOrderModel> Function(int) action, {String? confirm}) async {
    if (confirm != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(confirm),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.back'.tr())),
            TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('common.confirm'.tr())),
          ],
        ),
      );
      if (ok != true) return;
    }
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

  Future<void> _call(String phone) =>
      launchUrl(Uri.parse('tel:+${phone.replaceAll(RegExp(r'[^0-9]'), '')}'));

  String _sum(double v) => '${NumberFormatter.formatCurrency(v)} ${'common.currency'.tr()}';

  String _status(MaterialOrderModel o) {
    if (o.isDelivered) return 'material_orders.st_delivered'.tr();
    if (o.status == 'cancelled') return 'material_orders.st_cancelled'.tr();
    if (o.status == 'rejected') return 'material_orders.st_rejected'.tr();
    if (o.isPending) return 'material_orders.st_waiting_seller'.tr();
    switch (o.deliveryStatus) {
      case 'searching':
        return 'material_orders.st_searching'.tr();
      case 'accepted':
        return 'material_orders.st_accepted'.tr();
      case 'picked_up':
        return 'material_orders.st_picked_up'.tr();
      case 'arrived':
        return 'material_orders.st_arrived'.tr();
    }
    return 'material_orders.st_confirmed'.tr();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        title: Text(
          widget.asSeller ? 'material_orders.title_seller'.tr() : 'material_orders.title'.tr(),
          style: AppTypography.h3,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
          : RefreshIndicator(
              color: AppPalette.brand,
              onRefresh: _load,
              child: _failed
                  ? ListView(children: [
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('material_orders.load_failed'.tr(), textAlign: TextAlign.center),
                      ),
                    ])
                  : _orders.isEmpty
                      ? ListView(children: [
                          Padding(
                            padding: const EdgeInsets.all(32),
                            child: Text('material_orders.empty'.tr(), textAlign: TextAlign.center),
                          ),
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

  Widget _card(MaterialOrderModel o) {
    final busy = _busy.contains(o.id);
    final q = o.quantity == o.quantity.roundToDouble() ? o.quantity.toStringAsFixed(0) : o.quantity.toString();
    final closed = o.isClosed || o.isDelivered;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('#${o.id} · ${o.productTitle ?? MaterialTypes.label(o.materialType)}',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: closed ? AppPalette.page : AppPalette.brandSubtle,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_status(o),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: closed ? AppPalette.textSecondary : AppPalette.brand)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('$q ${o.unitLabel} · ${o.vehicleName ?? o.vehicleCode}',
              style: const TextStyle(color: AppPalette.textSecondary)),
          if (o.deliveryAddress != null)
            Text(o.deliveryAddress!, style: const TextStyle(color: AppPalette.textSecondary)),
          const SizedBox(height: 8),
          _row('material_orders.goods'.tr(), _sum(o.goodsAmount)),
          _row(
            o.cashDelivery ? 'material_orders.delivery_cash'.tr() : 'material_orders.delivery_wallet'.tr(),
            _sum(o.driverFee ?? o.deliveryFee),
          ),
          if (widget.asSeller) _row('material_orders.you_get'.tr(), _sum(o.goodsAmount - o.commission), bold: true),
          if (o.driverName != null) ...[
            const Divider(height: 20),
            Row(
              children: [
                const HIcon(Icons.local_shipping_outlined, color: AppPalette.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    [o.driverName, o.driverPlate].whereType<String>().join(' · '),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                if (o.driverPhone != null && !closed)
                  IconButton(
                    tooltip: 'material_orders.call_driver'.tr(),
                    icon: const HIcon(Icons.call_outlined, color: AppPalette.brand),
                    onPressed: () => _call(o.driverPhone!),
                  ),
              ],
            ),
          ],
          if (!closed) ...[
            const SizedBox(height: 10),
            ..._actions(o, busy),
          ],
        ],
      ),
    );
  }

  List<Widget> _actions(MaterialOrderModel o, bool busy) {
    final out = <Widget>[];
    if (widget.asSeller) {
      if (o.isPending) {
        out.add(Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: busy ? null : () => _act(o, _service.rejectOrder, confirm: 'material_orders.reject_q'.tr()),
                child: Text('material_orders.reject'.tr()),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: busy ? null : () => _act(o, _service.confirmOrder),
                child: Text('material_orders.accept'.tr()),
              ),
            ),
          ],
        ));
      } else if (o.deliveryStatus == 'searching') {
        out.add(Text('material_orders.seller_wait_driver'.tr(),
            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)));
      } else if (o.deliveryStatus == 'accepted') {
        out.add(Text('material_orders.seller_driver_coming'.tr(),
            style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)));
      }
      return out;
    }
    if (o.onTheWay) {
      if (o.cashDelivery) {
        out.add(Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('material_orders.pay_driver_cash'.tr(args: [_sum(o.driverFee ?? o.deliveryFee)]),
              style: const TextStyle(fontSize: 13)),
        ));
      }
      out.add(FilledButton(
        onPressed: busy
            ? null
            : () => _act(o, _service.confirmDelivery, confirm: 'material_orders.delivered_q'.tr()),
        child: Text('material_orders.delivered'.tr()),
      ));
    } else if (o.cancellable) {
      out.add(OutlinedButton(
        onPressed: busy ? null : () => _act(o, _service.cancelOrder, confirm: 'material_orders.cancel_q'.tr()),
        child: Text('material_orders.cancel'.tr()),
      ));
    }
    return out;
  }

  Widget _row(String k, String v, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(child: Text(k, style: const TextStyle(color: AppPalette.textSecondary))),
            Text(v, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
}
