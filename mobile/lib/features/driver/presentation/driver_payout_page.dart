import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/payout_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/payout_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/driver_api.dart';
import '../data/driver_card_model.dart';
import 'driver_add_card_page.dart';
import 'driver_cards_page.dart';
import 'driver_ui.dart';

/// Макет 04: «Pul yechish» (P2, C1, C5, P4).
class DriverPayoutPage extends StatefulWidget {
  const DriverPayoutPage({super.key});

  @override
  State<DriverPayoutPage> createState() => _DriverPayoutPageState();
}

class _DriverPayoutPageState extends State<DriverPayoutPage> {
  final _api = DriverApi();
  final _payoutService = PayoutService();
  final _amountCtrl = TextEditingController();

  List<DriverPayoutCard> _cards = [];
  DriverPayoutCard? _selectedCard;
  PayoutSettingsModel? _settings;

  double _available = 0;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _userId;

  // Экран успеха (P4)
  PayoutRequestModel? _successRequest;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final me = await AuthService().getUserId();
      if (me != null) {
        _userId = me.toString();
        final cards = await DriverCardsRepository.getCards(_userId!);
        _cards = cards;
        _selectedCard = cards.where((c) => c.isDefault).firstOrNull ?? cards.firstOrNull;
      }

      final bal = await _api.balance();
      final total = (bal['balance'] as num?)?.toDouble() ?? 0;
      final frozen = (bal['frozen_balance'] as num?)?.toDouble() ?? 0;
      final bonus = (bal['bonus_balance'] as num?)?.toDouble() ?? 0;
      _available = (total - frozen - bonus).clamp(0, double.infinity);

      try {
        _settings = await _payoutService.getSettings();
      } catch (_) {}
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _enteredAmount {
    final clean = _amountCtrl.text.replaceAll(RegExp(r'\D'), '');
    return double.tryParse(clean) ?? 0;
  }

  double get _commission {
    final amt = _enteredAmount;
    if (amt <= 0 || _settings == null) return 0;
    return _settings!.commissionFor(amt);
  }

  double get _netPayout {
    final amt = _enteredAmount;
    final comm = _commission;
    return (amt - comm).clamp(0, double.infinity);
  }

  void _setAmount(double val) {
    final v = val.clamp(0, _available);
    final str = v.toStringAsFixed(0);
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(str[i]);
    }
    _amountCtrl.text = buffer.toString();
    setState(() {});
  }

  void _addAmount(double add) {
    _setAmount(_enteredAmount + add);
  }

  Future<void> _onAddCard() async {
    final newCard = await Navigator.of(context).push<DriverPayoutCard>(
      MaterialPageRoute(builder: (_) => const DriverAddCardPage()),
    );
    if (newCard != null && _userId != null) {
      final cards = await DriverCardsRepository.getCards(_userId!);
      setState(() {
        _cards = cards;
        _selectedCard = cards.firstWhere((c) => c.id == newCard.id, orElse: () => newCard);
      });
    }
  }

  Future<void> _submitPayout() async {
    final amt = _enteredAmount;
    if (_selectedCard == null) {
      setState(() => _error = "Avval pul tushadigan kartani tanlang");
      return;
    }
    if (amt < 50000) {
      setState(() => _error = "Eng kam yechish summasi: 50 000 so'm");
      return;
    }
    if (amt > _available) {
      setState(() => _error = "Balansda yetarli mablag' mavjud emas");
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final req = await _payoutService.createRequest(
        amount: amt,
        cardNumber: _selectedCard!.number,
        cardHolder: _selectedCard!.holder,
      );

      if (!mounted) return;
      setState(() {
        _successRequest = req;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_successRequest != null) {
      return _buildSuccessP4();
    }

    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text("Pul yechish", style: AppTypography.h3),
        actions: [
          IconButton(
            icon: const Icon(Icons.credit_card, color: AppPalette.brand),
            tooltip: "Kartalarim",
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DriverCardsPage()),
              );
              _load();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Доступно к выводу
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppPalette.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Yechib olish mumkin",
                          style: TextStyle(fontSize: 13, color: AppPalette.textSecondary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          money(_available),
                          style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: AppPalette.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Ввод суммы
                  DCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Summa", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _amountCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            _AmountInputFormatter(),
                          ],
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: "0",
                            hintStyle: const TextStyle(color: AppPalette.borderDefault),
                            suffixText: "so'm",
                            suffixStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppPalette.textSecondary),
                            filled: true,
                            fillColor: AppPalette.page,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            _chipButton("+100 000", () => _addAmount(100000)),
                            const SizedBox(width: 8),
                            _chipButton("+500 000", () => _addAmount(500000)),
                            const SizedBox(width: 8),
                            _chipButton("Hammasi", () => _setAmount(_available)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Карты
                  _buildCardsSection(),

                  // Расчет комиссии и срока
                  if (_cards.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    DCard(
                      child: Column(
                        children: [
                          DRow("Komissiya", money(_commission)),
                          DRow("Tushadigan mablag'", money(_netPayout), bold: true),
                          const DRow("Muddat", "1–5 daqiqa"),
                        ],
                      ),
                    ),
                  ],

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: AppPalette.textDanger, fontSize: 13)),
                  ],

                  const SizedBox(height: 24),
                  if (_cards.isEmpty)
                    const DSecondary("Avval karta qo'shing", onPressed: null)
                  else
                    DPrimary(
                      _enteredAmount > 0 ? "${money(_enteredAmount)} yechish" : "Pul yechish",
                      busy: _busy,
                      onPressed: _enteredAmount >= 50000 && _enteredAmount <= _available ? _submitPayout : null,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _chipButton(String label, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: AppPalette.page,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppPalette.brand),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardsSection() {
    if (_cards.isEmpty) {
      // C1: Karta yo'q
      return DCard(
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppPalette.brandSubtle,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.credit_card_outlined, size: 28, color: AppPalette.brand),
            ),
            const SizedBox(height: 12),
            const Text(
              "Karta qo'shilmagan",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            const Text(
              "Pul yechish uchun avval karta qo'shing",
              style: TextStyle(fontSize: 13, color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 16),
            DSecondary("+ Karta qo'shish", onPressed: _onAddCard, tinted: true),
            const SizedBox(height: 6),
          ],
        ),
      );
    }

    // P2 / C5: Выбор карты
    return DCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Qaysi kartaga", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              TextButton(
                onPressed: _onAddCard,
                child: const Text("+ Yangi karta", style: TextStyle(color: AppPalette.brand, fontSize: 13, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final c in _cards)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: _selectedCard?.id == c.id ? const Color(0xFFF0F6FE) : AppPalette.page,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _selectedCard = c),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(right: 12),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedCard?.id == c.id ? AppPalette.brand : AppPalette.borderDefault,
                              width: 2,
                            ),
                          ),
                          child: _selectedCard?.id == c.id
                              ? Center(
                                  child: Container(
                                    width: 10,
                                    height: 10,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppPalette.brand,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                        Container(
                          width: 36,
                          height: 26,
                          decoration: BoxDecoration(
                            color: c.type == DriverCardType.humo
                                ? const Color(0xFFE6F4EA)
                                : const Color(0xFFEBF2FF),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text(
                              c.typeName.toUpperCase(),
                              style: TextStyle(
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                color: c.type == DriverCardType.humo
                                    ? const Color(0xFF0F766E)
                                    : AppPalette.brand,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.shortMasked, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              Text("Muddati: ${c.expiry}", style: const TextStyle(fontSize: 11, color: AppPalette.textSecondary)),
                            ],
                          ),
                        ),
                        if (c.isDefault)
                          const DChip("Asosiy", bg: Color(0xFFDCFCE7), fg: Color(0xFF16A34A)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuccessP4() {
    final req = _successRequest!;
    final cardName = _selectedCard?.shortMasked ?? req.cardMasked;
    final now = DateFormat('d MMMM, HH:mm', 'uz').format(DateTime.now());

    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 40),
            Center(
              child: Container(
                width: 88,
                height: 88,
                decoration: const BoxDecoration(
                  color: Color(0xFFDCFCE7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, size: 58, color: Color(0xFF16A34A)),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Pul yuborildi",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              "${money(req.payoutAmount)} $cardName kartangizga yuborildi. Odatda 1–5 daqiqada tushadi",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: AppPalette.textSecondary),
            ),
            const SizedBox(height: 28),
            DCard(
              child: Column(
                children: [
                  DRow("Sana", now),
                  DRow("Tranzaksiya", "#TR${req.id}"),
                  DRow("Yechilgan summa", money(req.payoutAmount), bold: true),
                  DRow("Karta", cardName),
                ],
              ),
            ),
            const SizedBox(height: 32),
            DPrimary("Tayyor", onPressed: () => Navigator.of(context).pop(true)),
            const SizedBox(height: 12),
            DSecondary(
              "Chekdan nusxa olish",
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: "MoveX GO to'lov cheki\n"
                        "Tranzaksiya: #TR${req.id}\n"
                        "Summa: ${money(req.payoutAmount)}\n"
                        "Karta: $cardName\n"
                        "Sana: $now",
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text("Chek ma'lumotlaridan nusxa olindi")),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AmountInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (text.isEmpty) return const TextEditingValue();
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && (text.length - i) % 3 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    final s = buffer.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
