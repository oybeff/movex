import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/phone_input_field.dart';
import '../../../../core/utils/error_handler.dart';
import '/features/auth/data/repositories/auth_repository.dart';

class RegisterPage extends StatefulWidget {
  final String role;
  const RegisterPage({super.key, required this.role});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
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
        'isRegistration': true,
        'role': widget.role,
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
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                _buildProfileIcon(),
                const SizedBox(height: 20),
                _buildHeader(context),
                const SizedBox(height: 30),
                _buildForm(),
                const SizedBox(height: 25),
                TextButton(
                  onPressed: () => context.pushReplacement('/login'),
                  child: Text('${'auth.have_account'.tr()}? ${'auth.login_button'.tr()}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileIcon() {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(color: AppColors.primaryGreen.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 5)),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: const Icon(Icons.person_add, size: 80, color: AppColors.white),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text('auth.register'.tr(), style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text('auth.register_subtitle'.tr(), style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          PhoneInputField(
            controller: _phoneCtrl,
            hintText: '+998 901234567',
            prefixIcon: Icons.phone,
          ),
          const SizedBox(height: 30),
          _loading
              ? const CircularProgressIndicator(color: AppColors.primaryGreen)
              : _buildGradientButton('auth.continue'.tr(), _sendOTP),
        ],
      ),
    );
  }

  Widget _buildGradientButton(String text, VoidCallback onPressed) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        height: 55,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [AppColors.primaryGreen, AppColors.secondaryGreen], begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(color: AppColors.primaryGreen.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))],
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.white)),
      ),
    );
  }
}
