import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/number_formatter.dart';

class BalanceTopUpPage extends StatefulWidget {
  final double? requiredAmount; // Kerakli summa (agar buyurtmadan kelgan bo'lsa)

  const BalanceTopUpPage({super.key, this.requiredAmount});

  @override
  State<BalanceTopUpPage> createState() => _BalanceTopUpPageState();
}

class _BalanceTopUpPageState extends State<BalanceTopUpPage> with WidgetsBindingObserver {
  final BalanceService _balanceService = BalanceService();
  final UserService _userService = UserService();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  BalanceModel? _balance;
  UserModel? _currentUser;
  bool _isLoading = false;
  bool _isLoadingBalance = true;
  String _selectedPaymentMethod = 'click'; // Default: click
  int? _pendingTransactionId; // Click to'lov uchun pending transaction ID

  final List<Map<String, dynamic>> _paymentMethods = [
    {'id': 'click', 'name': 'Click', 'icon': Icons.payment},
  ];

  final List<int> _quickAmounts = [10000, 50000, 100000, 500000, 1000000];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadBalance();
    _loadUserData();

    // Agar buyurtmadan kerakli summa berilgan bo'lsa, uni avtomatik to'ldirish
    if (widget.requiredAmount != null) {
      _amountController.text = widget.requiredAmount!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Ilova foreground'ga qaytganda balansni yangilash
    if (state == AppLifecycleState.resumed && _pendingTransactionId != null) {
      _checkPaymentStatus();
    }
  }

  Future<void> _loadBalance() async {
    setState(() => _isLoadingBalance = true);
    try {
      final balance = await _balanceService.getBalance();
      setState(() {
        _balance = balance;
        _isLoadingBalance = false;
      });
    } catch (e) {
      setState(() => _isLoadingBalance = false);
      if (mounted) {
        showErrorDialog(context, e);
      }
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _userService.getCurrentUser();
      setState(() {
        _currentUser = user;
        // Agar user telefon raqami mavjud bo'lsa, avtomatik to'ldirish
        if (user.phone != null && user.phone!.isNotEmpty) {
          _phoneController.text = user.phone!;
        }
      });
    } catch (e) {
      debugPrint('Load user data error: $e');
    }
  }

  Future<void> _topUpBalance() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('messages.enter_amount'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('messages.invalid_amount'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    // Click to'lov uchun telefon raqam majburiy
    String? phoneNumber;
    if (_selectedPaymentMethod == 'click') {
      phoneNumber = _phoneController.text.trim();
      if (phoneNumber.isEmpty) {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          style: ToastificationStyle.flatColored,
          title: Text('messages.phone_not_found'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        return;
      }

      // Telefon raqam validatsiyasi (oddiy)
      final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
      if (cleanPhone.length < 9) {
        toastification.show(
          context: context,
          type: ToastificationType.warning,
          style: ToastificationStyle.flatColored,
          title: Text('messages.invalid_phone'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final response = await _balanceService.topUpBalance(
        amount: amount,
        paymentMethod: _selectedPaymentMethod,
        phoneNumber: phoneNumber,
      );

      setState(() => _isLoading = false);

      // Agar Click to'lov bo'lsa, URL launcher orqali ochish
      if (_selectedPaymentMethod == 'click' && response.paymentUrl != null) {
        _pendingTransactionId = response.transactionId;

        // Click to'lov URL'ini ochish
        final url = Uri.parse(response.paymentUrl!);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);

          if (mounted) {
            toastification.show(
              context: context,
              type: ToastificationType.info,
              style: ToastificationStyle.flatColored,
              title: Text('messages.click_payment_opened'.tr()),
              autoCloseDuration: const Duration(seconds: 3),
              alignment: Alignment.topCenter,
            );
          }
        } else {
          if (mounted) {
            toastification.show(
              context: context,
              type: ToastificationType.error,
              style: ToastificationStyle.flatColored,
              title: Text('messages.cannot_open_payment_page'.tr()),
              autoCloseDuration: const Duration(seconds: 3),
              alignment: Alignment.topCenter,
            );
          }
        }
      } else {
        // Boshqa to'lov usullari uchun - to'g'ridan-to'g'ri completed
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.flatColored,
            title: Text('messages.balance_topup_success'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );

          // Balansni yangilash
          await _loadBalance();

          // Orqaga qaytish
          if (mounted) {
            context.pop();
          }
        }
      }
    } on DioException catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        showErrorDialog(context, e);
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.error'.tr()),
          description: Text(e.toString()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  /// Click to'lov statusini tekshirish
  Future<void> _checkPaymentStatus() async {
    if (_pendingTransactionId == null) return;

    try {
      final status = await _balanceService.checkTransactionStatus(_pendingTransactionId!);

      if (status == 'completed') {
        // To'lov muvaffaqiyatli
        _pendingTransactionId = null;
        await _loadBalance();

        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.flatColored,
            title: Text('messages.payment_success'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );

          // Orqaga qaytish
          context.pop();
        }
      } else if (status == 'failed') {
        // To'lov muvaffaqiyatsiz
        _pendingTransactionId = null;

        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flatColored,
            title: Text('messages.payment_failed_status'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
      }
      // Agar 'pending' bo'lsa, hech narsa qilmaymiz
    } catch (e) {
      // Xatolik bo'lsa, log qilamiz
      debugPrint('Payment status check error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
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
          title: Text(
            'balance.topup'.tr(),
            style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
        body: _isLoadingBalance
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildBalanceCard(),
                    const SizedBox(height: 24),
                    _buildAmountInput(),
                    const SizedBox(height: 16),
                    _buildQuickAmounts(),
                    const SizedBox(height: 24),
                    _buildPaymentMethods(),
                    // Click to'lov uchun telefon raqam
                    if (_selectedPaymentMethod == 'click') ...[
                      const SizedBox(height: 24),
                      _buildPhoneInput(),
                    ],
                    const SizedBox(height: 32),
                    _buildTopUpButton(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildBalanceCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, AppColors.secondaryGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'balance.current'.tr(),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${NumberFormatter.formatCurrency(_balance?.balance ?? 0)} ${'common.currency'.tr()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'balance.available'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '${NumberFormatter.formatCurrency(_balance?.availableBalance ?? 0)} ${'common.currency'.tr()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'balance.frozen'.tr(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  Text(
                    '${NumberFormatter.formatCurrency(_balance?.frozenBalance ?? 0)} ${'common.currency'.tr()}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'balance.amount'.tr(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _amountController,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            hintText: 'balance.enter_amount'.tr(),
            suffixText: 'common.currency'.tr(),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPhoneInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'auth.phone'.tr(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          readOnly: true, // Faqat o'qish uchun
          decoration: InputDecoration(
            hintText: '+998 90 123 45 67',
            prefixIcon: const Icon(Icons.phone, color: AppColors.primaryGreen),
            filled: true,
            fillColor: Colors.grey[100],
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'balance.phone_auto_used'.tr(),
          style: const TextStyle(
            fontSize: 12,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickAmounts() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _quickAmounts.map((amount) {
        return InkWell(
          onTap: () {
            _amountController.text = amount.toString();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Text(
              NumberFormatter.formatCurrencyCompact(amount),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPaymentMethods() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'balance.payment_method'.tr(),
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        ..._paymentMethods.map((method) {
          final isSelected = _selectedPaymentMethod == method['id'];
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedPaymentMethod = method['id'];
                });
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected ? AppColors.primaryGreen : Colors.grey[300]!,
                    width: isSelected ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      method['icon'],
                      color: isSelected ? AppColors.primaryGreen : Colors.grey,
                    ),
                    const SizedBox(width: 12),
                    Text(
                      method['name'],
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppColors.primaryGreen : Colors.black,
                      ),
                    ),
                    const Spacer(),
                    if (isSelected)
                      const Icon(
                        Icons.check_circle,
                        color: AppColors.primaryGreen,
                      ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ],
    );
  }

  Widget _buildTopUpButton() {
    return SizedBox(
      width: double.infinity,
      height: 55,
      child: ElevatedButton(
        onPressed: _isLoading ? null : _topUpBalance,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryGreen,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 0,
        ),
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                'balance.topup_button'.tr(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }
}

