import 'package:easy_localization/easy_localization.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/services/auth_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../data/driver_card_model.dart';
import 'driver_ui.dart';
import '../../../core/widgets/h_icon.dart';

/// Макет 04 C2, C3, C4: «Karta qo'shish», «SMS kodni tasdiqlash», «Karta qo'shildi».
class DriverAddCardPage extends StatefulWidget {
  const DriverAddCardPage({super.key});

  @override
  State<DriverAddCardPage> createState() => _DriverAddCardPageState();
}

enum _Step { input, otp, success }

class _DriverAddCardPageState extends State<DriverAddCardPage> {
  _Step _step = _Step.input;

  final _panCtrl = TextEditingController();
  final _expiryCtrl = TextEditingController();
  final _holderCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _isDefault = true;
  bool _busy = false;
  String? _error;
  DriverPayoutCard? _createdCard;

  int _resendTimer = 60;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    AuthService().getCurrentUser().then((u) {
      final name = u?.fullName;
      if (mounted && name != null && name.isNotEmpty) {
        _holderCtrl.text = name.toUpperCase();
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    _panCtrl.dispose();
    _expiryCtrl.dispose();
    _holderCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _resendTimer = 60);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_resendTimer <= 1) {
        t.cancel();
        setState(() => _resendTimer = 0);
      } else {
        setState(() => _resendTimer--);
      }
    });
  }

  String get _cleanPan => _panCtrl.text.replaceAll(RegExp(r'\D'), '');

  DriverCardType get _cardType => DriverPayoutCard.detectType(_cleanPan);

  LinearGradient get _cardGradient {
    switch (_cardType) {
      case DriverCardType.humo:
        return const LinearGradient(
          colors: [Color(0xFF0F766E), Color(0xFF10B981)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case DriverCardType.visa:
        return const LinearGradient(
          colors: [Color(0xFF1E293B), Color(0xFF334155)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case DriverCardType.mastercard:
        return const LinearGradient(
          colors: [Color(0xFF7F1D1D), Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      case DriverCardType.uzcard:
      default:
        return const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
    }
  }

  String _formatLivePan() {
    final digits = _cleanPan;
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(digits[i]);
    }
    final raw = buffer.toString();
    if (raw.length < 19) {
      return raw + '•••• •••• •••• ••••'.substring(raw.length.clamp(0, 19));
    }
    return raw;
  }

  void _onContinue() {
    final pan = _cleanPan;
    if (pan.length != 16) {
      setState(() => _error = "Karta raqami 16 ta raqam bo'lishi kerak");
      return;
    }
    final exp = _expiryCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (exp.length != 4) {
      setState(() => _error = 'driver.card_expiry_full'.tr());
      return;
    }
    final m = int.tryParse(exp.substring(0, 2)) ?? 0;
    if (m < 1 || m > 12) {
      setState(() => _error = "Yaroqsiz oy kiritildi (01-12)");
      return;
    }

    setState(() {
      _error = null;
      _step = _Step.otp;
    });
    _startTimer();
  }

  Future<void> _onConfirmOtp() async {
    final otp = _otpCtrl.text.replaceAll(RegExp(r'\D'), '');
    if (otp.length != 6) {
      setState(() => _error = 'driver.card_sms_6'.tr());
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final me = await AuthService().getUserId();
      if (me == null) throw Exception("Foydalanuvchi aniqlanmadi");

      final card = DriverPayoutCard(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        number: _cleanPan,
        expiry: _expiryCtrl.text.trim(),
        holder: _holderCtrl.text.trim().isNotEmpty
            ? _holderCtrl.text.trim()
            : 'CARDHOLDER',
        isDefault: _isDefault,
      );

      await DriverCardsRepository.addCard(me.toString(), card);

      if (!mounted) return;
      setState(() {
        _createdCard = card;
        _step = _Step.success;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(
        backgroundColor: AppPalette.surface,
        elevation: 0,
        leading: IconButton(
          icon: const HIcon(Icons.arrow_back, color: AppPalette.textPrimary),
          onPressed: () {
            if (_step == _Step.otp) {
              setState(() => _step = _Step.input);
            } else if (_step == _Step.success) {
              Navigator.of(context).pop(_createdCard);
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(
          _step == _Step.otp
              ? 'driver.card_sms_confirm'.tr()
              : (_step == _Step.success ? "Karta qo'shildi" : "Karta qo'shish"),
          style: AppTypography.h3,
        ),
      ),
      body: SafeArea(
        child: _step == _Step.input
            ? _buildInputStep()
            : (_step == _Step.otp ? _buildOtpStep() : _buildSuccessStep()),
      ),
    );
  }

  Widget _buildCardVisual({required String pan, required String expiry, required String holder}) {
    return Container(
      width: double.infinity,
      height: 190,
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: _cardGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [
          BoxShadow(color: Color(0x2A1E3A8A), blurRadius: 16, offset: Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 38,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFACC15).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const HIcon(Icons.credit_card, size: 20, color: Colors.black54),
              ),
              Text(
                _cardType == DriverCardType.humo
                    ? 'HUMO'
                    : (_cardType == DriverCardType.uzcard ? 'UZCARD' : 'CARD'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          Text(
            pan,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 2,
              fontFamily: 'monospace',
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('KARTA EGASI', style: TextStyle(fontSize: 9, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text(
                    holder.isNotEmpty ? holder : 'JALIL TOSHMURODOV',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('MUDDATI', style: TextStyle(fontSize: 9, color: Colors.white70)),
                  const SizedBox(height: 2),
                  Text(
                    expiry.isNotEmpty ? expiry : '••/••',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInputStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCardVisual(
          pan: _formatLivePan(),
          expiry: _expiryCtrl.text.isEmpty ? '••/••' : _expiryCtrl.text,
          holder: _holderCtrl.text,
        ),
        DCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Karta raqami', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              TextField(
                controller: _panCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(16),
                  _CardNumberFormatter(),
                ],
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: '8600 0000 0000 0000',
                  hintStyle: const TextStyle(color: AppPalette.textSecondary),
                  prefixIcon: const HIcon(Icons.credit_card_outlined, color: AppPalette.brand),
                  filled: true,
                  fillColor: AppPalette.page,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Amal qilish muddati', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _expiryCtrl,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(4),
                            _CardExpiryFormatter(),
                          ],
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'OO/YY',
                            hintStyle: const TextStyle(color: AppPalette.textSecondary),
                            filled: true,
                            fillColor: AppPalette.page,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('driver.card_holder'.tr(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _holderCtrl,
                          textCapitalization: TextCapitalization.characters,
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: 'ISM FAMILIYA',
                            hintStyle: const TextStyle(color: AppPalette.textSecondary),
                            filled: true,
                            fillColor: AppPalette.page,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const HIcon(Icons.shield_outlined, size: 20, color: AppPalette.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'driver.card_secure'.tr(),
                  style: const TextStyle(fontSize: 12, color: AppPalette.textSecondary),
                ),
              ),
            ],
          ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: AppPalette.textDanger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        DPrimary("Davom etish", onPressed: _cleanPan.length == 16 ? _onContinue : null),
      ],
    );
  }

  Widget _buildOtpStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: DChip.blueBg,
              shape: BoxShape.circle,
            ),
            child: const HIcon(Icons.mark_email_read_outlined, size: 36, color: AppPalette.brand),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'driver.card_sms_enter'.tr(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'driver.card_sms_hint'.tr(),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 28),
        TextField(
          controller: _otpCtrl,
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          autofocus: true,
          maxLength: 6,
          style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: 8),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            counterText: '',
            hintText: '••••••',
            hintStyle: const TextStyle(color: AppPalette.borderDefault, letterSpacing: 8),
            filled: true,
            fillColor: AppPalette.surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppPalette.borderDefault)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppPalette.brand, width: 2)),
          ),
        ),
        const SizedBox(height: 16),
        Center(
          child: _resendTimer > 0
              ? Text("Kodni qayta yuborish: 0:${_resendTimer.toString().padLeft(2, '0')}", style: const TextStyle(color: AppPalette.textSecondary))
              : TextButton(
                  onPressed: _startTimer,
                  child: const Text("Kodni qayta yuborish", style: TextStyle(color: AppPalette.brand, fontWeight: FontWeight.w600)),
                ),
        ),
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppPalette.textDanger, fontSize: 13)),
        ],
        const SizedBox(height: 24),
        DPrimary("Tasdiqlash", busy: _busy, onPressed: _onConfirmOtp),
      ],
    );
  }

  Widget _buildSuccessStep() {
    final c = _createdCard!;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const SizedBox(height: 30),
        Center(
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: Color(0xFFDCFCE7),
              shape: BoxShape.circle,
            ),
            child: const HIcon(Icons.check_circle_rounded, size: 52, color: Color(0xFF16A34A)),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          "Karta qo'shildi",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          "Endi daromadingizni ushbu kartaga yechib olishingiz mumkin",
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: Colors.grey[600]),
        ),
        const SizedBox(height: 28),
        _buildCardVisual(
          pan: c.maskedPan,
          expiry: c.expiry,
          holder: c.holder,
        ),
        DCard(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Asosiy karta qilish", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  SizedBox(height: 2),
                  Text("Pul yechishda avtomatik tanlanadi", style: TextStyle(fontSize: 12, color: AppPalette.textSecondary)),
                ],
              ),
              Switch(
                value: _isDefault,
                activeThumbColor: AppPalette.brand,
                onChanged: (v) async {
                  setState(() => _isDefault = v);
                  final me = await AuthService().getUserId();
                  if (me != null && v) {
                    await DriverCardsRepository.setDefault(me.toString(), c.id);
                  }
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        DPrimary(
          "Pul yechishga qaytish",
          onPressed: () => Navigator.of(context).pop(c),
        ),
      ],
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i > 0 && i % 4 == 0) buffer.write(' ');
      buffer.write(text[i]);
    }
    final s = buffer.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}

class _CardExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      if (i == 2) buffer.write('/');
      buffer.write(text[i]);
    }
    final s = buffer.toString();
    return TextEditingValue(
      text: s,
      selection: TextSelection.collapsed(offset: s.length),
    );
  }
}
