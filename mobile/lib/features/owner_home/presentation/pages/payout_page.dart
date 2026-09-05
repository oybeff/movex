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

  /// Ushlanma shartlari. Serverdan kelmasa null — u holda hisob-kitob
  /// ko'rsatilmaydi, lekin ariza berish ishlashda davom etadi.
  PayoutSettingsModel? _settings;

  bool _isLoading = true;
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    // Summa yozilishi bilan "kartaga qancha tushadi" qayta hisoblanadi.
    _amountController.addListener(_onAmountChanged);
    _load();
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _amountController.dispose();
    _cardController.dispose();
    _holderController.dispose();
    super.dispose();
  }

  void _onAmountChanged() {
    if (_settings != null && mounted) setState(() {});
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

    // Shartlar alohida so'raladi: ular kelmasa ham sahifa ishlashi kerak.
    try {
      final settings = await _payoutService.getSettings();
      if (mounted) setState(() => _settings = settings);
    } catch (_) {
      // Eski server — hisob-kitobsiz ishlaymiz.
    }
  }

  // YECHISH mumkin bo'lgan summa: sovg'a bunga kirmaydi. Ilgari bu yerda
  // availableBalance turardi va ekran yechib bo'lmaydigan sovg'a pulini
  // ham ko'rsatardi — odam so'rov yuborib, rad javobini olardi.
  double get _available => _balance?.withdrawableBalance ?? 0;

  double get _bonus => _balance?.bonusBalance ?? 0;

  /// Maydonga yozilgan summa. Yozilmagan yoki noto'g'ri bo'lsa — 0.
  double get _enteredAmount =>
      double.tryParse(_amountController.text.replaceAll(' ', '')) ?? 0;

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
          // Sovg'a alohida satrda: aks holda odam balansida 50 000 turganini
          // ko'rib, nega yechishga nol ekanini tushunmasdi.
          if (_bonus > 0) ...[
            const SizedBox(height: 8),
            Text(
              "${'payout.bonus_note'.tr()}: "
              "${NumberFormatter.formatCurrency(_bonus)} ${'common.currency'.tr()} — "
              "${'payout.bonus_hint'.tr()}",
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ],
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
                // Ushlanma butun summani yeb qo'ysa, server baribir rad
                // etadi — sababni oldinroq va tushunarliroq aytamiz.
                final settings = _settings;
                if (settings != null && amount > 0 && settings.netFor(amount) <= 0) {
                  return 'payout.commission_too_big'.tr();
                }
                return null;
              },
            ),
            _commissionNote(),
            _calculation(),
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

  /// Shart summa kiritilishidan OLDIN ko'rinadi: ega nimaga rozi
  /// bo'layotganini bilib turishi kerak.
  Widget _commissionNote() {
    final settings = _settings;
    if (settings == null) return const SizedBox.shrink();

    final text = settings.isFixed
        ? 'payout.commission_note_fixed'.tr(namedArgs: {
            'amount': NumberFormatter.formatCurrency(settings.fixed),
            'currency': 'common.currency'.tr(),
          })
        : 'payout.commission_note_percent'.tr(namedArgs: {
            'percent': _trimZero(settings.percent),
          });

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(
        text,
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      ),
    );
  }

  /// Summa yozilgan zahoti: qancha ushlanadi va kartaga qancha tushadi.
  Widget _calculation() {
    final settings = _settings;
    final amount = _enteredAmount;
    if (settings == null || amount <= 0) return const SizedBox.shrink();

    final commission = settings.commissionFor(amount);
    final net = amount - commission;
    if (commission <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          _calcRow('payout.amount'.tr(), amount),
          const SizedBox(height: 6),
          _calcRow('payout.commission'.tr(), -commission),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(height: 1),
          ),
          _calcRow('payout.to_card'.tr(), net, bold: true),
        ],
      ),
    );
  }

  Widget _calcRow(String label, double value, {bool bold = false}) {
    final prefix = value < 0 ? '− ' : '';
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: bold ? AppColors.black : Colors.grey[700],
            fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        Text(
          '$prefix${NumberFormatter.formatCurrency(value.abs())} '
          '${'common.currency'.tr()}',
          style: TextStyle(
            fontSize: bold ? 15 : 13,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  /// 10.0 -> "10", 2.5 -> "2.5". Foizda nol quyruq ortiqcha.
  String _trimZero(double value) {
    final text = value.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
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
          if (request.commission > 0) ...[
            const SizedBox(height: 4),
            // Ega tarixda ham farqni ko'rishi kerak: yuqorida so'ralgan
            // summa, bu yerda kartaga tushgani va ushlangani.
            Text(
              '${'payout.to_card'.tr()}: '
              '${NumberFormatter.formatCurrency(request.payoutAmount)} '
              '${'common.currency'.tr()} · '
              '${'payout.commission'.tr()} '
              '${NumberFormatter.formatCurrency(request.commission)}',
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
          ],
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
