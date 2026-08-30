import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
import '../../data/repositories/auth_repository.dart';

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
        if (widget.isRegistration) {
          context.pushReplacement('/register-complete', extra: {
            'phone': widget.phoneNumber,
            'role': widget.role ?? 'client',
          });
        } else {
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

      setState(() {
        _hasError = true;
        _errorMessage = getErrorMessage(e);
        _loading = false;
      });

      // Show error dialog
      showErrorDialog(context, e);

      // Clear all fields on error
      for (var controller in _controllers) {
        controller.clear();
      }
      _focusNodes[0].requestFocus();
    }
  }

  Future<void> _resendOTP() async {
    if (!_canResend) return;

    setState(() => _loading = true);

    try {
      await _authRepository.sendOTP(phone: widget.phoneNumber);
      
      if (!mounted) return;

      toastification.show(
        context: context,
        type: ToastificationType.success,
        style: ToastificationStyle.flatColored,
        title: Text('messages.otp_resent'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );

      _startResendTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);

      // Show error dialog
      showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _onChanged(String value, int index) {
    setState(() {
      _hasError = false;
      _errorMessage = '';
    });

    if (value.isNotEmpty && index < 3) {
      // Move to next field
      _focusNodes[index + 1].requestFocus();
    }

    // Auto-submit when all fields are filled
    if (index == 3 && value.isNotEmpty) {
      final allFilled = _controllers.every((c) => c.text.isNotEmpty);
      if (allFilled) {
        _verifyOTP();
      }
    }
  }

  void _onBackspace(int index) {
    if (index > 0 && _controllers[index].text.isEmpty) {
      _focusNodes[index - 1].requestFocus();
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
                _buildIcon(),
                const SizedBox(height: 30),
                _buildHeader(),
                const SizedBox(height: 40),
                _buildOTPFields(),
                if (_hasError) ...[
                  const SizedBox(height: 16),
                  _buildErrorMessage(),
                ],
                const SizedBox(height: 30),
                _buildResendButton(),
                const SizedBox(height: 20),
                if (_loading) const CircularProgressIndicator(color: AppColors.primaryGreen),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: AppColors.primaryGreen.withOpacity(0.1),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.sms_outlined,
        size: 50,
        color: AppColors.primaryGreen,
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        Text(
          'auth.verification_code'.tr(),
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 12),
        Text(
          'auth.enter_4_digit_code'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        const SizedBox(height: 8),
        Text(
          widget.phoneNumber,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryGreen,
              ),
        ),
      ],
    );
  }

  Widget _buildOTPFields() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(4, (index) {
        return SizedBox(
          width: 60,
          height: 60,
          child: TextField(
            controller: _controllers[index],
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _hasError ? Colors.red : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _hasError ? Colors.red : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: _hasError ? Colors.red : AppColors.primaryGreen,
                  width: 2,
                ),
              ),
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
            ],
            onChanged: (value) => _onChanged(value, index),
            onTap: () {
              // Clear field on tap
              _controllers[index].clear();
            },
          ),
        );
      }),
    );
  }

  Widget _buildErrorMessage() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResendButton() {
    return Column(
      children: [
        Text(
          'auth.code_not_received'.tr(),
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _canResend ? _resendOTP : null,
          child: Text(
            _canResend ? 'auth.resend'.tr() : '${'auth.resend'.tr()} ($_resendTimer s)',
            style: TextStyle(
              color: _canResend ? AppColors.primaryGreen : Colors.grey,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }
}

