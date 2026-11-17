import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/balance_service.dart';
import '../../../../core/services/order_service.dart';
import '../../../../core/services/pin_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/theme/app_tokens.dart';
import '../../../client_home/presentation/pages/client_catalog_page.dart';
import '../../../client_home/presentation/pages/client_main_page.dart';
import '../../../listings/presentation/pages/listings_page.dart';
import '../../../settings/presentation/pages/privacy_page.dart';
import '../../../settings/presentation/pages/terms_page.dart';
import '../../data/card_api.dart';
import '../../data/taxi_service.dart';
import '../widgets/taxi_ui.dart';
import 'help_page.dart';
import 'payment_methods_page.dart';
import 'personal_page.dart';
import 'saved_addresses_page.dart';
import 'orders_page.dart';
import 'taxi_notifications_page.dart';

/// Профиль клиента — макет «Pr1 · Profil» (клиентский файл, страница
/// «Profil»). В новом дизайне у клиента НЕТ нижнего меню: главная — заказ
/// на весь экран, а всё остальное открывается отсюда.
///
/// Каталог и объявления в макете не нарисованы, но они остаются в
/// приложении (решение владельца от 12.11.2026) — поэтому лежат в разделе
/// «Asosiy» рядом с заказами. «Saqlangan manzillar» и карты из макета
/// пока не сделаны: на сервере их нет.
class TaxiProfilePage extends StatefulWidget {
  const TaxiProfilePage({super.key});

  @override
  State<TaxiProfilePage> createState() => _TaxiProfilePageState();
}

class _TaxiProfilePageState extends State<TaxiProfilePage> {
  String? _name;
  String? _phone;
  int? _orders;
  int? _hours;
  double? _balance;
  int? _addresses;
  List<BankCard>? _cards;
  String? _avatar;
  String _version = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final u = await UserService().getCurrentUser();
      if (mounted) {
        setState(() {
          _name = u.fullName;
          _phone = u.phone;
          _avatar = u.avatarUrl;
        });
      }
    } catch (_) {}
    try {
      final orders = await OrderService().getOrders();
      final done = orders.where((o) => o.status == 'completed');
      if (mounted) {
        setState(() {
          _orders = orders.length;
          // Часы работы: у тарифных заказов они есть, у посуточных — нет.
          _hours = done.fold<int>(0, (s, o) => s + (o.hours ?? 0));
        });
      }
    } catch (_) {}
    try {
      final b = await BalanceService().getBalance();
      if (mounted) setState(() => _balance = b.balance);
    } catch (_) {}
    try {
      final c = await CardApi().list();
      if (mounted) setState(() => _cards = c);
    } catch (_) {}
    try {
      final a = await ProfileApi().addresses();
      if (mounted) setState(() => _addresses = a.length);
    } catch (_) {}
    try {
      final info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _version = info.version);
    } catch (_) {}
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));

  /// M1: «Kuzatish» и «Qayta buyurtma» решает главная — отдаём ей.
  Future<void> _openOrders() async {
    final nav = await Navigator.of(context).push<TaxiNav>(
      MaterialPageRoute(builder: (_) => const OrdersPage()),
    );
    if (nav != null && mounted) Navigator.of(context).pop(nav);
  }

  String get _initials {
    final parts = (_name ?? '').split(' ').where((p) => p.isNotEmpty).take(2);
    final s = parts.map((p) => p[0].toUpperCase()).join();
    return s.isEmpty ? '?' : s;
  }

  String get _phoneText {
    final d = (_phone ?? '').replaceAll(RegExp(r'\D'), '');
    if (d.length != 12) return _phone ?? '';
    return '+${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 8)} '
        '${d.substring(8, 10)} ${d.substring(10)}';
  }

  /// Pr5 · Ilova tili. Узбекская кириллица в макете есть, но перевода на
  /// неё в приложении нет — показываем только реальные языки.
  Future<void> _language() async {
    var picked = context.locale.languageCode;
    final code = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppPalette.surface,
      barrierColor: const Color(0x730B1220),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD3D8DF), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 12),
                Text('taxi.app_language'.tr(), style: AppTypography.h2),
                const SizedBox(height: 12),
                for (final (c, name, sub) in const [
                  ('uz', "O'zbekcha", 'Lotin yozuvi'),
                  ('ru', 'Русский', 'Русский язык'),
                ]) ...[
                  GestureDetector(
                    onTap: () => set(() => picked = c),
                    child: Container(
                      height: 60,
                      padding: const EdgeInsets.only(left: 12, right: 14),
                      decoration: BoxDecoration(
                        color: picked == c ? AppPalette.brandSubtle : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: picked == c ? AppPalette.surface : AppPalette.page,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: const TaxiIcon('globe', size: 24),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: AppTypography.bodyMedium),
                                Text(sub, style: AppTypography.captionS.copyWith(fontSize: 13, height: 18 / 13)),
                              ],
                            ),
                          ),
                          picked == c
                              ? const TaxiIcon('radio_on', size: 22)
                              : Container(
                                  width: 22,
                                  height: 22,
                                  decoration: BoxDecoration(
                                    color: AppPalette.surface,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: const Color(0xFFC9D0D9), width: 2),
                                  ),
                                ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(picked),
                  child: Text('taxi.save'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (code == null || !mounted || code == context.locale.languageCode) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', code);
    await UserService().setLanguage(code);
    if (!mounted) return;
    await context.setLocale(Locale(code));
  }

  /// Pr6 · Chiqishni tasdiqlash.
  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierColor: const Color(0x730B1220),
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: AppPalette.dangerSubtle, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const TaxiIcon('logout', size: 28),
                ),
              ),
              const SizedBox(height: 10),
              Text('taxi.logout_title'.tr(), textAlign: TextAlign.center, style: AppTypography.h3),
              const SizedBox(height: 10),
              Text('taxi.logout_body'.tr(), textAlign: TextAlign.center, style: AppTypography.subtitle),
              const SizedBox(height: 16),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    backgroundColor: AppPalette.brandSubtle,
                    foregroundColor: AppPalette.textDanger,
                    textStyle: AppTypography.buttonLarge,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                  ),
                  child: Text('settings.logout'.tr()),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: AppSpacing.buttonHeight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    foregroundColor: AppPalette.textBrand,
                    textStyle: AppTypography.buttonLarge,
                  ),
                  child: Text('taxi.cancel'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    // PIN тоже стирается: иначе следующего человека на этом телефоне
    // встретил бы код прежнего.
    await PinService.resetOnLogout();
    if (!mounted) return;
    context.go('/');
  }

  Future<void> _push(Widget page) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    _load();
  }

  Widget _stat(String value, String label) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontFamily: AppTypography.fontFamily,
                    fontSize: 20,
                    height: 26 / 20,
                    fontWeight: FontWeight.w700,
                    color: AppPalette.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: AppTypography.captionS.copyWith(fontSize: 13, height: 18 / 13)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final lang = context.locale.languageCode == 'ru' ? 'Русский' : "O'zbekcha";
    return Scaffold(
      backgroundColor: AppPalette.page,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TaxiPageHeader(title: 'profile.title'.tr()),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
                    decoration:
                        BoxDecoration(color: AppPalette.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
                    child: Row(
                      children: [
                        ProfileAvatar(size: 60, initials: _initials, url: _avatar),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_name ?? '', style: AppTypography.h3, maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(_phoneText, style: AppTypography.subtitle),
                            ],
                          ),
                        ),
                        TaxiRoundButton(icon: 'edit_brand', onTap: () => _push(const PersonalPage())),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      _stat(_orders?.toString() ?? '—', 'profile.stat_orders'.tr()),
                      const SizedBox(width: 10),
                      _stat(_hours?.toString() ?? '—', 'profile.stat_hours'.tr()),
                      const SizedBox(width: 10),
                      _stat(_cards?.length.toString() ?? '—', 'taxi.stat_cards'.tr()),
                    ],
                  ),
                  const SizedBox(height: 20),
                  GroupLabel('profile.section_main'.tr()),
                  const SizedBox(height: 8),
                  MenuCard(children: [
                    MenuRow(icon: 'orders', title: 'profile.my_orders'.tr(), value: _orders?.toString(), onTap: _openOrders),
                    MenuRow(
                      icon: 'menu_card',
                      title: 'taxi.payment_methods'.tr(),
                      value: (_cards ?? const <BankCard>[]).where((c) => c.isDefault).firstOrNull?.label ??
                          (_balance == null ? null : "${formatSum(_balance!)} ${'common.currency'.tr()}"),
                      onTap: () => _push(const PaymentMethodsPage()),
                    ),
                    MenuRow(
                      icon: 'menu_pin',
                      title: 'taxi.saved_addresses'.tr(),
                      value: _addresses?.toString(),
                      onTap: () => _push(const SavedAddressesPage()),
                    ),
                    // Каталог, объявления и старая карта в макете не нарисованы,
                    // но остаются в приложении (решение владельца, 12.11.2026).
                    MenuRow(iconData: Icons.grid_view_outlined, title: 'client.catalog'.tr(),
                        onTap: () => _open(const ClientCatalogPage())),
                    MenuRow(iconData: Icons.campaign_outlined, title: 'client.listings'.tr(),
                        onTap: () => _open(const ListingsPage())),
                    MenuRow(iconData: Icons.map_outlined, title: 'taxi.equipment_map'.tr(),
                        onTap: () => _open(const _WithBack(child: ClientMainPage()))),
                  ]),
                  const SizedBox(height: 20),
                  GroupLabel('profile.section_settings'.tr()),
                  const SizedBox(height: 8),
                  MenuCard(children: [
                    MenuRow(icon: 'menu_bell', title: 'notifications.title'.tr(),
                        onTap: () => _open(const TaxiNotificationsPage())),
                    MenuRow(icon: 'menu_globe', title: 'settings.language'.tr(), value: lang, onTap: _language),
                    MenuRow(icon: 'menu_help', title: 'profile.help'.tr(), onTap: () => _open(const HelpPage())),
                  ]),
                  const SizedBox(height: 20),
                  GroupLabel('profile.section_docs'.tr()),
                  const SizedBox(height: 8),
                  MenuCard(children: [
                    MenuRow(icon: 'menu_doc', title: 'settings.terms'.tr(), onTap: () => _open(const TermsPage())),
                    MenuRow(icon: 'menu_shield', title: 'settings.privacy_policy'.tr(),
                        onTap: () => _open(const PrivacyPage())),
                  ]),
                  const SizedBox(height: 20),
                  MenuCard(children: [
                    MenuRow(
                      icon: 'menu_logout',
                      iconBg: AppPalette.dangerSubtle,
                      title: 'settings.logout'.tr(),
                      color: AppPalette.textDanger,
                      chevron: false,
                      onTap: _logout,
                    ),
                  ]),
                  const SizedBox(height: 20),
                  Text(
                    'MoveX GO · ${'profile.version'.tr()} $_version',
                    textAlign: TextAlign.center,
                    style: AppTypography.captionS,
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

/// Старая страница-вкладка без своей шапки: поверх неё — «назад».
class _WithBack extends StatelessWidget {
  const _WithBack({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          Positioned.fill(child: child),
          Positioned(
            top: MediaQuery.of(context).padding.top + AppSpacing.sm,
            left: AppSpacing.gutter,
            child: MapIconButton(
              icon: 'back',
              label: 'auth.back'.tr(),
              onTap: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      );
}
