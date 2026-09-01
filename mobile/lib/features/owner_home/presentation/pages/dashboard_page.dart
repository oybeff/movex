import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import 'owner_home_page.dart' show OwnerTab;
import 'package:go_router/go_router.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import 'package:movex_go/core/widgets/notification_bell.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/services/equipment_service.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/payment_service.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/utils/number_formatter.dart';
import 'franchise_manage_page.dart';
import '../../../balance/presentation/pages/balance_topup_page.dart';

class DashboardPage extends StatefulWidget {
  final Function(int)? onNavigate;

  const DashboardPage({super.key, this.onNavigate});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final EquipmentService _equipmentService = EquipmentService();
  final OrderService _orderService = OrderService();
  final PaymentService _paymentService = PaymentService();
  final BalanceService _balanceService = BalanceService();

  bool _isLoading = true;
  int _activeEquipmentCount = 0;
  int _currentOrdersCount = 0;
  double _todayIncome = 0.0;
  double _currentBalance = 0.0;
  List<FlSpot> _chartData = [];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    try {
      setState(() => _isLoading = true);

      // Parallel ravishda barcha ma'lumotlarni yuklaymiz
      final results = await Future.wait([
        _equipmentService.getEquipmentList(ownerOnly: true), // Barcha texnikalar
        _orderService.getOrders(),
        _balanceService.getTransactionHistory(), // Balance transactions
        _balanceService.getBalance(),
      ]);

      final equipment = results[0] as List;
      final orders = results[1] as List;
      final transactions = results[2] as List;
      final balance = results[3] as dynamic;

      // Bugungi daromadni hisoblash (faqat 'income' type transactions)
      final today = DateTime.now();
      double todayIncome = 0.0;
      for (var transaction in transactions) {
        final createdDate = transaction.createdAt;
        if (createdDate.year == today.year &&
            createdDate.month == today.month &&
            createdDate.day == today.day &&
            transaction.type == 'income' &&
            transaction.status == 'completed') {
          todayIncome += transaction.amount;
        }
      }

      // Oxirgi 7 kunlik buyurtmalar statistikasi
      final chartData = <FlSpot>[];
      for (int i = 6; i >= 0; i--) {
        final date = today.subtract(Duration(days: i));
        final dayOrders = orders.where((order) {
          final orderDate = order.createdAt;
          return orderDate.year == date.year &&
              orderDate.month == date.month &&
              orderDate.day == date.day &&
              (order.status == 'confirmed' || order.status == 'completed');
        }).length;
        chartData.add(FlSpot((6 - i).toDouble(), dayOrders.toDouble()));
      }

      setState(() {
        // Faol texnika: bo'sh va band texnikalar (ta'mirdagilar emas)
        _activeEquipmentCount = equipment.where((e) =>
          e.status == 'available' || e.status == 'busy'
        ).length;
        // Joriy buyurtmalar: faqat tasdiqlanishi kutilayotganlar
        _currentOrdersCount = orders.where((o) => o.status == 'pending').length;
        _todayIncome = todayIncome;
        _currentBalance = balance.balance;
        _chartData = chartData;
        _isLoading = false;
      });
    } catch (e) {
      print('Load dashboard data error: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('errors.network'.tr()),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const Color primaryGreen = Color(0xFF4CAF50);
    const double cardRadius = 16;

    final stats = [
      // Balans kartochkasi bosiladigan bo'ldi: QA "bosilmaydi" deb yozgan,
      // va hisobni to'ldirishni odam avvalo shu yerda qidiradi.
      {'title': 'balance.current_balance'.tr(), 'value': '${NumberFormatter.formatCurrency(_currentBalance)} ${'common.currency'.tr()}', 'icon': Icons.account_balance_wallet, 'onTap': 'topup'},
      {'title': 'owner.active_equipment'.tr(), 'value': '$_activeEquipmentCount', 'icon': Icons.construction},
      {'title': 'owner.current_orders'.tr(), 'value': '$_currentOrdersCount', 'icon': Icons.assignment},
      // Yuqoridagi balans kabi — razryadlar bilan. Ilgari toStringAsFixed(0)
      // turardi va yonma-yon "1 902 400 сум" va "1902400 сум" chiqardi.
      {'title': 'owner.income_today'.tr(), 'value': '${NumberFormatter.formatCurrency(_todayIncome)} ${'common.currency'.tr()}', 'icon': Icons.attach_money},
    ];

    // Vaqtinchalik region (profildan olinadi)
    final currentRegion = 'owner.tashkent'.tr();

    final screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.white,

        elevation: 0,
        title: Row(
          children: [
            //logo
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: primaryGreen,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                child: Image.asset('assets/logo_only.png')),
            ),
            const SizedBox(width: 12),
            Text('app_name'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          const NotificationBell(),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
            tooltip: 'settings.title'.tr(),
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
            // Franshiza bloki (joriy region)
            // Container(
            //   padding: const EdgeInsets.all(16),
            //   decoration: BoxDecoration(
            //     color: Colors.white,
            //     borderRadius: BorderRadius.circular(cardRadius),
            //     boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))],
            //   ),
            //   child: Column(
            //     crossAxisAlignment: CrossAxisAlignment.start,
            //     mainAxisAlignment: MainAxisAlignment.spaceBetween,
            //     children: [
            //       Row(
            //         children: [
            //           const Icon(Icons.location_city, color: primaryGreen, size: 32),
            //           const SizedBox(width: 12),
            //           Expanded(
            //             child: Text(
            //               "${'owner.my_region'.tr()}: $currentRegion",
            //               style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            //             ),
            //           ),
            //         ],
            //       ),
            //       const SizedBox(height: 12),
            //       SizedBox(
            //         width: double.infinity,
            //         height: 44,
            //         child: ElevatedButton(
            //               onPressed: () {
            //                 Navigator.push(
            //                   context,
            //                   MaterialPageRoute(
            //                     builder: (context) => const FranchiseManagePage(),
            //                   ),
            //                 );
            //               },
            //               style: ElevatedButton.styleFrom(
            //                 backgroundColor: primaryGreen,
            //                 shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            //               ),
            //               child: Text('franchise.title'.tr(), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
            //             ),
            //       ),
            //     ],
            //   ),
            // ),
            // const SizedBox(height: 24),

            // Statistika
            ListView.builder(
              scrollDirection: Axis.vertical,
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: stats.length,
              itemBuilder: (context, index) {
                final stat = stats[index];
                final card = Container(
                  width: MediaQuery.of(context).size.width,
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(cardRadius),
                    boxShadow: const [
                      BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(1, 1)),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(stat['icon'] as IconData, color: Colors.black87, size: 28),
                      const SizedBox(width: 6),
                      Text(
                        stat['title'] as String,
                        style: const TextStyle(color: Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Text(
                        stat['value'] as String,
                        style: const TextStyle(color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      
                    ],
                  ),
                );

                if (stat['onTap'] != 'topup') return card;
                return InkWell(
                  borderRadius: BorderRadius.circular(cardRadius),
                  onTap: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BalanceTopUpPage(),
                      ),
                    );
                    // Qaytgach raqamlar yangilansin — pul qo'shilgan bo'lishi
                    // mumkin
                    if (mounted) _loadDashboardData();
                  },
                  child: card,
                );
              },
            ),
            const SizedBox(height: 8),

            // Tez harakatlar
            Text('owner.quick_actions'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            LayoutBuilder(builder: (context, constraints) {
              final double cardWidth = ((constraints.maxWidth - 16) / 2).clamp(100, 300);
              return Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _ActionCard(
                    title: 'owner.add_equipment'.tr(),
                    icon: Icons.add,
                    color: primaryGreen,
                    width: cardWidth,
                    onTap: () => context.push('/add-equipment'),
                  ),
                  _ActionCard(
                    title: 'owner.orders'.tr(),
                    icon: Icons.assignment,
                    color: Colors.orange,
                    width: cardWidth,
                    onTap: () {
                      widget.onNavigate?.call(OwnerTab.orders);
                    },
                  ),
                  _ActionCard(
                    title: 'owner.chat'.tr(),
                    icon: Icons.chat,
                    color: Colors.blue,
                    width: cardWidth,
                    onTap: () {
                      widget.onNavigate?.call(OwnerTab.chat);
                    },
                  ),
                ],
              );
            }),
            const SizedBox(height: 24),

            // Grafik
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('owner.orders_chart'.tr(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                TextButton.icon(
                  onPressed: () => context.push('/order-statistics'),
                  icon: const Icon(Icons.bar_chart, size: 18),
                  label: Text('messages.details'.tr()),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.primaryGreen,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              height: 250,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(cardRadius),
                boxShadow: const [
                  BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(1, 1)),
                ],
              ),
              child: _chartData.isEmpty
                  ? Center(
                      child: Text(
                        'messages.no_data'.tr(),
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : LineChart(
                      LineChartData(
                        gridData: FlGridData(
                          show: true,
                          drawVerticalLine: false,
                          horizontalInterval: 1,
                          getDrawingHorizontalLine: (value) {
                            return FlLine(
                              color: Colors.grey[300]!,
                              strokeWidth: 1,
                            );
                          },
                        ),
                        titlesData: FlTitlesData(
                          show: true,
                          rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 45,
                              interval: 1,
                              getTitlesWidget: (value, meta) {
                                final date = DateTime.now().subtract(
                                  Duration(days: 6 - value.toInt()),
                                );
                                final dayNames = 'common.weekdays_short'.tr().split(',');
                                return Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        dayNames[date.weekday - 1],
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${date.day}.${date.month}',
                                        style: TextStyle(
                                          color: Colors.grey[500],
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: 1,
                              reservedSize: 35,
                              getTitlesWidget: (value, meta) {
                                return Text(
                                  value.toInt().toString(),
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        borderData: FlBorderData(
                          show: true,
                          border: Border(
                            bottom: BorderSide(color: Colors.grey[300]!),
                            left: BorderSide(color: Colors.grey[300]!),
                          ),
                        ),
                        minX: 0,
                        maxX: 6,
                        minY: 0,
                        maxY: _chartData.map((e) => e.y).reduce((a, b) => a > b ? a : b) + 2,
                        lineBarsData: [
                          LineChartBarData(
                            spots: _chartData,
                            isCurved: true,
                            color: AppColors.primaryGreen,
                            barWidth: 3,
                            isStrokeCapRound: true,
                            dotData: FlDotData(
                              show: true,
                              getDotPainter: (spot, percent, barData, index) {
                                return FlDotCirclePainter(
                                  radius: 4,
                                  color: Colors.white,
                                  strokeWidth: 2,
                                  strokeColor: AppColors.primaryGreen,
                                );
                              },
                            ),
                            belowBarData: BarAreaData(
                              show: true,
                              color: AppColors.primaryGreen.withValues(alpha: 0.1),
                            ),
                          ),
                        ],
                        lineTouchData: LineTouchData(
                          touchTooltipData: LineTouchTooltipData(
                            getTooltipColor: (touchedSpot) => AppColors.primaryGreen,
                            getTooltipItems: (touchedSpots) {
                              return touchedSpots.map((spot) {
                                final date = DateTime.now().subtract(
                                  Duration(days: 6 - spot.x.toInt()),
                                );
                                return LineTooltipItem(
                                  '${spot.y.toInt()} ta\n${date.day}.${date.month}',
                                  const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              }).toList();
                            },
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final double width;

  const _ActionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 2))],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
