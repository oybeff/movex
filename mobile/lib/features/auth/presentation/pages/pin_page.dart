import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/repositories/auth_repository.dart';
import 'otp_verification_page.dart';

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
  const PinPage({
    super.key,
    required this.mode,
    this.onSuccess,
    this.mandatory = false,
  });

  final PinMode mode;

  /// Majburiy o'rnatish: ortga qaytish yo'q va AppBar ko'rsatilmaydi.
  /// Ro'yxatdan o'tishda PIN kod shart — usiz ilovaga kirib bo'lmaydi.
  final bool mandatory;

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

  /// "PIN kodni unutdingizmi?" — SMS OTP orqali tiklash.
  ///
  /// Odam allaqachon tizimga kirgan (token bor), faqat PIN bilan
  /// bloklangan. Shuning uchun: telefonini profildan olamiz, eski PINni
  /// o'chiramiz, SMS kod yuboramiz va OTP ekraniga o'tamiz. OTP muvaffaqiyatli
  /// bo'lgach, o'sha ekran yangi PIN o'rnatishni taklif qiladi va ichkariga
  /// kiritadi — ya'ni tiklashning alohida oxiri kerak emas.
  Future<void> _forgotPin() async {
    setState(() => _error = null);
    // Tilni async chaqiruvdan OLDIN olamiz: keyin context ishlatish
    // (await'dan so'ng) flutter ogohlantirishi beradi.
    final language = context.locale.languageCode;
    try {
      final user = await UserService().getCurrentUser();
      final phone = user.phone;
      if (phone == null || phone.isEmpty) {
        if (mounted) setState(() => _error = 'pin.reset_no_phone'.tr());
        return;
      }

      // Eski PINni O'CHIRAMIZ: OTP o'tgach ekran yangisini so'raydi, va
      // odam eski unutilgan kod bilan qulflanib qolmaydi.
      await PinService.clearPin();
      await AuthRepository().sendOTP(phone: phone, language: language);
      if (!mounted) return;

      // OTP ekrani login rejimida: kod tasdiqlangach yangi PIN taklif
      // qilinadi va bosh ekranga o'tkazadi.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => OTPVerificationPage(phoneNumber: phone),
        ),
      );
    } catch (e) {
      if (mounted) showErrorDialog(context, e);
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
      // Qulf rejimida ham, majburiy o'rnatishda ham ortga qaytish yo'q:
      // aks holda "ortga" bosib PIN kodsiz ichkariga kirib bo'lardi.
      canPop: widget.mode != PinMode.unlock && !widget.mandatory,
      child: Scaffold(
        backgroundColor: AppColors.white,
        appBar: (widget.mode == PinMode.unlock || widget.mandatory)
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
              // "Unutdingizmi?" faqat qulf rejimida: create/confirm da
              // odam kodni endigina kiritmoqda, tiklash u yerda ortiqcha.
              if (widget.mode == PinMode.unlock)
                TextButton(
                  onPressed: _forgotPin,
                  child: Text(
                    'pin.forgot'.tr(),
                    style: const TextStyle(fontSize: 14, color: AppColors.primaryGreen),
                  ),
                ),
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


/// PIN kodni MAJBURIY o'rnatish.
///
/// Ro'yxatdan o'tgandan va kirgandan keyin chaqiriladi. Ilgari bu taklif
/// edi ("keyinroq" tugmasi bilan), va PIN qo'ymagan odam ilovaga har
/// safar hech narsa so'ralmasdan kirardi. Endi kirish oqimi bitta:
/// raqamni SMS bilan tasdiqlash, so'ng PIN kod — keyingi kirishlarda
/// faqat PIN (yoki barmoq izi).
Future<void> requirePinSetup(BuildContext context) async {
  if (await PinService.hasPin()) return;
  if (!context.mounted) return;

  // PIN o'rnatilmaguncha qaytarmaymiz: ekranni yopib bo'lmaydi, lekin
  // kutilmagan holatda (masalan tizim ekranni yopsa) qayta so'raymiz.
  while (!await PinService.hasPin()) {
    if (!context.mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const PinPage(mode: PinMode.create, mandatory: true),
        fullscreenDialog: true,
      ),
    );
  }
}
