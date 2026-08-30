import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:movex_go/core/constants/app_colors.dart';
import '../../../../core/services/franchise_service.dart';
import '../../../../core/models/franchise_model.dart';
import '../../../../core/constants/equipment_types.dart';
import '../../../../core/utils/number_formatter.dart';

/// Franchayzing ekrani.
///
/// DIQQAT: bu ekran ISHLAMAYDI va shu holatda qoldirilgan ataylab.
///
/// Backend'da franchayzing umuman yo'q: /franchises/ endpoint'i, modeli va
/// jadvali mavjud emas. Quyidagi kod raqamlarni boshqa endpointlardan
/// yig'ib, franchayzing statistikasi sifatida ko'rsatardi — ya'ni
/// foydalanuvchi o'ylab topilgan raqamlarni ko'rardi.
///
/// Shuning uchun ekran ochilganda ochiq ogohlantirish chiqadi. Qolgan kod
/// o'chirilmadi: backend paydo bo'lganda [_backendReady] ni true qilish
/// kifoya. Kodni butunlay o'chirish yoki backend yozish — mahsulot bo'yicha
/// qaror, uni loyiha egasi qabul qiladi.
class FranchiseManagePage extends StatefulWidget {
  const FranchiseManagePage({super.key});

  @override
  State<FranchiseManagePage> createState() => _FranchiseManagePageState();
}

class _FranchiseManagePageState extends State<FranchiseManagePage> {
  /// Backend'da franchayzing paydo bo'lgach — true.
  static const bool _backendReady = false;

  final FranchiseService _franchiseService = FranchiseService();
  FranchiseModel? _franchise;
  bool _isLoading = true;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    if (_backendReady) {
      _loadFranchise();
    } else {
      _isLoading = false;
    }
  }

  /// Backend yo'qligini ochiq aytadigan ekran. O'ylab topilgan raqamlarni
  /// ko'rsatishdan ko'ra shu to'g'riroq.
  Widget _notAvailable() {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text('franchise.title'.tr()),
        centerTitle: true,
        backgroundColor: AppColors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.black),
        titleTextStyle: const TextStyle(
            color: AppColors.black, fontSize: 18, fontWeight: FontWeight.bold),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.construction_outlined,
                  size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                'franchise.not_available'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 17, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                'franchise.not_available_hint'.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadFranchise() async {
    try {
      setState(() => _isLoading = true);
      final franchise = await _franchiseService.getMyFranchise();
      setState(() {
        _franchise = franchise;
        _isLoading = false;
      });
    } catch (e) {
      print('Load franchise error: $e');
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

  List<Widget> get _pages => [
    FranchiseEquipmentPage(franchise: _franchise),
    FranchiseOrdersPage(franchise: _franchise),
    FranchiseIncomePage(franchise: _franchise),
    FranchiseStatsPage(franchise: _franchise),
  ];

  List<String> get _titles => [
    'franchise.equipment'.tr(),
    'franchise.orders'.tr(),
    'franchise.income'.tr(),
    'franchise.stats'.tr(),
  ];

  @override
  Widget build(BuildContext context) {
    if (!_backendReady) return _notAvailable();

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text('franchise.title'.tr()),
          centerTitle: true,
          backgroundColor: Colors.blueAccent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,)),
      );
    }

    if (_franchise == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text('franchise.title'.tr()),
          centerTitle: true,
          backgroundColor: Colors.blueAccent,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store_mall_directory, size: 80, color: Colors.grey),
              const SizedBox(height: 20),
              Text(
                'franchise.no_franchise'.tr(),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                'franchise.contact_admin'.tr(),
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        centerTitle: true,
        backgroundColor: Colors.blueAccent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFranchise,
          ),
        ],
      ),
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.agriculture),
            label: 'franchise.equipment'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.assignment),
            label: 'franchise.orders'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.attach_money),
            label: 'franchise.income'.tr(),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.analytics),
            label: 'franchise.stats'.tr(),
          ),
        ],
      ),
    );
  }
}

/// ---------------------
/// Franchise Equipment Page
/// ---------------------
class FranchiseEquipmentPage extends StatefulWidget {
  final FranchiseModel? franchise;

  const FranchiseEquipmentPage({super.key, this.franchise});

  @override
  State<FranchiseEquipmentPage> createState() => _FranchiseEquipmentPageState();
}

class _FranchiseEquipmentPageState extends State<FranchiseEquipmentPage> {
  final FranchiseService _franchiseService = FranchiseService();
  List<dynamic> _equipment = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEquipment();
  }

  Future<void> _loadEquipment() async {
    if (widget.franchise == null) return;

    try {
      setState(() => _isLoading = true);
      final equipment = await _franchiseService.getFranchiseEquipment(widget.franchise!.id);
      setState(() {
        _equipment = equipment;
        _isLoading = false;
      });
    } catch (e) {
      print('Load franchise equipment error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,));
    }

    if (_equipment.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.agriculture, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              'franchise.no_equipment'.tr(),
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadEquipment,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _equipment.length,
        itemBuilder: (context, index) {
          final equipment = _equipment[index];
          final status = equipment.status ?? 'available';

          Color statusColor = Colors.green;
          String statusText = 'equipment.status_available'.tr();

          if (status == 'rented') {
            statusColor = Colors.orange;
            statusText = 'equipment.status_busy'.tr();
          } else if (status == 'maintenance') {
            statusColor = Colors.red;
            statusText = 'equipment.status_repair'.tr();
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(Icons.agriculture, color: statusColor, size: 32),
              title: Text(
                '${EquipmentTypes.label(equipment.type)} ${equipment.model}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('${'messages.status_with_colon'.tr()} $statusText'),
                  Text('${'messages.price'.tr()}: ${NumberFormatter.formatCurrency(equipment.pricePerDay)} ${'common.currency'.tr()}/${'common.day'.tr()}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () {
                  // Texnika tafsilotlariga o'tish
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ---------------------
/// Franchise Orders Page
/// ---------------------
class FranchiseOrdersPage extends StatefulWidget {
  final FranchiseModel? franchise;

  const FranchiseOrdersPage({super.key, this.franchise});

  @override
  State<FranchiseOrdersPage> createState() => _FranchiseOrdersPageState();
}

class _FranchiseOrdersPageState extends State<FranchiseOrdersPage> {
  final FranchiseService _franchiseService = FranchiseService();
  List<dynamic> _orders = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    if (widget.franchise == null) return;

    try {
      setState(() => _isLoading = true);
      final orders = await _franchiseService.getFranchiseOrders(widget.franchise!.id);

      // Buyurtmalarni yangilaridan eskisiga qarab tartiblash (created_at bo'yicha)
      orders.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      print('Load franchise orders error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,));
    }

    if (_orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.assignment, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              'franchise.no_orders'.tr(),
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _orders.length,
        itemBuilder: (context, index) {
          final order = _orders[index];
          final status = order.status;

          Color statusColor = Colors.blue;
          String statusText = 'orders.status_pending'.tr();

          if (status == 'active') {
            statusColor = Colors.green;
            statusText = 'orders.status_active'.tr();
          } else if (status == 'completed') {
            statusColor = Colors.grey;
            statusText = 'Yakunlangan';
          } else if (status == 'cancelled') {
            statusColor = Colors.red;
            statusText = 'orders.status_canceled'.tr();
          }

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: Icon(Icons.assignment, color: statusColor, size: 32),
              title: Text(
                "${'orders.order_number'.tr()} #${order.id}",
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('${'messages.status_with_colon'.tr()} $statusText'),
                  Text('${'messages.amount'.tr()}: ${order.totalAmount.toStringAsFixed(0)} ${'common.currency'.tr()}'),
                  Text('${'messages.date_with_colon'.tr()} ${DateFormat('dd.MM.yyyy').format(order.startDate)}'),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.arrow_forward_ios),
                onPressed: () {
                  // Buyurtma tafsilotlariga o'tish
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

/// ---------------------
/// Franchise Income Page
/// ---------------------
class FranchiseIncomePage extends StatefulWidget {
  final FranchiseModel? franchise;

  const FranchiseIncomePage({super.key, this.franchise});

  @override
  State<FranchiseIncomePage> createState() => _FranchiseIncomePageState();
}

class _FranchiseIncomePageState extends State<FranchiseIncomePage> {
  final FranchiseService _franchiseService = FranchiseService();
  List<dynamic> _payments = [];
  bool _isLoading = true;

  double _todayIncome = 0.0;
  double _monthIncome = 0.0;
  double _totalIncome = 0.0;

  @override
  void initState() {
    super.initState();
    _loadPayments();
  }

  Future<void> _loadPayments() async {
    if (widget.franchise == null) return;

    try {
      setState(() => _isLoading = true);
      final payments = await _franchiseService.getFranchisePayments(
        widget.franchise!.id,
        status: 'paid',
      );

      // Daromadlarni hisoblash
      final now = DateTime.now();
      double todayIncome = 0.0;
      double monthIncome = 0.0;
      double totalIncome = 0.0;

      for (var payment in payments) {
        final amount = payment.amount - payment.commission;
        totalIncome += amount;

        if (payment.paidAt != null) {
          final paidDate = payment.paidAt!;

          if (paidDate.year == now.year &&
              paidDate.month == now.month &&
              paidDate.day == now.day) {
            todayIncome += amount;
          }

          if (paidDate.year == now.year && paidDate.month == now.month) {
            monthIncome += amount;
          }
        }
      }

      setState(() {
        _payments = payments;
        _todayIncome = todayIncome;
        _monthIncome = monthIncome;
        _totalIncome = totalIncome;
        _isLoading = false;
      });
    } catch (e) {
      print('Load franchise payments error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,));
    }

    return RefreshIndicator(
      onRefresh: _loadPayments,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Statistika kartochkalari
            _buildStatCard(
              'franchise.income_today'.tr(),
              '${_todayIncome.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.today,
              Colors.green,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'franchise.income_monthly'.tr(),
              '${_monthIncome.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.calendar_month,
              Colors.blue,
            ),
            const SizedBox(height: 12),
            _buildStatCard(
              'franchise.income_total'.tr(),
              '${_totalIncome.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.account_balance_wallet,
              Colors.purple,
            ),
            const SizedBox(height: 24),

            // To'lovlar ro'yxati
            if (_payments.isNotEmpty) ...[
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'So\'nggi to\'lovlar',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _payments.length > 10 ? 10 : _payments.length,
                itemBuilder: (context, index) {
                  final payment = _payments[index];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.payment, color: Colors.green),
                      title: Text('${'messages.payment_hash'.tr()}${payment.id}'),
                      subtitle: Text(
                        payment.paidAt != null
                            ? DateFormat('dd.MM.yyyy HH:mm').format(payment.paidAt!)
                            : 'N/A',
                      ),
                      trailing: Text(
                        '${(payment.amount - payment.commission).toStringAsFixed(0)} ${'common.currency'.tr()}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ---------------------
/// Franchise Stats Page
/// ---------------------
class FranchiseStatsPage extends StatefulWidget {
  final FranchiseModel? franchise;

  const FranchiseStatsPage({super.key, this.franchise});

  @override
  State<FranchiseStatsPage> createState() => _FranchiseStatsPageState();
}

class _FranchiseStatsPageState extends State<FranchiseStatsPage> {
  final FranchiseService _franchiseService = FranchiseService();
  FranchiseStatsModel? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    if (widget.franchise == null) return;

    try {
      setState(() => _isLoading = true);
      final stats = await _franchiseService.getFranchiseStats(widget.franchise!.id);
      setState(() {
        _stats = stats;
        _isLoading = false;
      });
    } catch (e) {
      print('Load franchise stats error: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen,));
    }

    if (_stats == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.analytics, size: 80, color: Colors.grey),
            const SizedBox(height: 20),
            Text(
              'franchise.no_stats'.tr(),
              style: const TextStyle(fontSize: 18),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Franchise ma'lumotlari
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.store_mall_directory, size: 32, color: Colors.blue),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.franchise!.name,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                widget.franchise!.region,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildInfoRow('Status', widget.franchise!.status),
                    if (widget.franchise!.royaltyPercentage != null)
                      _buildInfoRow('Royalti', '${widget.franchise!.royaltyPercentage}%'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Statistika
            Text(
              'statistics.title'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.equipment_count'.tr(),
              '${_stats!.totalEquipment}',
              Icons.agriculture,
              Colors.green,
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.active_orders'.tr(),
              '${_stats!.activeOrders}',
              Icons.assignment,
              Colors.blue,
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.completed_orders'.tr(),
              '${_stats!.completedOrders}',
              Icons.assignment_turned_in,
              Colors.grey,
            ),
            const SizedBox(height: 24),

            // Moliyaviy statistika
            Text(
              'statistics.financial'.tr(),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.total_revenue'.tr(),
              '${_stats!.totalRevenue.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.account_balance_wallet,
              Colors.purple,
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.total_royalty'.tr(),
              '${_stats!.totalRoyalty.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.monetization_on,
              Colors.orange,
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.monthly_revenue'.tr(),
              '${_stats!.monthlyRevenue.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.calendar_month,
              Colors.teal,
            ),
            const SizedBox(height: 12),

            _buildStatCard(
              'statistics.monthly_royalty'.tr(),
              '${_stats!.monthlyRoyalty.toStringAsFixed(0)} ${'common.currency'.tr()}',
              Icons.payment,
              Colors.indigo,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.grey),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
