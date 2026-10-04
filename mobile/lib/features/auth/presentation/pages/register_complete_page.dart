import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
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
  final _nameCtrl = TextEditingController();
  final AuthRepository _authRepository = AuthRepository();
  bool _loading = false;

  Future<void> _completeRegistration() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);
    try {
      // 1. Ro'yxatdan o'tish. Javobda DARHOL kirish tokeni keladi:
      //    raqam SMS kodi bilan oldingi qadamda tasdiqlangan, ikkinchi
      //    marta kod so'rash ortiqcha (va ortiqcha SMS puli).
      final result = await _authRepository.register(
        fullName: _nameCtrl.text.trim(),
        phone: widget.phone,
        role: widget.role,
      );

      if (!mounted) return;

      // 2. Muvaffaqiyatli xabar
      toastification.show(
        context: context,
        type: ToastificationType.success,
        style: ToastificationStyle.flatColored,
        title: Text('messages.registration_success'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );

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
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => context.pop(),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const SizedBox(height: 20),
                _buildProfileIcon(),
                const SizedBox(height: 20),
                _buildHeader(context),
                const SizedBox(height: 30),
                _buildForm(),
                const SizedBox(height: 25),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProfileIcon() {
    return Container(
      width: 100,
      height: 100,
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
      child: const Icon(Icons.person_add, size: 50, color: Colors.white),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      children: [
        Text(
          'auth.fill_information'.tr(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'auth.complete_registration'.tr(),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildTextField(_nameCtrl, 'auth.full_name'.tr(), Icons.person),
          const SizedBox(height: 30),
          _loading
              ? const CircularProgressIndicator(color: AppColors.primaryGreen)
              : _buildGradientButton('auth.register_button'.tr(), _completeRegistration),
        ],
      ),
    );
  }

  Widget _buildTextField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    bool obscure = false,
    bool required = true,
  }) {
    return TextFormField(
      controller: ctrl,
      obscureText: obscure,
      validator: (v) {
        if (required && (v == null || v.isEmpty)) {
          return 'messages.enter_field'.tr(args: [hint]);
        }
        return null;
      },
      style: const TextStyle(fontSize: 16),
      decoration: InputDecoration(
        prefixIcon: Icon(icon, color: AppColors.primaryGreen),
        hintText: hint,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
        ),
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
          gradient: const LinearGradient(
            colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.white,
              ),
        ),
      ),
    );
  }
}

