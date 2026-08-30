import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/number_formatter.dart';

class ClientBalancePage extends StatefulWidget {
  const ClientBalancePage({super.key});

  @override
  State<ClientBalancePage> createState() => _ClientBalancePageState();
}

class _ClientBalancePageState extends State<ClientBalancePage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  final BalanceService _balanceService = BalanceService();
  final UserService _userService = UserService();

  BalanceModel? _balance;
  UserModel? _currentUser;
  List<BalanceTransactionModel>? _transactions;
  bool _isLoadingBalance = true;
  bool _isLoadingTransactions = true;
  bool _isProcessing = false;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  String _selectedPaymentMethod = 'click';
  int? _pendingTransactionId;

  final List<int> _quickAmounts = [10000, 50000, 100000, 500000, 1000000];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _loadBalance();
    _loadTransactions();
    _loadUserData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabController.dispose();
    _amountController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingTransactionId != null) {
      _checkTransactionStatus();
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
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('${'common.error'.tr()}: $e'),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoadingTransactions = true);
    try {
      final transactions = await _balanceService.getTransactionHistory();
      setState(() {
        _transactions = transactions;
        _isLoadingTransactions = false;
      });
    } catch (e) {
      setState(() => _isLoadingTransactions = false);
    }
  }

  Future<void> _loadUserData() async {
    try {
      final user = await _userService.getCurrentUser();
      setState(() {
        _currentUser = user;
        if (user.phone != null && user.phone!.isNotEmpty) {
          _phoneController.text = user.phone!;
        }
      });
    } catch (e) {
      debugPrint('Load user data error: $e');
    }
  }

  Future<void> _checkTransactionStatus() async {
    if (_pendingTransactionId == null) return;

    try {
      final transaction = await _balanceService.getTransaction(_pendingTransactionId!);

      if (transaction.status.toLowerCase() == 'completed') {
        setState(() => _pendingTransactionId = null);
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.flatColored,
            title: Text('messages.payment_success'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
          _loadBalance();
          _loadTransactions();
        }
      } else if (transaction.status.toLowerCase() == 'failed') {
        setState(() => _pendingTransactionId = null);
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flatColored,
            title: Text('messages.payment_failed'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
      }
    } catch (e) {
      debugPrint('Check transaction status error: $e');
    }
  }

  Future<void> _topUpBalance() async {
    final amountText = _amountController.text.trim();
    if (amountText.isEmpty) {
      toastification.show(
        context: context,
        type: ToastificationType.warning,
        style: ToastificationStyle.flatColored,
        title: Text('balance.enter_amount'.tr()),
        autoCloseDuration: const Duration(seconds: 3),
        alignment: Alignment.topCenter,
      );
      return;
    }

    final amount = double.tryParse(amountText);
    if (amount == null || amount < 10000 || amount > 10000000) {
      toastification.show(
        context: context,
        type: ToastificationType.error,
        style: ToastificationStyle.flatColored,
        title: Text('balance.invalid_amount'.tr()),
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

    setState(() => _isProcessing = true);

    try {
      final result = await _balanceService.topUpBalance(
        amount: amount,
        paymentMethod: _selectedPaymentMethod,
        phoneNumber: phoneNumber,
      );

      setState(() => _isProcessing = false);

      if (_selectedPaymentMethod == 'click' && result.paymentUrl != null) {
        setState(() => _pendingTransactionId = result.transactionId);

        final uri = Uri.parse(result.paymentUrl!);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          if (mounted) {
            toastification.show(
              context: context,
              type: ToastificationType.info,
              style: ToastificationStyle.flatColored,
              title: Text('messages.complete_payment_in_click'.tr()),
              autoCloseDuration: const Duration(seconds: 3),
              alignment: Alignment.topCenter,
            );
          }
        } else {
          throw Exception('errors.cannot_open_click'.tr());
        }
      } else {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.success,
            style: ToastificationStyle.flatColored,
            title: Text('balance.topup_success'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
          _amountController.clear();
          _loadBalance();
          _loadTransactions();
        }
      }
    } catch (e) {
      setState(() => _isProcessing = false);
      if (mounted) {
        showErrorDialog(context, e);
      }
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
          backgroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'balance.title'.tr(),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          bottom: TabBar(
            controller: _tabController,
            labelColor: AppColors.primaryGreen,
            unselectedLabelColor: Colors.grey,
            indicatorColor: AppColors.primaryGreen,
            indicatorWeight: 3,
            tabs: [
              Tab(text: 'balance.topup'.tr()),
              Tab(text: 'balance.topup_history'.tr()),
            ],
          ),
        ),
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildTopUpTab(),
            _buildHistoryTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopUpTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Balance Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.primaryGreen, Color(0xFF45A049)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
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
                  'balance.current_balance'.tr(),
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                _isLoadingBalance
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text(
                        '${NumberFormatter.formatCurrency(_balance?.balance ?? 0)} so\'m',
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white30, height: 1),
                const SizedBox(height: 16),

                // Mavjud va muzlatilgan balans
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'balance.available'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _isLoadingBalance
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  '${NumberFormatter.formatCurrency(_balance?.availableBalance ?? 0)} so\'m',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'balance.frozen'.tr(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _isLoadingBalance
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  '${NumberFormatter.formatCurrency(_balance?.frozenBalance ?? 0)} so\'m',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Amount Input
          Text(
            'balance.enter_amount'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              hintText: 'balance.amount_placeholder'.tr(),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
              ),
              suffixText: 'so\'m',
              suffixStyle: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'balance.min_amount'.tr(),
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 16),

          // Tezkor summalar
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _quickAmounts.map((amount) {
              return InkWell(
                onTap: () {
                  setState(() {
                    _amountController.text = amount.toString();
                  });
                },
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primaryGreen.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    '${NumberFormatter.formatCurrency(amount)} so\'m',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primaryGreen,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),

          // Telefon raqam (faqat o'qish uchun)
          Text(
            'auth.phone'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            readOnly: true,
            decoration: InputDecoration(
              hintText: '+998 90 123 45 67',
              prefixIcon: const Icon(Icons.phone, color: AppColors.primaryGreen),
              filled: true,
              fillColor: Colors.grey[100],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tizimda ro\'yxatdan o\'tgan telefon raqamingiz avtomatik ishlatiladi',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 24),

          // Payment Method Selection
          Text(
            'balance.select_payment_method'.tr(),
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.black,
            ),
          ),
          const SizedBox(height: 12),
          _PaymentMethodCard(
            title: 'balance.click'.tr(),
            icon: Icons.credit_card_rounded,
            isSelected: _selectedPaymentMethod == 'click',
            onTap: () => setState(() => _selectedPaymentMethod = 'click'),
          ),
          const SizedBox(height: 32),

          // Top Up Button
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: _isProcessing ? null : _topUpBalance,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isProcessing
                  ? const SizedBox(
                      height: 24,
                      width: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : Text(
                      'balance.topup_button'.tr(),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryTab() {
    if (_isLoadingTransactions) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primaryGreen),
      );
    }

    if (_transactions == null || _transactions!.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 16),
            Text(
              'balance.no_transactions'.tr(),
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primaryGreen,
      onRefresh: _loadTransactions,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions!.length,
        itemBuilder: (context, index) {
          final transaction = _transactions![index];
          return _TransactionCard(transaction: transaction);
        },
      ),
    );
  }
}

class _PaymentMethodCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _PaymentMethodCard({
    required this.title,
    required this.icon,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryGreen.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppColors.primaryGreen.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppColors.primaryGreen : Colors.grey.shade600,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? AppColors.primaryGreen : AppColors.black,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.primaryGreen,
                size: 24,
              ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final BalanceTransactionModel transaction;

  const _TransactionCard({required this.transaction});

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getStatusText(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return 'payments.completed'.tr();
      case 'pending':
        return 'payments.pending'.tr();
      case 'failed':
        return 'payments.failed'.tr();
      default:
        return status;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return Icons.add_circle_rounded;
      case 'payment':
        return Icons.remove_circle_rounded;
      default:
        return Icons.swap_horiz_rounded;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return Colors.green;
      case 'payment':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  String _getTypeText(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return 'balance.transaction_type_topup'.tr();
      case 'payment':
        return 'balance.transaction_type_payment'.tr();
      default:
        return type;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: _getTypeColor(transaction.type).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _getTypeIcon(transaction.type),
                    color: _getTypeColor(transaction.type),
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _getTypeText(transaction.type),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.black,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        dateFormatter.format(transaction.createdAt),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${transaction.type.toLowerCase() == 'topup' ? '+' : '-'}${NumberFormatter.formatCurrency(transaction.amount)} so\'m',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _getTypeColor(transaction.type),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: _getStatusColor(transaction.status).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _getStatusText(transaction.status),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _getStatusColor(transaction.status),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            if (transaction.description != null) ...[
              const SizedBox(height: 12),
              const Divider(height: 1, color: Colors.black12),
              const SizedBox(height: 12),
              Text(
                transaction.description!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            if (transaction.paymentMethod != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    size: 14,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    transaction.paymentMethod!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
