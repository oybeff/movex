import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:toastification/toastification.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/balance_service.dart';
import '../../../../core/models/user_model.dart';
import '../../../../core/models/contact_method_model.dart';
import '../../../../core/models/balance_model.dart';
import '../../../../core/utils/number_formatter.dart';
import 'client_profile_detail_page.dart';
import 'client_payments_page.dart';
import 'client_balance_page.dart';
import '../../../settings/presentation/pages/terms_page.dart';
import '../../../settings/presentation/pages/privacy_page.dart';

class ClientProfilePage extends StatefulWidget {
  const ClientProfilePage({super.key});

  @override
  State<ClientProfilePage> createState() => _ClientProfilePageState();
}

class _ClientProfilePageState extends State<ClientProfilePage> {
  final UserService _userService = UserService();
  final SettingsService _settingsService = SettingsService();
  final BalanceService _balanceService = BalanceService();
  UserModel? _user;
  BalanceModel? _balance;
  bool _isLoading = true;
  bool _isLoadingBalance = true;
  String _appVersion = '1.0.0';
  List<ContactMethodModel>? _contactMethods;
  bool _isLoadingContacts = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadBalance();
    _loadAppVersion();
    _loadContactMethods();
  }

  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    try {
      final user = await _userService.getCurrentUser();
      setState(() {
        _user = user;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('${'profile.update_error'.tr()}: $e'),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
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
      print('Error loading balance: $e');
    }
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (${packageInfo.buildNumber})';
      });
    } catch (e) {
      print('Error loading app version: $e');
    }
  }

  Future<void> _loadContactMethods() async {
    setState(() => _isLoadingContacts = true);
    try {
      final methods = await _settingsService.getContactMethods();
      setState(() {
        _contactMethods = methods;
        _isLoadingContacts = false;
      });
    } catch (e) {
      print('Error loading contact methods: $e');
      setState(() => _isLoadingContacts = false);
    }
  }

  Widget _buildBalanceCard() {
    if (_isLoadingBalance) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primaryGreen, Color(0xFF00A86B)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryGreen.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: CircularProgressIndicator(
            color: Colors.white,
          ),
        ),
      );
    }

    if (_balance == null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primaryGreen, Color(0xFF00A86B)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primaryGreen.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Jami balans va aktiv va muzlatilgan hisoblar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'balance.total'.tr(),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${NumberFormatter.formatCurrency(_balance!.balance)} so\'m',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white.withValues(alpha: 0.6),
                size: 28,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Aktiv va muzlatilgan hisoblar
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.check_circle_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'balance.active'.tr(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        NumberFormatter.formatCurrency(_balance!.availableBalance) + ' so\'m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lock_rounded,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'balance.frozen'.tr(),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        NumberFormatter.formatCurrency(_balance!.frozenBalance) + ' so\'m',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageBottomSheet() async {
    final currentLocale = context.locale.languageCode;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'settings.select_language'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 24),
            _LanguageOption(
              title: 'O\'zbek',
              flag: '🇺🇿',
              isSelected: currentLocale == 'uz',
              onTap: () async {
                await context.setLocale(const Locale('uz'));
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('selected_language', 'uz');
                if (!mounted) return;
                Navigator.of(context).pop();
                context.go('/clientHome');
              },
            ),
            const SizedBox(height: 12),
            _LanguageOption(
              title: 'Русский',
              flag: '🇷🇺',
              isSelected: currentLocale == 'ru',
              onTap: () async {
                await context.setLocale(const Locale('ru'));
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString('selected_language', 'ru');
                if (!mounted) return;
                Navigator.of(context).pop();
                context.go('/clientHome');
              },
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _showContactUsBottomSheet() async {
    if (_contactMethods == null && !_isLoadingContacts) {
      await _loadContactMethods();
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'contact.title'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'contact.subtitle'.tr(),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 24),
            _isLoadingContacts
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: AppColors.primaryGreen),
                    ),
                  )
                : _contactMethods == null || _contactMethods!.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Text(
                          'contact.error'.tr(),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: _contactMethods!.map((method) {
                          return _ContactMethodTile(
                            method: method,
                            onTap: () => _launchContactMethod(method),
                          );
                        }).toList(),
                      ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _launchContactMethod(ContactMethodModel method) async {
    String url = '';

    switch (method.type.toLowerCase()) {
      case 'phone':
        url = 'tel:${method.value}';
        break;
      case 'email':
        url = 'mailto:${method.value}';
        break;
      case 'telegram':
        url = method.value.startsWith('http') ? method.value : 'https://t.me/${method.value}';
        break;
      case 'whatsapp':
        url = 'https://wa.me/${method.value.replaceAll(RegExp(r'[^\d]'), '')}';
        break;
      case 'website':
        url = method.value.startsWith('http') ? method.value : 'https://${method.value}';
        break;
      case 'sms':
        url = 'sms:${method.value}';
        break;
      default:
        url = method.value;
    }

    try {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          toastification.show(
            context: context,
            type: ToastificationType.error,
            style: ToastificationStyle.flatColored,
            title: Text('contact.no_app'.tr()),
            autoCloseDuration: const Duration(seconds: 3),
            alignment: Alignment.topCenter,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        toastification.show(
          context: context,
          type: ToastificationType.error,
          style: ToastificationStyle.flatColored,
          title: Text('${'contact.error'.tr()}: $e'),
          autoCloseDuration: const Duration(seconds: 3),
          alignment: Alignment.topCenter,
        );
      }
    }
  }

  Future<void> _showLogoutDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('settings.logout_confirm_title'.tr()),
        content: Text('settings.logout_confirm_message'.tr()),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('settings.cancel'.tr()),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text('settings.confirm'.tr()),
          ),
        ],
      ),
    );

    if (result == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('role');
      if (!mounted) return;
      context.go('/');
    }
  }

  Future<void> _showEditProfileBottomSheet() async {
    if (_user == null) return;

    final fullNameController = TextEditingController(text: _user!.fullName);
    final phoneController = TextEditingController(text: _user!.phone ?? '');

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'profile.edit_profile'.tr(),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.black,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              // Full Name
              TextField(
                controller: fullNameController,
                decoration: InputDecoration(
                  labelText: 'profile.full_name'.tr(),
                  prefixIcon: const Icon(Icons.person_rounded, color: AppColors.primaryGreen),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Phone
              TextField(
                controller: phoneController,
                enabled: false,
                decoration: InputDecoration(
                  labelText: 'profile.phone'.tr(),
                  prefixIcon: const Icon(Icons.phone_rounded, color: AppColors.primaryGreen),
                  filled: true,
                  fillColor: Colors.grey[100],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primaryGreen, width: 2),
                  ),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 24),

              // Save Button
              ElevatedButton(
                onPressed: () async {
                  try {
                    await _userService.updateCurrentUser(
                      fullName: fullNameController.text,
                      phone: phoneController.text.isEmpty ? null : phoneController.text,
                    );

                    if (!mounted) return;
                    Navigator.pop(context);

                    toastification.show(
                      context: context,
                      type: ToastificationType.success,
                      style: ToastificationStyle.flatColored,
                      title: Text('profile.update_success'.tr()),
                      autoCloseDuration: const Duration(seconds: 3),
                      alignment: Alignment.topCenter,
                    );

                    _loadUserData();
                  } catch (e) {
                    if (!mounted) return;
                    toastification.show(
                      context: context,
                      type: ToastificationType.error,
                      style: ToastificationStyle.flatColored,
                      title: Text('${'profile.update_error'.tr()}: $e'),
                      autoCloseDuration: const Duration(seconds: 3),
                      alignment: Alignment.topCenter,
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: Text(
                  'common.save'.tr(),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
       
        body: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
            : _user == null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          'profile.update_error'.tr(),
                          style: const TextStyle(fontSize: 16, color: Colors.grey),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadUserData,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryGreen,
                            foregroundColor: Colors.white,
                          ),
                          child: Text('messages.retry'.tr()),
                        ),
                      ],
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisAlignment: MainAxisAlignment.start,
                      children: [
                        SizedBox(height: 60,),
                        // Avatar
                        CircleAvatar(
                          radius: 50,
                          backgroundColor: AppColors.primaryGreen.withValues(alpha: 0.1),
                          child: Text(
                            _user!.fullName.isNotEmpty ? _user!.fullName[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Full Name
                        Column(
                          children: [
                            Text(
                              _user!.fullName,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: AppColors.black,
                              ),
                            ),
                            const SizedBox(height: 8),

                        // Role
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _user!.role == 'owner' ? 'role_select.owner'.tr() : 'role_select.client'.tr(),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryGreen,
                            ),
                          ),
                        ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Balans kartasi
                        _buildBalanceCard(),

                        const SizedBox(height: 16),

                        // Mening profilim
                        // _SectionHeader(title: 'settings.account'.tr()),
                        // const SizedBox(height: 12),
                        _SettingsCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.person_rounded,
                              title: 'settings.profile'.tr(),
                              subtitle: 'settings.profile_desc'.tr(),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ClientProfileDetailPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Hisob va To'lovlar
                        _SettingsCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.account_balance_wallet_rounded,
                              title: 'balance.topup'.tr(),
                              subtitle: 'Hisobni to\'ldirish va tarix',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ClientBalancePage(),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1, color: Colors.black12),
                            _SettingsTile(
                              icon: Icons.payment_rounded,
                              title: 'client.payments'.tr(),
                              subtitle: 'To\'lovlar tarixi',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const ClientPaymentsPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Sozlamalar
                        // _SectionHeader(title: 'settings.general'.tr()),
                        // const SizedBox(height: 12),
                        _SettingsCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.language_rounded,
                              title: 'settings.language'.tr(),
                              subtitle: context.locale.languageCode == 'uz' ? 'O\'zbek' : 'Русский',
                              onTap: _showLanguageBottomSheet,
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // Yordam
                        // _SectionHeader(title: 'settings.support'.tr()),
                        // const SizedBox(height: 12),
                        _SettingsCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.contact_support_rounded,
                              title: 'settings.contact_us'.tr(),
                              subtitle: 'settings.contact_us_desc'.tr(),
                              onTap: _showContactUsBottomSheet,
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Ilova haqida
                        _SectionHeader(title: 'settings.about'.tr()),
                        const SizedBox(height: 12),
                        _SettingsCard(
                          children: [
                            _SettingsTile(
                              icon: Icons.info_rounded,
                              title: 'settings.version'.tr(),
                              subtitle: _appVersion,
                              showArrow: false,
                            ),
                            const Divider(height: 1, color: Colors.black12),
                            _SettingsTile(
                              icon: Icons.description_rounded,
                              title: 'settings.terms'.tr(),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const TermsPage(),
                                  ),
                                );
                              },
                            ),
                            const Divider(height: 1, color: Colors.black12),
                            _SettingsTile(
                              icon: Icons.privacy_tip_rounded,
                              title: 'settings.privacy_policy'.tr(),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => const PrivacyPage(),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),

                        const SizedBox(height: 32),

                        // Chiqish tugmasi
                        _LogoutButton(onTap: _showLogoutDialog),

                        const SizedBox(height: 90), // Bottom navigation uchun joy
                      ],
                    ),
                  ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColors.grey,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;

  const _SettingsCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(children: children),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool showArrow;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.showArrow = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppColors.primaryGreen.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          icon,
          color: AppColors.primaryGreen,
          size: 22,
        ),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: AppColors.black,
        ),
      ),
      subtitle: subtitle != null
          ? Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                subtitle!,
                style: TextStyle(
                  fontSize: 13,
                  color: AppColors.grey.withValues(alpha: 0.8),
                ),
              ),
            )
          : null,
      trailing: showArrow
          ? const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: AppColors.grey,
            )
          : null,
    );
  }
}

class _ContactMethodTile extends StatelessWidget {
  final ContactMethodModel method;
  final VoidCallback onTap;

  const _ContactMethodTile({
    required this.method,
    required this.onTap,
  });

  IconData _getIconForType(String type) {
    switch (type.toLowerCase()) {
      case 'phone':
        return Icons.phone_rounded;
      case 'email':
        return Icons.email_rounded;
      case 'telegram':
        return Icons.telegram;
      case 'whatsapp':
        return Icons.chat_rounded;
      case 'website':
        return Icons.language_rounded;
      case 'sms':
        return Icons.sms_rounded;
      default:
        return Icons.contact_support_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppColors.primaryGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                _getIconForType(method.type),
                color: AppColors.primaryGreen,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    method.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    method.value,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;

  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.red.shade200,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.logout_rounded,
              color: Colors.red.shade600,
              size: 22,
            ),
            const SizedBox(width: 12),
            Text(
              'settings.logout'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LanguageOption extends StatelessWidget {
  final String title;
  final String flag;
  final bool isSelected;
  final VoidCallback onTap;

  const _LanguageOption({
    required this.title,
    required this.flag,
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
          color: isSelected
              ? AppColors.primaryGreen.withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryGreen
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppColors.primaryGreen
                      : AppColors.black,
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
