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
import 'driver_earnings_tab.dart';
import 'driver_orders_tab.dart';

/// Главная MoveX GO Driver: «Buyurtmalar», «Daromad», «Profil» (макет).
class DriverHomePage extends StatefulWidget {
  const DriverHomePage({super.key});

  @override
  State<DriverHomePage> createState() => _DriverHomePageState();
}

class _DriverHomePageState extends State<DriverHomePage> {
  int _tab = 0;

  /// «Daromad» пересоздаётся при каждом открытии: заказ мог завершиться,
  /// пока водитель был на «Buyurtmalar», и цифры должны быть свежими.
  int _earningsOpened = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          const DriverOrdersTab(),
          DriverEarningsTab(key: ValueKey(_earningsOpened)),
          const DriverProfileTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          if (i == 1 && _tab != 1) _earningsOpened++;
          _tab = i;
        }),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.local_shipping_outlined), label: 'driver.tab_orders'.tr()),
          NavigationDestination(icon: const Icon(Icons.payments_outlined), label: 'driver.tab_earnings'.tr()),
          NavigationDestination(icon: const Icon(Icons.person_outline_rounded), label: 'driver.tab_profile'.tr()),
        ],
      ),
    );
  }
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
    return Scaffold(
      backgroundColor: AppPalette.page,
      appBar: AppBar(title: Text('driver.tab_profile'.tr()), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppPalette.brandSubtle,
                  child: Text(
                    (me?.fullName.isNotEmpty ?? false) ? me!.fullName.characters.first.toUpperCase() : '?',
                    style: AppTypography.h2.copyWith(color: AppPalette.textBrand),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(me?.fullName ?? '…', style: AppTypography.h3),
                      if (me?.phone != null)
                        Text('+${me!.phone}', style: AppTypography.bodyM.copyWith(color: AppPalette.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          _item(Icons.construction_rounded, 'driver.my_equipment'.tr(), () => _push(const MyEquipmentPage())),
          _item(Icons.campaign_outlined, 'driver.listings'.tr(), () => _push(const ListingsPage())),
          _item(Icons.notifications_none_rounded, 'driver.notifications'.tr(), () => context.push('/notifications')),
          _item(Icons.settings_outlined, 'driver.settings'.tr(), () => context.push('/settings')),
          _item(Icons.logout_rounded, 'driver.logout'.tr(), _logout, danger: true),
          const SizedBox(height: AppSpacing.xl),
          const DeleteAccountButton(),
        ],
      ),
    );
  }

  Widget _item(IconData icon, String title, VoidCallback onTap, {bool danger = false}) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: AppPalette.surface,
          borderRadius: BorderRadius.circular(16),
          child: ListTile(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            leading: Icon(icon, color: danger ? AppPalette.textDanger : AppPalette.iconPrimary),
            title: Text(title, style: TextStyle(color: danger ? AppPalette.textDanger : null)),
            trailing: danger ? null : const Icon(Icons.chevron_right_rounded),
            onTap: onTap,
          ),
        ),
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
