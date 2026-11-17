import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/balance_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../client_home/presentation/pages/client_balance_page.dart';
import '../../data/card_api.dart';
import '../widgets/taxi_ui.dart';
import 'app_status_pages.dart' show HaloState;
import 'card_bind_page.dart';

/// Pr3 · To'lov usullari, T6 (удалить карту), T7 (карт нет).
class PaymentMethodsPage extends StatefulWidget {
  const PaymentMethodsPage({super.key});

  @override
  State<PaymentMethodsPage> createState() => _PaymentMethodsPageState();
}

class _PaymentMethodsPageState extends State<PaymentMethodsPage> {
  final _api = CardApi();
  double? _balance;
  List<BankCard>? _cards;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final c = await _api.list();
      if (mounted) setState(() => _cards = c);
    } catch (_) {
      if (mounted) setState(() => _cards = const []);
    }
    try {
      final b = await BalanceService().getBalance();
      if (mounted) setState(() => _balance = b.balance);
    } catch (_) {}
  }

  void _toast(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _add() async {
    final c = await addBankCard(context);
    if (c != null) _load();
  }

  Future<void> _actions(BankCard c) async {
    final a = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.gutter),
                child: CardArt(card: c),
              ),
              if (!c.isDefault)
                MenuRow(icon: 'check_circle', title: 'taxi.make_main'.tr(), chevron: false,
                    onTap: () => Navigator.pop(ctx, 'main')),
              MenuRow(
                icon: 'menu_logout',
                iconBg: AppPalette.dangerSubtle,
                title: 'taxi.card_delete_yes'.tr(),
                color: AppPalette.textDanger,
                chevron: false,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || a == null) return;
    try {
      if (a == 'main') {
        await _api.makeDefault(c.id);
      } else if (await confirmDeleteCard(context, c) == true) {
        await _api.delete(c.id);
      }
      _load();
    } catch (e) {
      _toast(getErrorMessage(e));
    }
  }

  Widget _miniCard() => Container(
        width: 40,
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: const LinearGradient(colors: [Color(0xFF2A62C0), Color(0xFF5B9BEA)]),
        ),
        alignment: const Alignment(-.6, -.5),
        child: Container(
          width: 9,
          height: 7,
          decoration: BoxDecoration(color: const Color(0xFFF6C849), borderRadius: BorderRadius.circular(2)),
        ),
      );

  Widget _cardRow(BankCard c) => InkWell(
        onTap: () => _actions(c),
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _miniCard(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(c.label, style: AppTypography.bodyMedium.copyWith(fontSize: 15, height: 20 / 15)),
                      if ((c.holder ?? '').isNotEmpty)
                        Text(c.holder!, style: AppTypography.captionS.copyWith(fontSize: 13, height: 18 / 13)),
                    ],
                  ),
                ),
                if (c.isDefault) ...[
                  TaxiBadge('taxi.card_main'.tr(), bg: AppPalette.brandSubtle, fg: AppPalette.textBrand),
                  const SizedBox(width: 8),
                ],
                const TaxiIcon('chevron_right', size: 18),
              ],
            ),
          ),
        ),
      );

  List<Widget> _others({bool cashSelected = false}) => [
        MenuCard(children: [
          MenuRow(
            icon: 'cash_menu',
            title: 'taxi.cash_money'.tr(),
            value: cashSelected ? 'taxi.now_selected'.tr() : 'taxi.after_work'.tr(),
            chevron: false,
          ),
          MenuRow(
            icon: 'menu_card',
            title: 'taxi.pay_balance'.tr(),
            value: _balance == null ? null : "${formatSum(_balance!)} ${'common.currency'.tr()}",
            onTap: () async {
              await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ClientBalancePage()));
              _load();
            },
          ),
        ]),
      ];

  @override
  Widget build(BuildContext context) {
    final cards = _cards;
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'taxi.payment_methods'.tr()),
            Expanded(
              child: cards == null
                  ? const Center(child: CircularProgressIndicator(color: AppPalette.brand))
                  : cards.isEmpty
                      // T7 · Kartalar yo'q
                      ? ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 40, AppSpacing.gutter, 24),
                          children: [
                            HaloState(
                              icon: const TaxiIcon('menu_card', size: 32),
                              title: 'taxi.no_cards'.tr(),
                              body: 'taxi.no_cards_body'.tr(),
                            ),
                            const SizedBox(height: 24),
                            ElevatedButton(onPressed: _add, child: Text('taxi.add_card_short'.tr())),
                            const SizedBox(height: 12),
                            ..._others(cashSelected: true),
                          ],
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 16, AppSpacing.gutter, 24),
                          children: [
                            GroupLabel('taxi.cards'.tr()),
                            const SizedBox(height: 8),
                            MenuCard(children: [
                              for (final c in cards) _cardRow(c),
                              MenuRow(
                                icon: 'plus_brand',
                                iconBg: AppPalette.brandSubtle,
                                title: 'taxi.add_card'.tr(),
                                color: AppPalette.textBrand,
                                onTap: _add,
                              ),
                            ]),
                            const SizedBox(height: 20),
                            GroupLabel('taxi.other_methods'.tr()),
                            const SizedBox(height: 8),
                            ..._others(),
                            const SizedBox(height: 20),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const TaxiIcon('lock', size: 16),
                                const SizedBox(width: 8),
                                Expanded(child: Text('taxi.payment_note'.tr(), style: AppTypography.captionS)),
                              ],
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
