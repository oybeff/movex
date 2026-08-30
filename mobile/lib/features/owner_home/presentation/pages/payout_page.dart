import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/models/payout_model.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/services/payout_service.dart';
import '../../../../core/utils/number_formatter.dart';

/// Pul yechish: ariza berish va o'z arizalari tarixi.
///
/// Ilgari texnika egasining balansi o'sib borardi, lekin pulni olib
/// chiqishning hech qanday yo'li yo'q edi.
class PayoutPage extends StatefulWidget {
  const PayoutPage({super.key});

  @override
  State<PayoutPage> createState() => _PayoutPageState();
}

class _PayoutPageState extends State<PayoutPage> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _cardController = TextEditingController();
  final _holderController = TextEditingController();

  final PayoutService _payoutService = PayoutService();
  final BalanceService _balanceService = BalanceService();

  BalanceModel? _balance;
  List<PayoutRequestModel> _requests = [];
  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _cardController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _balanceService.getBalance(),
        _payoutService.getMyRequests(),
      ]);
      if (!mounted) return;
      setState(() {
        _balance = results[0] as BalanceModel;
        _requests = results[1] as List<PayoutRequestModel>;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _snack('errors.something_went_wrong'.tr());
    }
  }

  double get _available => _balance?.availableBalance ?? 0;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSending = true);
    try {
      await _payoutService.createRequest(
        amount: double.parse(_amountController.text.replaceAll(' ', '')),
        cardNumber: _cardController.text.replaceAll(' ', ''),
        cardHolder: _holderController.text.trim(),
      );
      if (!mounted) return;
      _amountController.clear();
      _holderController.clear();
      _snack('payout.created'.tr());
      await _load();
    } on Exception catch (error) {
      if (!mounted) return;
      // Serverdagi sabab foydalanuvchiga aynan shundayligicha kerak:
      // "yetarli mablag' yo'q", "eng kam summa ..." va hokazo
      _snack(_serverMessage(error) ?? 'errors.something_went_wrong'.tr());
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  String? _serverMessage(Object error) {
    final text = error.toString();
    final match = RegExp(r'"detail"\s*:\s*"([^"]+)"').firstMatch(text);
    return match?.group(1);
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        title: Text(
          'payout.title'.tr(),
          style: const TextStyle(color: AppColors.black, fontWeight: FontWeight.bold),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              color: AppColors.primaryGreen,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _balanceCard(),
                  const SizedBox(height: 16),
                  _form(),
                  const SizedBox(height: 24),
                  _history(),
                ],
              ),
            ),
    );
  }

  Widget _balanceCard() {
    final balance = _balance;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('payout.available'.tr(),
              style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          const SizedBox(height: 6),
          Text(
            '${NumberFormatter.formatCurrency(_available)} ${'common.currency'.tr()}',
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          ),
          if (balance != null && balance.frozenBalance > 0) ...[
            const SizedBox(height: 8),
            Text(
              '${'payout.frozen'.tr()}: '
              '${NumberFormatter.formatCurrency(balance.frozenBalance)} ${'common.currency'.tr()}',
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }

  Widget _form() {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.black12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('payout.new_request'.tr(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _amountController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                labelText: 'payout.amount'.tr(),
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final amount = double.tryParse((value ?? '').replaceAll(' ', ''));
                if (amount == null || amount <= 0) return 'payout.enter_amount'.tr();
                if (amount > _available) return 'payout.not_enough'.tr();
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _cardController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              decoration: InputDecoration(
                labelText: 'payout.card_number'.tr(),
                hintText: '8600 •••• •••• ••••',
                border: const OutlineInputBorder(),
              ),
              validator: (value) {
                final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
                if (digits.length != 16) return 'payout.card_invalid'.tr();
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _holderController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: 'payout.card_holder'.tr(),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSending ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isSending
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text('payout.submit'.tr(),
                        style: const TextStyle(color: Colors.white, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'payout.hint'.tr(),
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _history() {
    if (_requests.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text('payout.no_requests'.tr(),
              style: TextStyle(color: Colors.grey[600])),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('payout.history'.tr(),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 10),
        ..._requests.map(_historyTile),
      ],
    );
  }

  Widget _historyTile(PayoutRequestModel request) {
    final palette = {
      'pending': (AppColors.primaryGreen, 'payout.status_pending'),
      'paid': (const Color(0xFF2C6E4E), 'payout.status_paid'),
      'rejected': (AppColors.error, 'payout.status_rejected'),
    }[request.status] ?? (AppColors.grey, 'payout.status_pending');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${NumberFormatter.formatCurrency(request.amount)} ${'common.currency'.tr()}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: palette.$1.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  palette.$2.tr(),
                  style: TextStyle(color: palette.$1, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${request.cardMasked} · ${DateFormat('dd.MM.yyyy HH:mm').format(request.createdAt)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 13),
          ),
          if (request.adminComment != null && request.adminComment!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(request.adminComment!,
                style: TextStyle(color: Colors.grey[700], fontSize: 13)),
          ],
        ],
      ),
    );
  }
}
