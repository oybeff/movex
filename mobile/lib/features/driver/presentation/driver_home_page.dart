import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/models/user_model.dart';
import '../../../core/services/auth_service.dart';
import '../../../core/services/pin_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/widgets/delete_account_button.dart';
import '../../listings/presentation/pages/listings_page.dart';
import '../../owner_home/presentation/pages/my_equipment_page.dart';
import '../../requests/presentation/pages/search_area_page.dart';
import 'driver_earnings_tab.dart';
import 'driver_history_tab.dart';
import 'driver_verification_page.dart';
import 'driver_orders_tab.dart';

/// Главная MoveX GO Driver — нижнее меню макета: «Asosiy», «Buyurtmalar»,
/// «Daromad», «Profil».
class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  int _tab = 0;

  /// «Buyurtmalar» и «Daromad» пересоздаются при каждом открытии: заказ
  /// мог завершиться, пока водитель был на «Asosiy», цифры должны быть свежими.
  int _opened = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const DriverOrdersTab(),
          DriverHistoryTab(key: ValueKey('h$_opened')),
          DriverEarningsTab(key: ValueKey('e$_opened')),
          const DriverProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        backgroundColor: AppPalette.surface,
        indicatorColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        onDestinationSelected: (i) => setState(() {
          if (i != _tab && (i == 1 || i == 2)) _opened++;
          _tab = i;
        }),
        destinations: [
          _dest(Icons.near_me_outlined, Icons.near_me_rounded, 'driver.tab_home'.tr()),
          _dest(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'driver.tab_orders'.tr()),
          _dest(Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'driver.tab_earnings'.tr()),
          _dest(Icons.person_outline_rounded, Icons.person_rounded, 'driver.tab_profile'.tr()),
        ],
      ),
    );
  }

  NavigationDestination _dest(IconData icon, IconData active, String label) => NavigationDestination(
        icon: Icon(icon, color: AppPalette.textSecondary),
        selectedIcon: Icon(active, color: AppPalette.brand),
        label: label,
      );
}

/// «Profil»: техника, объявления, уведомления, настройки, выход.
/// Экраны техники и объявлений — те же, что у владельца в клиентском
/// приложении: правка в одном месте видна в обоих.
class DriverProfileTab extends StatefulWidget {
  const DriverProfileTab({super.key});

  @override
  State<DriverProfileTab> createState() => _DriverProfileTabState();
}

class _DriverProfileTabState extends State<DriverProfileTab> {
  UserModel? _me;

  @override
  void initState() {
    super.initState();
    AuthService().getCurrentUser().then((u) {
      if (mounted) setState(() => _me = u);
    }).catchError((_) {});
  }

  Future<void> _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('driver.logout_title'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('driver.back'.tr())),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text('driver.logout'.tr())),
        ],
      ),
    );
    if (ok != true) return;
    await driverLogout();
    if (mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final parts = (me?.fullName ?? '').trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Pr1: шапка профиля
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: AppPalette.brand,
                    child: Text(initials, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me?.fullName ?? '…', style: AppTypography.h3),
                        if (me?.phone != null)
                          Text('+${me!.phone}', style: const TextStyle(fontSize: 13, color: AppPalette.textSecondary)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppPalette.successSubtle, borderRadius: BorderRadius.circular(6)),
                          child: Text('driver.owner_badge'.tr(),
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppPalette.textSuccess)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _group([
              _item(Icons.construction_rounded, 'driver.my_equipment'.tr(), () => _push(const MyEquipmentPage())),
              _item(Icons.badge_outlined, 'driver.documents'.tr(), () => _push(const DriverVerificationPage())),
              _item(Icons.radar_rounded, 'driver.work_area'.tr(), () => _push(const SearchAreaPage(isOwner: true))),
              _item(Icons.campaign_outlined, 'driver.listings'.tr(), () => _push(const ListingsPage())),
            ]),
            const SizedBox(height: 12),
            _group([
              _item(Icons.credit_card_rounded, 'driver.withdraw'.tr(), () => context.push('/payout')),
              _item(Icons.notifications_none_rounded, 'driver.notifications'.tr(), () => context.push('/notifications')),
              _item(Icons.language_rounded, 'driver.settings'.tr(), () => context.push('/settings')),
              _item(Icons.logout_rounded, 'driver.logout'.tr(), _logout, danger: true),
            ]),
            const SizedBox(height: 24),
            const DeleteAccountButton(),
          ],
        ),
      ),
    );
  }

  Widget _group(List<Widget> items) => Container(
        decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(16)),
        child: Column(children: items),
      );

  Widget _item(IconData icon, String title, VoidCallback onTap, {bool danger = false}) => ListTile(
        leading: Icon(icon, color: danger ? AppPalette.textDanger : AppPalette.iconPrimary),
        title: Text(title, style: TextStyle(fontSize: 15, color: danger ? AppPalette.textDanger : AppPalette.textPrimary)),
        trailing: danger ? null : const Icon(Icons.chevron_right_rounded, color: AppPalette.textSecondary),
        onTap: onTap,
      );

}

/// Выход: токен, роль и ПИН стираются — как в клиентском профиле.
Future<void> driverLogout() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('token');
  await prefs.remove('role');
  await PinService.resetOnLogout();
}

/// Клиентский аккаунт в приложении водителя: объясняем и предлагаем выйти.
class DriverWrongRolePage extends StatelessWidget {
  const DriverWrongRolePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.local_shipping_rounded, size: 72, color: AppPalette.brand),
              const SizedBox(height: AppSpacing.lg),
              Text('driver.wrong_role_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h2),
              const SizedBox(height: AppSpacing.sm),
              Text('driver.wrong_role_body'.tr(),
                  textAlign: TextAlign.center, style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
              const SizedBox(height: AppSpacing.xl),
              ElevatedButton(
                onPressed: () async {
                  await driverLogout();
                  if (context.mounted) context.go('/');
                },
                child: Text('driver.logout'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
