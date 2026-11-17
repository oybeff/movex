import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../../core/utils/error_handler.dart';
import '../widgets/auth_header.dart';
import '../widgets/auth_ui.dart';
import 'pin_page.dart';
import '/features/auth/data/repositories/auth_repository.dart';

class RegisterCompletePage extends StatefulWidget {
  final String phone;
  final String role;

  const RegisterCompletePage({
    Key? key,
    required this.phone,
    required this.role,
  }) : super(key: key);

  @override
  State<RegisterCompletePage> createState() => _RegisterCompletePageState();
}

class _RegisterCompletePageState extends State<RegisterCompletePage> {
  final _formKey = GlobalKey<FormState>();

  // Maketda ikkita maydon: "Ism" va "Familiya". Serverga esa baribir BITTA
  // satr ketadi (`fullName`) — API o'zgarmagan, faqat kiritish bo'lingan.
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  final AuthRepository _authRepository = AuthRepository();
  bool _loading = false;

  /// Rozilik belgisi — maketda belgilangan holatda turadi.
  bool _agreed = true;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // Ikki maydon bitta satrga yig'iladi. Familiya bo'sh bo'lsa ortiqcha
      // bo'shliq qolmasligi uchun trim qilinadi — aks holda serverga
      // "Abror " kabi nom ketardi va ro'yxatlarda shunday ko'rinardi.
      final fullName =
          '${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'.trim();

      // 1. Ro'yxatdan o'tish. Javobda DARHOL kirish tokeni keladi:
      //    raqam SMS kodi bilan oldingi qadamda tasdiqlangan, ikkinchi
      //    marta kod so'rash ortiqcha (va ortiqcha SMS puli).
      final result = await _authRepository.register(
        fullName: fullName,
        phone: widget.phone,
        role: widget.role,
      );

      if (!mounted) return;

      // 2. Xabar ko'rsatilmaydi: maketda bu yerdan to'g'ri PIN ekraniga
      //    o'tiladi, va tepadagi bildirishnoma shapkani yopib qo'yardi.

      // 3. PIN kod — MAJBURIY. Keyingi kirishlarda SMS so'ralmaydi,
      //    shuning uchun ilovani himoya qiladigan narsa aynan shu kod
      //    (va u o'rnatilgach — barmoq izi / Face ID).
      await requirePinSetup(context);
      if (!mounted) return;

      // 4. Rolga qarab ichkariga. Ilgari bu yer '/login' ga qaytarardi:
      //    odam qaytadan kod so'rab, SMS ikki marta kelardi.
      final role = result['role'];
      if (role == 'owner') {
        context.go('/ownerHome');
      } else if (role == 'client') {
        context.go('/clientHome');
      } else {
        context.go('/');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      // Show error dialog
      showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Ism-familiya ekrani ikkinchi maketda YO'Q (mijoz u yerda darhol PIN ga
    // o'tadi), lekin egasi uni qoldirishni so'radi. Ko'rinish maketning
    // qolgan kirish ekranlaridan va egasi faylidagi «R3 · Shaxsiy
    // ma'lumotlar» dan olingan: o'sha shapka, sarlavha, Input komponenti.
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
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AuthHeader(),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.gutter,
                      AppSpacing.lg,
                      AppSpacing.gutter,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('auth.fill_information'.tr(),
                            style: authTitleStyle),
                        const SizedBox(height: AppSpacing.sm),
                        Text('auth.complete_registration'.tr(),
                            style: authSubtitleStyle),
                        const SizedBox(height: AppSpacing.xl),
                        _buildField(_firstNameCtrl, 'auth.first_name'.tr(),
                            next: true),
                        const SizedBox(height: AppSpacing.md),
                        _buildField(_lastNameCtrl, 'auth.last_name'.tr()),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.gutter,
                    AppSpacing.sm,
                    AppSpacing.gutter,
                    AppSpacing.md,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildAgreement(),
                      const SizedBox(height: AppSpacing.lg),
                      AuthPrimaryButton(
                        label: 'auth.continue'.tr(),
                        loading: _loading,
                        onPressed: _agreed ? _completeRegistration : null,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Design System «Input»: kulrang, ramkasiz, 56 px, ichki (suzuvchi)
  /// yorliq. Ko'rinish mavzudan keladi (AppTheme.inputDecorationTheme).
  Widget _buildField(
    TextEditingController ctrl,
    String label, {
    bool next = false,
  }) {
    return TextFormField(
      controller: ctrl,
      // Birinchi maydondan — ikkinchisiga, ikkinchisidan — yuborishga.
      textInputAction: next ? TextInputAction.next : TextInputAction.done,
      textCapitalization: TextCapitalization.words,
      onFieldSubmitted:
          next ? null : (_) => _loading ? null : _completeRegistration(),
      validator: (v) {
        if (v == null || v.trim().isEmpty) {
          return 'messages.enter_field'.tr(args: [label]);
        }
        return null;
      },
      style: AppTypography.bodyMedium,
      cursorColor: AppPalette.brand,
      decoration: InputDecoration(labelText: label),
    );
  }

  /// Rozilik. Design System «Checkbox»: 20 px, radius 6, belgilangan —
  /// ko'k fon, oq galochka.
  Widget _buildAgreement() => GestureDetector(
        onTap: () => setState(() => _agreed = !_agreed),
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: Checkbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
                activeColor: AppPalette.brand,
                checkColor: AppPalette.textOnBrand,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                side: const BorderSide(
                  color: AppPalette.borderStrong,
                  width: 1.5,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('auth.agreement'.tr(), style: AppTypography.captionS),
            ),
          ],
        ),
      );
}
