import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import 'package:movex_go/core/widgets/phone_input_field.dart';
import 'package:movex_go/features/auth/data/repositories/auth_repository.dart';
import 'package:movex_go/core/utils/error_handler.dart';

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
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  final AuthRepository _authRepository = AuthRepository();

  bool _loading = false;

  Future<void> _sendOTP() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      final result = await _authRepository.sendOTP(
        phone: _phoneCtrl.text.trim(),
        language: context.locale.languageCode,
      );

      if (!mounted) return;

      toastification.show(
        context: context,
        type: ToastificationType.success,
        style: ToastificationStyle.flatColored,
        title: Text(result['message'] ?? 'messages.otp_sent'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );

      // Navigate to OTP verification page
      context.push('/otp-verification', extra: {
        'phoneNumber': formatPhoneNumber(_phoneCtrl.text.trim()),
        'isRegistration': false,
      });
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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        // Ortga qaytish tugmasi: bu ekranga rol tanlashdan kelinadi, va
        // rolni almashtirmoqchi bo'lgan odam uchun yo'l yo'q edi —
        // faqat Android jesti ishlardi, iPhone da esa umuman hech narsa.
        // Tugma faqat qaytadigan joy bo'lsa ko'rinadi.
        appBar: Navigator.of(context).canPop()
            ? AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                foregroundColor: AppColors.black,
                systemOverlayStyle: SystemUiOverlayStyle.dark,
              )
            : null,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 40),
                _buildProfileIcon(),
                const SizedBox(height: 20),
                _buildHeader(context),
                const SizedBox(height: 30),
                _buildForm(),
                const SizedBox(height: 25),
                TextButton(
                  onPressed: () =>
                      context.pushReplacement('/register', extra: widget.role),
                  child: Text('auth.no_account'.tr() + ' ' + 'auth.register_button'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileIcon() => Container(
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withOpacity(0.3),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: const Icon(Icons.lock_open, size: 80, color: AppColors.white),
      );

  Widget _buildHeader(BuildContext context) => Column(
        children: [
          Text('auth.welcome_back'.tr(),
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('auth.login_subtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      );

  Widget _buildForm() => Form(
        key: _formKey,
        child: Column(
          children: [
            PhoneInputField(
              controller: _phoneCtrl,
              hintText: '+998 901234567',
              prefixIcon: Icons.phone,
              // Klaviaturadagi "Tayyor" — ekrandagi tugmani qidirmasdan
              // davom etish uchun.
              onSubmitted: _loading ? null : _sendOTP,
            ),
            const SizedBox(height: 30),
            _loading
                ? const CircularProgressIndicator(color: AppColors.primaryGreen)
                : _buildGradientButton('auth.continue'.tr(), _sendOTP),
          ],
        ),
      );

  Widget _buildGradientButton(String text, VoidCallback onPressed) => InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          width: double.infinity,
          height: 55,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(text,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(fontSize: 17)
                  .copyWith(fontWeight: FontWeight.bold, color: AppColors.white)),
        ),
      );
}
