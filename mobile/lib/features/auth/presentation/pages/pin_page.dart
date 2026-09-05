import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/pin_service.dart';

/// PIN ekrani. Uch vazifani bajaradi, shuning uchun rejim bilan.
enum PinMode {
  /// Ilova ochilganda: kodni so'raydi, ortga qaytish yo'q.
  unlock,

  /// Yangi kod o'rnatish (ikki marta kiritiladi).
  create,

  /// Eski kodni tekshirish — o'chirish yoki almashtirish oldidan.
  confirmCurrent,
}

class PinPage extends StatefulWidget {
  const PinPage({super.key, required this.mode, this.onSuccess});

  final PinMode mode;

  /// Muvaffaqiyatli tugagach chaqiriladi. Berilmasa — Navigator.pop(true).
  final VoidCallback? onSuccess;

  @override
  State<PinPage> createState() => _PinPageState();
}

class _PinPageState extends State<PinPage> {
  String _entered = '';
  String? _firstEntry; // create rejimida birinchi kiritilgan kod
  String? _error;
  bool _biometricOffered = false;

  @override
  void initState() {
    super.initState();
    if (widget.mode == PinMode.unlock) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometric());
    }
  }

  Future<void> _tryBiometric() async {
    if (_biometricOffered) return;
    _biometricOffered = true;
    if (!await PinService.biometricEnabled()) return;
    if (!await PinService.biometricsAvailable()) return;
    final ok = await PinService.authenticateBiometric('pin.biometric_reason'.tr());
    if (ok && mounted) _finish();
  }

  void _finish() {
    if (widget.onSuccess != null) {
      widget.onSuccess!();
    } else {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _onDigit(String digit) async {
    if (_entered.length >= PinService.pinLength) return;
    setState(() {
      _entered += digit;
      _error = null;
    });
    if (_entered.length == PinService.pinLength) {
      await _onComplete();
    }
  }

  void _onBackspace() {
    if (_entered.isEmpty) return;
    setState(() => _entered = _entered.substring(0, _entered.length - 1));
  }

  Future<void> _onComplete() async {
    final code = _entered;

    switch (widget.mode) {
      case PinMode.create:
        if (_firstEntry == null) {
          // Birinchi kiritish — takrorlashni so'raymiz.
          setState(() {
            _firstEntry = code;
            _entered = '';
          });
          return;
        }
        if (_firstEntry != code) {
          // Kodlar mos kelmadi — boshidan. Aks holda odam xato kodni
          // o'rnatib qo'yib, keyin ilovaga kira olmasdi.
          setState(() {
            _firstEntry = null;
            _entered = '';
            _error = 'pin.mismatch'.tr();
          });
          return;
        }
        await PinService.setPin(code);
        if (mounted) _finish();
        return;

      case PinMode.unlock:
      case PinMode.confirmCurrent:
        if (await PinService.verifyPin(code)) {
          if (mounted) _finish();
          return;
        }
        if (mounted) {
          HapticFeedback.mediumImpact();
          setState(() {
            _entered = '';
            _error = 'pin.wrong'.tr();
          });
        }
        return;
    }
  }

  String get _title {
    switch (widget.mode) {
      case PinMode.create:
        return _firstEntry == null ? 'pin.create_title'.tr() : 'pin.repeat_title'.tr();
      case PinMode.unlock:
        return 'pin.unlock_title'.tr();
      case PinMode.confirmCurrent:
        return 'pin.current_title'.tr();
    }
  }

  @override
  Widget build(BuildContext context) {
    // unlock rejimida ortga qaytish yo'q: aks holda qulf ma'nosini
    // yo'qotardi — "ortga" bosib ichkariga kirib bo'lardi.
    return PopScope(
      canPop: widget.mode != PinMode.unlock,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: widget.mode == PinMode.unlock
            ? null
            : AppBar(
                backgroundColor: AppColors.white,
                elevation: 0,
                foregroundColor: AppColors.black,
              ),
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Icon(Icons.lock_outline_rounded,
                  size: 46, color: AppColors.primaryGreen),
              const SizedBox(height: 18),
              Text(
                _title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.black),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 20,
                child: _error == null
                    ? Text('pin.hint'.tr(),
                        style: const TextStyle(fontSize: 13, color: AppColors.grey))
                    : Text(_error!,
                        style: const TextStyle(fontSize: 13, color: AppColors.error)),
              ),
              const SizedBox(height: 26),
              _dots(),
              const Spacer(),
              _keypad(),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(PinService.pinLength, (i) {
        final filled = i < _entered.length;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 9),
          width: 15,
          height: 15,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? AppColors.primaryGreen : Colors.transparent,
            border: Border.all(
              color: filled ? AppColors.primaryGreen : Colors.black26,
              width: 1.5,
            ),
          ),
        );
      }),
    );
  }

  Widget _keypad() {
    final rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        children: [
          for (final row in rows)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final d in row) _digitButton(d)],
            ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sideButton(
                icon: Icons.fingerprint_rounded,
                onTap: widget.mode == PinMode.unlock ? _tryBiometricManually : null,
              ),
              _digitButton('0'),
              _sideButton(icon: Icons.backspace_outlined, onTap: _onBackspace),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _tryBiometricManually() async {
    _biometricOffered = false;
    await _tryBiometric();
  }

  Widget _digitButton(String digit) {
    return _tapTarget(
      onTap: () => _onDigit(digit),
      child: Text(digit,
          style: const TextStyle(
              fontSize: 26, fontWeight: FontWeight.w500, color: AppColors.black)),
    );
  }

  Widget _sideButton({required IconData icon, VoidCallback? onTap}) {
    return _tapTarget(
      onTap: onTap,
      child: Icon(icon,
          size: 24, color: onTap == null ? Colors.transparent : AppColors.grey),
    );
  }

  Widget _tapTarget({required Widget child, VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(width: 72, height: 66, child: Center(child: child)),
      ),
    );
  }
}


/// Kirishdan keyin PIN o'rnatishni BIR MARTA taklif qiladi.
///
/// Majburlamaymiz: kimdir kodni xohlamaydi, va uni zo'rlab qo'yish kirishni
/// og'irlashtiradi. Rad etgan odam sozlamalardan istagan payt qo'ya oladi,
/// shuning uchun taklif qayta chiqmaydi.
Future<void> offerPinSetup(BuildContext context) async {
  const shownKey = 'pin_offer_shown';
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(shownKey) ?? false) return;
  if (await PinService.hasPin()) return;
  await prefs.setBool(shownKey, true);

  if (!context.mounted) return;
  final wants = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('pin.offer_title'.tr()),
      content: Text('pin.offer_body'.tr()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text('pin.offer_later'.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text('pin.offer_set'.tr()),
        ),
      ],
    ),
  );
  if (wants != true || !context.mounted) return;

  await Navigator.of(context).push<bool>(
    MaterialPageRoute(builder: (_) => const PinPage(mode: PinMode.create)),
  );
}
