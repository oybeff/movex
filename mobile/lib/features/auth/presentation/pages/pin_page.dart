import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/services/pin_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_ui.dart';
import 'otp_verification_page.dart';
import '../../../../core/widgets/h_icon.dart';

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
    final ok = await PinService.authenticateBiometric(
      'pin.biometric_reason'.tr(),
    );
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
        if (await PinService.biometricsAvailable()) {
          await PinService.setBiometricEnabled(true);
        }
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
        return _firstEntry == null
            ? 'pin.create_title'.tr()
            : 'pin.repeat_title'.tr();
      case PinMode.unlock:
        return 'pin.unlock_title'.tr();
      case PinMode.confirmCurrent:
        return 'pin.current_title'.tr();
    }
  }

  String get _subtitle {
    switch (widget.mode) {
      case PinMode.create:
        return _firstEntry == null
            ? 'pin.create_subtitle'.tr()
            : 'pin.repeat_subtitle'.tr();
      case PinMode.unlock:
        return 'pin.unlock_subtitle'.tr();
      case PinMode.confirmCurrent:
        return 'pin.hint'.tr();
    }
  }

  /// Shapkada nima turadi. Maket: C1 va D2 — logotip; C2 (takrorlash) —
  /// orqaga strelka, u birinchi kiritishga qaytaradi.
  VoidCallback? get _back {
    if (widget.mode == PinMode.create && _firstEntry != null) {
      return () => setState(() {
        _firstEntry = null;
        _entered = '';
        _error = null;
      });
    }
    if (widget.mode == PinMode.unlock || widget.mandatory) return null;
    return () => Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Qulf rejimida ham, majburiy o'rnatishda ham ortga qaytish yo'q:
      // aks holda "ortga" bosib PIN kodsiz ichkariga kirib bo'lardi.
      canPop: widget.mode != PinMode.unlock && !widget.mandatory,
      // Свой цвет системных панелей: без него экран наследовал тёмно-синюю
      // полосу навигации от онбординга и заставки.
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarBrightness: Brightness.light,
          statusBarIconBrightness: Brightness.dark,
          systemNavigationBarColor: AppPalette.surface,
          systemNavigationBarIconBrightness: Brightness.dark,
        ),
        child: Scaffold(
          backgroundColor: AppPalette.surface,
          // Ekran past bo'lsa pastki qismi KESILMAYDI: joy yetmasa ro'yxat
          // suriladi. Ilgari "PIN kodni unutdingizmi?" ekrandan chiqib
          // ketardi va kodni unutgan odam ilovaga umuman kira olmasdi.
          body: SafeArea(
            child: Column(
              children: [
                AuthHeader(onBack: _back),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: IntrinsicHeight(
                          child: Column(
                            children: [
                              const SizedBox(height: AppSpacing.s10),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.gutter,
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      _title,
                                      textAlign: TextAlign.center,
                                      style: authTitleStyle,
                                    ),
                                    const SizedBox(height: AppSpacing.sm),
                                    Text(
                                      _subtitle,
                                      textAlign: TextAlign.center,
                                      style: authSubtitleStyle,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xxl),
                              _dots(),
                              if (_error != null) ...[
                                const SizedBox(height: AppSpacing.xl),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.gutter,
                                  ),
                                  child: _errorLine(_error!),
                                ),
                              ],
                              const Spacer(),
                              _keypad(),
                              // "Unutdingizmi?" faqat qulf rejimida: create va
                              // confirm da odam kodni endigina kiritmoqda.
                              if (widget.mode == PinMode.unlock)
                                TextButton(
                                  onPressed: _forgotPin,
                                  child: Text('pin.forgot'.tr()),
                                )
                              else
                                const SizedBox(height: AppSpacing.sm),
                              const SizedBox(height: AppSpacing.sm),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Maket C3/D3: xato matni nuqtalar ostida, o'rtada.
  Widget _errorLine(String message) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const HIcon(
        Icons.error_outline_rounded,
        size: 14,
        color: AppPalette.textDanger,
      ),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: AppTypography.captionS.copyWith(color: AppPalette.textDanger),
        ),
      ),
    ],
  );

  /// Maket «Auth/PIN dot»: 16 px, to'ldirilgan — ko'k, bo'sh — border/default.
  /// Xatoda (C3, D3) to'rttasi ham qizil: odam kodni noto'g'ri kiritganini
  /// nuqtalarning o'zidan ko'radi, keyingi raqam bosilguncha.
  Widget _dots() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(PinService.pinLength, (i) {
        final Color color;
        if (_error != null) {
          color = AppPalette.textDanger;
        } else if (i < _entered.length) {
          color = AppPalette.brand;
        } else {
          color = AppPalette.borderDefault;
        }
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          margin: const EdgeInsets.symmetric(horizontal: 10),
          width: 16,
          height: 16,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        );
      }),
    );
  }

  /// Maket «Auth/PIN keypad»: tugma 96×64, oralig'i 24 (yonma-yon) va
  /// 8 (qatorlar). Raqam 28 Medium.
  Widget _keypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
    ];
    return Column(
      children: [
        for (final row in rows) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final d in row) ...[
                if (d != row.first) const SizedBox(width: AppSpacing.xl),
                _digitButton(d),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Maket D2: qulf ekranida chapda — biometriya. Boshqa
            // rejimlarda bo'sh joy (C1, C2).
            widget.mode == PinMode.unlock
                ? _sideButton(
                    icon: Theme.of(context).platform == TargetPlatform.iOS
                        ? Icons.face_outlined
                        : Icons.fingerprint_rounded,
                    onTap: _tryBiometricManually,
                    label: 'pin.biometric_reason'.tr(),
                  )
                : const SizedBox(width: 96, height: 64),
            const SizedBox(width: AppSpacing.xl),
            _digitButton('0'),
            const SizedBox(width: AppSpacing.xl),
            _sideButton(
              icon: Icons.backspace_outlined,
              onTap: _onBackspace,
              label: 'auth.delete'.tr(),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _tryBiometricManually() async {
    final canBio = await PinService.biometricsAvailable();
    if (!canBio) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('pin.biometric_desc'.tr())),
        );
      }
      return;
    }
    final ok = await PinService.authenticateBiometric(
      'pin.biometric_reason'.tr(),
    );
    if (ok && mounted) {
      await PinService.setBiometricEnabled(true);
      _finish();
    }
  }

  Widget _digitButton(String digit) {
    return _tapTarget(
      onTap: () => _onDigit(digit),
      label: digit,
      child: Text(
        digit,
        style: const TextStyle(
          fontFamily: AppTypography.fontFamily,
          fontSize: 28,
          fontWeight: FontWeight.w500,
          color: AppPalette.textPrimary,
        ),
      ),
    );
  }

  Widget _sideButton({
    required IconData icon,
    required VoidCallback onTap,
    required String label,
  }) {
    return _tapTarget(
      onTap: onTap,
      label: label,
      child: HIcon(icon, size: 28, color: AppPalette.iconPrimary),
    );
  }

  Widget _tapTarget({
    required Widget child,
    required VoidCallback onTap,
    required String label,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(32),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: AppPalette.brandSubtle,
          highlightColor: AppPalette.page,
          child: SizedBox(width: 96, height: 64, child: Center(child: child)),
        ),
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
