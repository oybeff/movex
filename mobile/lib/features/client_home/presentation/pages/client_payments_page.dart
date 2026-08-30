import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/utils/number_formatter.dart';

class ClientPaymentsPage extends StatefulWidget {
  const ClientPaymentsPage({super.key});

  @override
  State<ClientPaymentsPage> createState() => _ClientPaymentsPageState();
}

class _ClientPaymentsPageState extends State<ClientPaymentsPage> {
  final BalanceService _balanceService = BalanceService();
  List<BalanceTransactionModel>? _transactions;
  bool _isLoading = true;
  String _selectedFilter = 'all'; // all, topup, payment, income, refund

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    setState(() => _isLoading = true);
    try {
      final transactions = await _balanceService.getTransactionHistory();
      setState(() {
        _transactions = transactions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'payments.error'.tr()}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  List<BalanceTransactionModel> get _filteredTransactions {
    if (_transactions == null) return [];
    if (_selectedFilter == 'all') return _transactions!;
    return _transactions!.where((t) => t.type.toLowerCase() == _selectedFilter).toList();
  }

  double get _totalIncome {
    if (_transactions == null) return 0;
    return _transactions!.fold(0, (sum, transaction) {
      if (transaction.type.toLowerCase() == 'income' && transaction.status.toLowerCase() == 'completed') {
        return sum + transaction.amount;
      }
      return sum;
    });
  }

  double get _totalPayments {
    if (_transactions == null) return 0;
    return _transactions!.fold(0, (sum, transaction) {
      if (transaction.type.toLowerCase() == 'payment' && transaction.status.toLowerCase() == 'completed') {
        return sum + transaction.amount;
      }
      return sum;
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'completed':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'failed':
      case 'canceled':
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
      case 'canceled':
        return 'payments.canceled'.tr();
      default:
        return status;
    }
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return Colors.blue;
      case 'payment':
        return Colors.red;
      case 'income':
        return Colors.green;
      case 'refund':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _getTypeText(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return 'transactions.topup'.tr();
      case 'payment':
        return 'transactions.payment'.tr();
      case 'income':
        return 'transactions.income'.tr();
      case 'refund':
        return 'transactions.refund'.tr();
      default:
        return type;
    }
  }

  IconData _getTypeIcon(String type) {
    switch (type.toLowerCase()) {
      case 'topup':
        return Icons.add_circle_outline;
      case 'payment':
        return Icons.remove_circle_outline;
      case 'income':
        return Icons.trending_up;
      case 'refund':
        return Icons.refresh;
      default:
        return Icons.swap_horiz;
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
            'payments.title'.tr(),
            style: const TextStyle(
              color: AppColors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : RefreshIndicator(
                color: AppColors.primaryGreen,
                onRefresh: _loadTransactions,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Balance Cards
                      Row(
                        children: [
                          Expanded(
                            child: _BalanceCard(
                              title: 'transactions.total_income'.tr(),
                              amount: _totalIncome,
                              icon: Icons.trending_up,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _BalanceCard(
                              title: 'transactions.total_payments'.tr(),
                              amount: _totalPayments,
                              icon: Icons.trending_down,
                              color: Colors.red,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _FilterChip(
                              label: 'common.all'.tr(),
                              isSelected: _selectedFilter == 'all',
                              onTap: () => setState(() => _selectedFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'transactions.topup'.tr(),
                              isSelected: _selectedFilter == 'topup',
                              onTap: () => setState(() => _selectedFilter = 'topup'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'transactions.payment'.tr(),
                              isSelected: _selectedFilter == 'payment',
                              onTap: () => setState(() => _selectedFilter = 'payment'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'transactions.income'.tr(),
                              isSelected: _selectedFilter == 'income',
                              onTap: () => setState(() => _selectedFilter = 'income'),
                            ),
                            const SizedBox(width: 8),
                            _FilterChip(
                              label: 'transactions.refund'.tr(),
                              isSelected: _selectedFilter == 'refund',
                              onTap: () => setState(() => _selectedFilter = 'refund'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Transactions List
                      if (_filteredTransactions.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.all(48),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.receipt_long_rounded,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'transactions.no_transactions'.tr(),
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _filteredTransactions.length,
                          itemBuilder: (context, index) {
                            final transaction = _filteredTransactions[index];
                            return _TransactionCard(
                              transaction: transaction,
                              typeColor: _getTypeColor(transaction.type),
                              typeText: _getTypeText(transaction.type),
                              typeIcon: _getTypeIcon(transaction.type),
                              statusColor: _getStatusColor(transaction.status),
                              statusText: _getStatusText(transaction.status),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  final String title;
  final double amount;
  final IconData icon;
  final Color color;

  const _BalanceCard({
    required this.title,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${NumberFormatter.formatCurrency(amount)} ${'common.currency'.tr()}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.black,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primaryGreen : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.primaryGreen : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppColors.black,
          ),
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  final BalanceTransactionModel transaction;
  final Color typeColor;
  final String typeText;
  final IconData typeIcon;
  final Color statusColor;
  final String statusText;

  const _TransactionCard({
    required this.transaction,
    required this.typeColor,
    required this.typeText,
    required this.typeIcon,
    required this.statusColor,
    required this.statusText,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('dd.MM.yyyy HH:mm');
    final isIncome = transaction.type.toLowerCase() == 'income' || transaction.type.toLowerCase() == 'topup' || transaction.type.toLowerCase() == 'refund';

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
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: typeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        typeIcon,
                        color: typeColor,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          typeText,
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
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: Colors.black12),
            const SizedBox(height: 16),

            // Amount
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'transactions.amount'.tr(),
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey.shade600,
                  ),
                ),
                Text(
                  '${isIncome ? '+' : '-'} ${NumberFormatter.formatCurrency(transaction.amount)} ${'common.currency'.tr()}',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isIncome ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),

            // Description
            if (transaction.description != null && transaction.description!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                transaction.description!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade700,
                ),
              ),
            ],

            // Payment Method
            if (transaction.paymentMethod != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Icons.credit_card_rounded,
                    size: 16,
                    color: Colors.grey.shade600,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    transaction.paymentMethod!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
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
