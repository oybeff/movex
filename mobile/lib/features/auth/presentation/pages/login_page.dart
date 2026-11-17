import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:movex_go/core/theme/app_tokens.dart';
import 'package:movex_go/core/widgets/phone_input_field.dart';
import 'package:movex_go/features/auth/data/repositories/auth_repository.dart';
import 'package:movex_go/core/utils/error_handler.dart';
import 'package:movex_go/features/auth/presentation/widgets/auth_header.dart';
import 'package:movex_go/features/auth/presentation/widgets/auth_ui.dart';

/// Ekran: telefon raqamini kiritish.
///
/// Ko'rinishi ikkinchi maketdan (mijoz fayli, «A1–A3 · Telefon»): tepada
/// logotip va til tugmasi, sarlavha, bitta maydon — "+998" uning ichida,
/// ajratgich chiziq bilan. Raqam to'liq bo'lmaguncha tugma o'chiq va ustida
/// "Raqamni to'liq kiriting" turadi. Xato — maydon ostida, oyna emas.
///
/// Mantiq o'zgarmagan — o'sha [AuthRepository.sendOTP] va o'sha yo'nalish
/// `/otp-verification` ga. Yangi raqamni kod ekrani o'zi ro'yxatdan
/// o'tkazishga olib boradi, shuning uchun "Ro'yxatdan o'tish" havolasi
/// maketdagidek olib tashlandi: yo'l bitta («bitta oqim»).
class LoginPage extends StatefulWidget {
  const LoginPage({super.key, this.role});

  /// Boshida tanlangan rol ('client' yoki 'owner').
  ///
  /// Kirishga TA'SIR QILMAYDI: mavjud odamning roli serverdan keladi.
  /// U faqat ro'yxatdan o'tishga uzatiladi — shu ekran orqali o'tiladi.
  final String? role;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneCtrl = TextEditingController();
  final _focus = FocusNode();
  final AuthRepository _authRepository = AuthRepository();

  bool _loading = false;

  /// Maydon ostidagi xato matni. `null` — xato yo'q.
  String? _error;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => setState(() {}));
    _phoneCtrl.addListener(() {
      // Odam raqamni tuzata boshlasa, eski xato endi to'g'ri emas.
      if (_error != null) _error = null;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _complete => normalizeUzbekPhoneDigits(_phoneCtrl.text).length == 9;

  Future<void> _sendOTP() async {
    // Raqam [normalizeUzbekPhoneDigits] orqali ajratiladi, ya'ni qo'yilgan
    // "+998901234567" ham to'g'ri tushuniladi.
    if (!_complete || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authRepository.sendOTP(
        phone: _phoneCtrl.text.trim(),
        language: context.locale.languageCode,
      );

      if (!mounted) return;

      context.push('/otp-verification', extra: {
        'phoneNumber': formatPhoneNumber(_phoneCtrl.text.trim()),
        'isRegistration': false,
        // Rol ham uzatiladi: raqam yangi bo'lsa, kod ekrani odamni
        // ro'yxatdan o'tkazishga olib boradi va unga rol kerak.
        'role': widget.role,
      });
    } catch (e) {
      if (!mounted) return;
      // Maketda xato oynada emas, maydon ostida (A3).
      setState(() => _error = getErrorMessage(e));
    } finally {
      if (mounted) setState(() => _loading = false);
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
              // Orqaga yo'l faqat qaytadigan joy bo'lsa: aks holda iPhone da
              // rol tanlashga qaytishning umuman iloji yo'q edi.
              AuthHeader(
                onBack: Navigator.of(context).canPop()
                    ? () => Navigator.of(context).maybePop()
                    : null,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.lg,
                    AppSpacing.gutter,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('auth.phone_title'.tr(), style: authTitleStyle),
                      const SizedBox(height: AppSpacing.sm),
                      Text('auth.phone_subtitle'.tr(), style: authSubtitleStyle),
                      const SizedBox(height: AppSpacing.xl),
                      _buildField(),
                      if (_error != null) ...[
                        const SizedBox(height: 6),
                        AuthFieldError(_error!),
                      ],
                    ],
                  ),
                ),
              ),
              _buildBottom(),
            ],
          ),
        ),
      ),
    );
  }

  /// Maket: "Auth/Telefon input" — 56 px, radius lg, ichida "+998",
  /// ajratgich va raqam. Bo'sh — kulrang; fokusda — oq, ko'k ramka;
  /// xatoda — pushti fon, qizil ramka.
  Widget _buildField() {
    final focused = _focus.hasFocus;
    final hasError = _error != null;
    final Color bg;
    final Border? border;
    if (hasError) {
      bg = AppPalette.dangerSubtle;
      border = Border.all(color: AppPalette.borderDanger, width: 1.5);
    } else if (focused) {
      bg = AppPalette.surface;
      border = Border.all(color: AppPalette.borderFocus, width: 1.5);
    } else {
      bg = AppPalette.page;
      border = null;
    }

    return GestureDetector(
      onTap: _focus.requestFocus,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: AppSpacing.fieldHeight,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: border,
        ),
        child: Row(
          children: [
            Text('+998', style: _fieldText.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(width: AppSpacing.md),
            Container(width: 1, height: 24, color: AppPalette.borderDefault),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PhoneInputField(
                controller: _phoneCtrl,
                focusNode: _focus,
                autofocus: true,
                // "+998" maydon ichida, chap tomonda — matnda takrorlanmaydi.
                showInlinePrefix: false,
                groupDigits: true,
                style: _fieldText,
                cursorColor: AppPalette.brand,
                validator: (_) => null,
                onSubmitted: _sendOTP,
                decoration: InputDecoration(
                  hintText: '00 000 00 00',
                  hintStyle: _fieldText.copyWith(
                    color: AppPalette.textPlaceholder,
                    fontWeight: FontWeight.w400,
                  ),
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static const TextStyle _fieldText = TextStyle(
    fontFamily: AppTypography.fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    color: AppPalette.textPrimary,
  );

  Widget _buildBottom() {
    final enabled = _complete && !_loading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.sm,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Maket A1: tugma nega o'chiqligi shu yerda yozilgan.
          if (!_complete) ...[
            Text(
              'auth.enter_full_phone'.tr(),
              style: AppTypography.captionS,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          AuthPrimaryButton(
            label: 'auth.get_code'.tr(),
            loading: _loading,
            onPressed: enabled ? _sendOTP : null,
          ),
        ],
      ),
    );
  }
}
