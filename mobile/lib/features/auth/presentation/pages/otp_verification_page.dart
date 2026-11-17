import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../data/repositories/auth_repository.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_ui.dart';
import 'pin_page.dart';

class OTPVerificationPage extends StatefulWidget {
  final String phoneNumber;
  final bool isRegistration; // true if coming from registration, false if from login
  final String? role; // role for registration flow

  const OTPVerificationPage({
    Key? key,
    required this.phoneNumber,
    this.isRegistration = false,
    this.role,
  }) : super(key: key);

  @override
  State<OTPVerificationPage> createState() => _OTPVerificationPageState();
}

class _OTPVerificationPageState extends State<OTPVerificationPage> {
  final List<TextEditingController> _controllers = List.generate(
    4,
    (index) => TextEditingController(),
  );
  final List<FocusNode> _focusNodes = List.generate(
    4,
    (index) => FocusNode(),
  );

  final AuthRepository _authRepository = AuthRepository();
  bool _loading = false;
  bool _hasError = false;
  String _errorMessage = '';
  int _resendTimer = 60;
  bool _canResend = false;
  Timer? _timer;

  /// KeyboardListener uchun alohida fokus tugunlari: matn maydoniniki
  /// bilan bitta tugunni baham ko'rib bo'lmaydi.
  final List<FocusNode> _keyNodes = List.generate(4, (_) => FocusNode());

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Auto-focus first field
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNodes[0].requestFocus();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    for (var node in _keyNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _startResendTimer() {
    _resendTimer = 60;
    _canResend = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_resendTimer > 0) {
          _resendTimer--;
        } else {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _verifyOTP() async {
    final otp = _controllers.map((c) => c.text).join();
    
    if (otp.length != 4) {
      setState(() {
        _hasError = true;
        _errorMessage = 'messages.enter_4_digit_code'.tr();
      });
      return;
    }

    setState(() {
      _loading = true;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final result = await _authRepository.verifyOTP(
        phone: widget.phoneNumber,
        otpCode: otp,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // If this is registration flow, continue to complete registration
        // Qaysi yo'l — SERVER javobi hal qiladi, odam qaysi tugmadan
        // kelgani emas.
        //
        // Ilgari bu yerda `isRegistration` bayrog'i hal qilardi. Odam
        // "Mijoz" tugmasini bosib KIRISH ekraniga tushardi va yangi raqam
        // kiritardi: server "raqam tasdiqlandi, ro'yxatdan o'ting" deb
        // tokensiz javob berardi, ilova esa buni kirish deb hisoblab PIN
        // so'rardi va boshlang'ich ekranga qaytarardi. Hisob hech qachon
        // yaratilmasdi — har urinish yangi SMS va yana o'sha aylanma.
        //
        // Endi: token keldi — hisob bor, PIN va ichkariga. Token yo'q —
        // hisob yo'q, ism-familiya, keyin PIN.
        final hasAccount = result['token'] != null;
        if (!hasAccount) {
          context.pushReplacement('/register-complete', extra: {
            'phone': widget.phoneNumber,
            'role': widget.role ?? 'client',
          });
        } else {
          // Kirish endi saqlanadi va qaytadan so'ralmaydi, shuning uchun
          // PIN kod MAJBURIY: ilovani himoya qiladigan yagona narsa shu.
          await requirePinSetup(context);
          if (!mounted) return;
          // If this is login flow, navigate to home based on role
          final role = result['role'];
          if (role == 'client') {
            context.go('/clientHome');
          } else if (role == 'owner') {
            context.go('/ownerHome');
          } else {
            context.go('/');
          }
        }
      }
    } catch (e) {
      if (!mounted) return;

      // Maket B4: xato oynada emas — kataklar qizil, ostida matn.
      // Raqamlar ko'rinib turadi (odam nimani yozganini ko'rsin), birinchi
      // katak belgilanadi: keyingi bosilgan raqam kodni boshidan boshlaydi.
      setState(() {
        _hasError = true;
        _errorMessage = getErrorMessage(e);
        _loading = false;
      });
      // Fokus KEYINGI kadrda: tekshiruv paytida kataklar o'chiq edi, va
      // o'chiq maydon fokus olmaydi — darhol so'ralsa, so'rov yo'qolardi
      // va odam yangi kodni yoza olmasdi.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _focusNodes[0].requestFocus();
        _controllers[0].selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controllers[0].text.length,
        );
      });
    }
  }

  Future<void> _resendOTP() async {
    if (!_canResend) return;

    setState(() => _loading = true);

    try {
      await _authRepository.sendOTP(
        phone: widget.phoneNumber,
        language: context.locale.languageCode,
      );
      
      if (!mounted) return;
      for (final c in _controllers) {
        c.clear();
      }
      _focusNodes[0].requestFocus();
      // Sanagich qaytadan boshlangani — kod ketganining belgisi (maket B1).
      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
        _errorMessage = getErrorMessage(e);
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value, int index) {
    // Xatodan keyin birinchi bosilgan raqam — yangi urinish: eski kod
    // tozalanadi (sxemada «B4 Noto'g'ri kod → tozalash»).
    if (_hasError) {
      for (var i = 0; i < _controllers.length; i++) {
        if (i != index) _controllers[i].clear();
      }
    }
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    // BIR NECHTA raqam kelsa — kod to'liq joylangan (SMS dan avtomatik
    // to'ldirish yoki buferdan qo'yish). Ilgari maydon faqat bittasini
    // olardi, qolgani yo'qolardi va odam kodni qo'lda ko'chirardi.
    if (value.length > 1) {
      _fillFromCode(value);
      return;
    }

    if (value.isNotEmpty && index < 3) {
      _focusNodes[index + 1].requestFocus();
    }

    // Raqam O'CHIRILGANDA fokus oldingi maydonga qaytadi.
    //
    // Bu yerda eng achinarli xato bor edi: _onBackspace yozilgan, lekin
    // HECH QAYERDAN chaqirilmasdi. Raqamni o'chirgan odam bo'sh maydonda
    // qolardi va har safar oldingi katakka barmoq bilan tegishi kerak
    // bo'lardi — "klaviatura ishlamayapti" deb aynan shu tuyulardi.
    if (value.isEmpty && index > 0) {
      _focusNodes[index - 1].requestFocus();
    }

    if (index == 3 && value.isNotEmpty) {
      final allFilled = _controllers.every((c) => c.text.isNotEmpty);
      if (allFilled) {
        _verifyOTP();
      }
    }
  }

  /// To'liq kodni kataklarga yoyadi va tekshirishni boshlaydi.
  void _fillFromCode(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    for (var i = 0; i < 4; i++) {
      _controllers[i].text = i < digits.length ? digits[i] : '';
    }
    final filled = digits.length.clamp(0, 4);
    if (filled >= 4) {
      _focusNodes[3].unfocus();
      _verifyOTP();
    } else {
      _focusNodes[filled].requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: AppPalette.surface,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppPalette.surface,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthHeader(onBack: () => context.pop()),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    AppSpacing.lg,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('auth.otp_title'.tr(), style: authTitleStyle),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'auth.otp_subtitle'.tr(args: [
                          formatPhoneNumberGrouped(widget.phoneNumber),
                        ]),
                        style: authSubtitleStyle,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Maket: «Raqamni o'zgartirish» — oldingi ekranga.
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Text(
                          'auth.change_number'.tr(),
                          style: _linkStyle,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                      _buildOTPFields(),
                      const SizedBox(height: AppSpacing.lg),
                      if (_loading)
                        _buildChecking()
                      else ...[
                        if (_hasError) ...[
                          AuthFieldError(_errorMessage),
                          const SizedBox(height: AppSpacing.lg),
                        ],
                        _buildResend(),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const TextStyle _linkStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: AppPalette.textBrand,
  );

  static const TextStyle _hintStyle = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 15,
    fontWeight: FontWeight.w500,
    color: AppPalette.textSecondary,
  );

  /// Maket B3: «Tekshirilmoqda...» va kichik aylana.
  Widget _buildChecking() => Row(
        children: [
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppPalette.brand,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            'auth.checking'.tr(),
            style: _hintStyle.copyWith(color: AppPalette.textBrand),
          ),
        ],
      );

  /// Maket B1/B5: sanagich tugaguncha «Kodni qayta yuborish: 0:59»
  /// kulrang matn, tugagach — o'sha so'zlar ko'k havola.
  Widget _buildResend() {
    if (_canResend) {
      return GestureDetector(
        onTap: _resendOTP,
        child: Text('auth.resend_code'.tr(), style: _linkStyle),
      );
    }
    final m = _resendTimer ~/ 60;
    final ss = (_resendTimer % 60).toString().padLeft(2, '0');
    return Text(
      '${'auth.resend_code'.tr()}: $m:$ss',
      style: _hintStyle,
    );
  }

  Widget _buildOTPFields() {
    // Maketda kataklar OLTITA, server esa TO'RT xonali kod yuboradi
    // (verify_otp_security shuni tekshiradi), shuning uchun bu yerda
    // to'rtta — o'lchami va oralig'i maketdagidek (48×56, 8).
    return Row(
      children: List.generate(_controllers.length, (index) {
        return Padding(
          padding: EdgeInsets.only(
            right: index == _controllers.length - 1 ? 0 : AppSpacing.sm,
          ),
          child: SizedBox(
            width: 48,
            height: AppSpacing.fieldHeight,
            // BO'SH katakda "o'chirish" bosilganda onChanged ishlamaydi:
            // matn o'zgarmagan, demak hodisa ham yo'q. Shuning uchun
            // tugmaning o'zini ushlaymiz va fokusni oldingi katakka
            // qaytaramiz.
            child: KeyboardListener(
              focusNode: _keyNodes[index],
              onKeyEvent: (event) {
                if (event is! KeyDownEvent) return;
                if (event.logicalKey != LogicalKeyboardKey.backspace) return;
                if (_controllers[index].text.isNotEmpty) return;
                if (index == 0) return;
                _controllers[index - 1].clear();
                _focusNodes[index - 1].requestFocus();
              },
              child: _OtpCell(
                controller: _controllers[index],
                focusNode: _focusNodes[index],
                hasError: _hasError,
                enabled: !_loading,
                autofill: index == 0,
                onChanged: (value) => _onChanged(value, index),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Bitta katak. Maket «Auth/OTP cell»: bo'sh — kulrang, fokusda — oq va
/// ko'k ramka, xatoda — pushti va qizil ramka, raqam 24 Semibold.
class _OtpCell extends StatelessWidget {
  const _OtpCell({
    required this.controller,
    required this.focusNode,
    required this.hasError,
    required this.enabled,
    required this.autofill,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool hasError;
  final bool enabled;
  final bool autofill;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        final Color fill;
        final Color? borderColor;
        if (hasError) {
          fill = AppPalette.dangerSubtle;
          borderColor = AppPalette.borderDanger;
        } else if (focused) {
          fill = AppPalette.surface;
          borderColor = AppPalette.borderFocus;
        } else {
          fill = AppPalette.page;
          borderColor = null;
        }
        final side = borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor, width: 1.5);
        final shape = OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: side,
        );
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          textAlign: TextAlign.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          cursorColor: AppPalette.brand,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: hasError ? AppPalette.textDanger : AppPalette.textPrimary,
          ),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: fill,
            contentPadding: EdgeInsets.zero,
            border: shape,
            enabledBorder: shape,
            disabledBorder: shape,
            focusedBorder: shape,
          ),
          // SMS dagi kodni telefon o'zi taklif qiladi — bir tegishda
          // hamma katak to'ladi.
          autofillHints: autofill ? const [AutofillHints.oneTimeCode] : null,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onChanged: onChanged,
          // Katakka tegilganda u TOZALANMAYDI, faqat kursor oxiriga o'tadi.
          onTap: () {
            controller.selection = TextSelection.fromPosition(
              TextPosition(offset: controller.text.length),
            );
          },
        );
      },
    );
  }
}
