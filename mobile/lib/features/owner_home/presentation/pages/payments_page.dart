import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/models/payment_model.dart';
import '../../../../core/utils/number_formatter.dart';
import 'payout_page.dart';

class PaymentsPage extends StatefulWidget {
  const PaymentsPage({super.key});

  @override
  State<PaymentsPage> createState() => _PaymentsPageState();
}

class _PaymentsPageState extends State<PaymentsPage> {
  final PaymentService _paymentService = PaymentService();
  List<PaymentModel> _payments = [];
  bool _isLoading = true;

  double _todayTotal = 0.0;
  double _monthTotal = 0.0;
  double _yearTotal = 0.0;
  double _balance = 0.0;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    try {
      setState(() => _isLoading = true);

      final payments = await _paymentService.getPayments();

      // Statistikani hisoblash
      final now = DateTime.now();
      double todayTotal = 0.0;
      double monthTotal = 0.0;
      double yearTotal = 0.0;
      double balance = 0.0;

      for (var payment in payments) {
        if (payment.status == 'paid' && payment.paidAt != null) {
          final paidDate = payment.paidAt!;
          final amount = payment.amount - payment.commission;

          if (paidDate.year == now.year &&
              paidDate.month == now.month &&
              paidDate.day == now.day) {
            todayTotal += amount;
          }

          if (paidDate.year == now.year && paidDate.month == now.month) {
            monthTotal += amount;
          }

          if (paidDate.year == now.year) {
            yearTotal += amount;
          }

          balance += amount;
        }
      }

      setState(() {
        _payments = payments;
        _todayTotal = todayTotal;
        _monthTotal = monthTotal;
        _yearTotal = yearTotal;
        _balance = balance;
        _isLoading = false;
      });
    } catch (e) {
      print('Load payments error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('errors.network'.tr()),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('payments.title'.tr()),
        actions: [
          // Pul yechish: ilgari egasi pulini olib chiqa olmasdi
          IconButton(
            tooltip: 'payout.title'.tr(),
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PayoutPage()),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    // Statistika
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      margin: const EdgeInsets.only(bottom: 16),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            _buildStatRow('payments.today'.tr(), _todayTotal),
                            const SizedBox(height: 8),
                            _buildStatRow('payments.this_month'.tr(), _monthTotal),
                            const SizedBox(height: 8),
                            _buildStatRow('payments.this_year'.tr(), _yearTotal),
                            const Divider(height: 24),
                            _buildStatRow('payments.current_balance'.tr(), _balance, isBold: true),
                          ],
                        ),
                      ),
                    ),

                    // To'lovlar ro'yxati
                    Expanded(
                      child: _payments.isEmpty
                          ? Center(child: Text('payments.no_payments'.tr()))
                          : ListView.builder(
                              itemCount: _payments.length,
                              itemBuilder: (context, index) {
                                final payment = _payments[index];
                                final String status = payment.status;
                                Color statusColor;
                                String statusText;

                                switch (status) {
                                  case 'paid':
                                    statusColor = Colors.green;
                                    statusText = 'payments.paid'.tr();
                                    break;
                                  case 'pending':
                                    statusColor = Colors.orange;
                                    statusText = 'payments.pending'.tr();
                                    break;
                                  case 'canceled':
                                    statusColor = Colors.red;
                                    statusText = 'payments.canceled'.tr();
                                    break;
                                  default:
                                    statusColor = Colors.grey;
                                    statusText = status;
                                }

                                final dateFormat = DateFormat('dd.MM.yyyy');
                                final dateStr = payment.paidAt != null
                                    ? dateFormat.format(payment.paidAt!)
                                    : '-';

                                return Card(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  margin: const EdgeInsets.only(bottom: 12),
                                  child: Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // Asosiy ma'lumot
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${'payments.order'.tr()} #${payment.orderId}',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                              ),
                                              const SizedBox(height: 4),
                                              Text('${'payments.date'.tr()}: $dateStr'),
                                              Text('${'payments.amount'.tr()}: ${payment.amount.toStringAsFixed(0)} ${'common.currency'.tr()}'),
                                              Text('${'payments.commission'.tr()}: ${payment.commission.toStringAsFixed(0)} ${'common.currency'.tr()}'),
                                            ],
                                          ),
                                        ),

                                        const SizedBox(width: 8),

                                        // Status
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor,
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: const TextStyle(color: Colors.white, fontSize: 12),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatRow(String label, double value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
        Text('${NumberFormatter.formatCurrency(value)} ${'common.currency'.tr()}', style: TextStyle(fontSize: 16, fontWeight: isBold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}
