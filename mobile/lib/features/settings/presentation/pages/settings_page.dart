import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/pin_service.dart';
import '../../../auth/presentation/pages/pin_page.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/services/settings_service.dart';
import '../../../../core/services/user_service.dart';
import '../../../../core/models/contact_method_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../owner_home/presentation/pages/payments_page.dart';
import '../../../balance/presentation/pages/balance_topup_page.dart';
import '../../../requests/presentation/pages/requests_feed_page.dart';
import '../../../requests/presentation/pages/search_area_page.dart';
import 'profile_page.dart';
import 'terms_page.dart';
import 'privacy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final SettingsService _settingsService = SettingsService();
  final UserService _userService = UserService();
  String _appVersion = '1.0.0';
  List<ContactMethodModel>? _contactMethods;
  bool _isLoadingContacts = false;
  UserModel? _user;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadAppVersion();
    _loadContactMethods();
    _loadPinState();
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'profile.update_error'.tr()}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadContactMethods() async {
    setState(() {
      _isLoadingContacts = true;
    });
    try {
      final methods = await _settingsService.getContactMethods();
      setState(() {
        _contactMethods = methods;
        _isLoadingContacts = false;
      });
    } catch (e) {
      print('Error loading contact methods: $e');
      setState(() {
        _isLoadingContacts = false;
      });
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



  /// Tilni almashtirish.
  ///
  /// Tartib muhim: avval oynani yopamiz, keyin til almashadi.
  /// Ilgari teskarisi edi — setLocale butun daraxtni qayta quradi va
  /// undan keyingi `if (!mounted) return;` ishga tushib, Navigator.pop()
  /// bajarilmay qolardi: til o'zgarardi, lekin oyna ochiq qolib,
  /// belgi eski tilda turaverardi.
  ///
  /// [sheetContext] — oynaning o'z konteksti, uni yopish uchun kerak.
  Future<void> _applyLanguage(BuildContext sheetContext, String code) async {
    final navigator = Navigator.of(sheetContext);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', code);

    // Serverga ham aytamiz: xabarnoma va push matnini u yozadi va
    // foydalanuvchining tilini bilmasa, hammasi o'zbekcha ketadi.
    await UserService().setLanguage(code);

    if (navigator.canPop()) {
      navigator.pop();
    }

    if (!mounted) return;
    await context.setLocale(Locale(code));

    if (!mounted) return;
    final role = prefs.getString('role');
    context.go(role == 'owner' ? '/ownerHome' : '/clientHome');
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
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'settings.select_language'.tr(),
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.black,
              ),
            ),
            const SizedBox(height: 24),

            // Language options
            _LanguageOption(
              title: 'O\'zbek',
              flag: '🇺🇿',
              isSelected: currentLocale == 'uz',
              onTap: () => _applyLanguage(context, 'uz'),
            ),
            const SizedBox(height: 12),
            _LanguageOption(
              title: 'Русский',
              flag: '🇷🇺',
              isSelected: currentLocale == 'ru',
              onTap: () => _applyLanguage(context, 'ru'),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Future<void> _showContactUsBottomSheet() async {
    // Agar ma'lumotlar yuklanmagan bo'lsa, avval yuklash
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
            // Handle bar
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Title
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

            // Contact methods from state
            _isLoadingContacts
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: CircularProgressIndicator(color: AppColors.primaryGreen,),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('contact.no_app'.tr()),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${'contact.error'.tr()}: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ------------------------------------------------------------- PIN kod
  //
  // Kirish tokeni endi muddatsiz, shuning uchun telefonni PIN kod himoya
  // qiladi. Yangi bo'lim ochilmadi — sozlamalardagi mavjud ro'yxatga
  // qo'shildi.
  //
  // PIN kodni O'CHIRISH yo'q: u majburiy (requirePinSetup). O'chirish
  // tugmasi bo'lsa, odam uni bosib himoyasiz qolardi, keyin esa ekran-
  // zastavka o'rnatishni qaytadan so'rab, cheksiz aylanish chiqardi.
  // Bu yerda faqat kodni almashtirish va barmoq izi tumblerasi.
  bool _pinOn = false;
  bool _biometricOn = false;
  bool _biometricAvailable = false;

  Future<void> _loadPinState() async {
    final on = await PinService.hasPin();
    final bio = await PinService.biometricEnabled();
    final canBio = await PinService.biometricsAvailable();
    if (!mounted) return;
    setState(() {
      _pinOn = on;
      _biometricOn = bio;
      _biometricAvailable = canBio;
    });
  }

  Future<void> _openPinSettings() async {
    if (!_pinOn) {
      final ok = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => const PinPage(mode: PinMode.create)),
      );
      if (ok == true && mounted) _snackPin('pin.saved'.tr());
      await _loadPinState();
      return;
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.password_rounded),
              title: Text('pin.change'.tr()),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _changePin();
              },
            ),
            if (_biometricAvailable)
              SwitchListTile(
                secondary: const Icon(Icons.fingerprint_rounded),
                title: Text('pin.biometric_title'.tr()),
                subtitle: Text('pin.biometric_desc'.tr()),
                value: _biometricOn,
                onChanged: (value) async {
                  // Varaqni AVVAL yopamiz: await dan keyin sheetContext
                  // allaqachon yaroqsiz bo'lishi mumkin.
                  Navigator.pop(sheetContext);
                  await PinService.setBiometricEnabled(value);
                  await _loadPinState();
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _changePin() async {
    // Avval ESKI kod so'raladi: telefonni qo'lga olgan odam kodni
    // shunchaki almashtira olmasin.
    final confirmed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
          builder: (_) => const PinPage(mode: PinMode.confirmCurrent)),
    );
    if (confirmed != true || !mounted) return;
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const PinPage(mode: PinMode.create)),
    );
    if (ok == true && mounted) _snackPin('pin.saved'.tr());
    await _loadPinState();
  }

  void _snackPin(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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
      // PIN ham o'chadi: aks holda telefonda boshqa odam kirsa, uni
      // avvalgi egasining kodi kutib olardi.
      await PinService.resetOnLogout();
      if (!mounted) return;
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentLanguage = context.locale.languageCode == 'uz' ? 'O\'zbek' : 'Русский';

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
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_rounded, color: AppColors.black),
            onPressed: () => Navigator.pop(context),
          ),
        ),
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
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const SizedBox(height: 60),
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

                      // Umumiy sozlamalar
                      // _SectionHeader(title: 'settings.general'.tr()),
                      // const SizedBox(height: 12),
            
            
            // const SizedBox(height: 24),
            
            // // Bildirishnomalar
            // _SectionHeader(title: 'settings.notifications'.tr()),
            // const SizedBox(height: 12),
            // _SettingsCard(
            //   children: [
            //     _SettingsSwitchTile(
            //       icon: Icons.notifications_rounded,
            //       title: 'settings.push_notifications'.tr(),
            //       value: _pushNotifications,
            //       onChanged: (value) {
            //         setState(() => _pushNotifications = value);
            //         _saveNotificationSetting('push_notifications', value);
            //       },
            //     ),
            //     const Divider(height: 1, color: Colors.black12),
            //     _SettingsSwitchTile(
            //       icon: Icons.email_rounded,
            //       title: 'settings.email_notifications'.tr(),
            //       value: _emailNotifications,
            //       onChanged: (value) {
            //         setState(() => _emailNotifications = value);
            //         _saveNotificationSetting('email_notifications', value);
            //       },
            //     ),
            //     const Divider(height: 1, color: Colors.black12),
            //     _SettingsSwitchTile(
            //       icon: Icons.sms_rounded,
            //       title: 'settings.sms_notifications'.tr(),
            //       value: _smsNotifications,
            //       onChanged: (value) {
            //         setState(() => _smsNotifications = value);
            //         _saveNotificationSetting('sms_notifications', value);
            //       },
            //     ),
            //   ],
            // ),
            
            // const SizedBox(height: 16),
            
            // Akkaunt
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
                        builder: (context) => const ProfilePage(),
                      ),
                    );
                  },
                ),
                // PIN kod shu yerda: alohida bo'lim ochilmadi, mavjud
                // ro'yxatga qo'shildi.
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  title: 'pin.settings_title'.tr(),
                  subtitle: _pinOn
                      ? 'pin.settings_desc_on'.tr()
                      : 'pin.settings_desc_off'.tr(),
                  onTap: _openPinSettings,
                ),
                // Ega uchun to'lovlar: shu yergacha yetib borish yo'li yo'q
                // edi — PaymentsPage va undagi pul yechish ekrani faqat
                // to'g'ridan-to'g'ri manzil orqali ochilardi.
                if (_user?.role == 'owner') ...[
                  const Divider(height: 1, color: Colors.black12),
                  _SettingsTile(
                    icon: Icons.account_balance_wallet_rounded,
                    title: 'owner.payments'.tr(),
                    subtitle: 'payout.title'.tr(),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const PaymentsPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, color: Colors.black12),
                  // Ega ham hisobini to'ldira oladi — API bunga hech qachon
                  // to'sqinlik qilmagan, faqat menyuda kirish joyi yo'q edi.
                  _SettingsTile(
                    icon: Icons.add_card_rounded,
                    title: 'balance.topup'.tr(),
                    subtitle: 'profile.topup_and_history'.tr(),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const BalanceTopUpPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, color: Colors.black12),
                  _SettingsTile(
                    icon: Icons.campaign_outlined,
                    title: 'requests.feed'.tr(),
                    subtitle: 'requests.feed_hint'.tr(),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const RequestsFeedPage(),
                        ),
                      );
                    },
                  ),
                ],
                // Radius ikkala rolga ham kerak: egaga zayavkalarni,
                // mijozga texnikani filtrlaydi.
                const Divider(height: 1, color: Colors.black12),
                _SettingsTile(
                  icon: Icons.radar,
                  title: 'area.title'.tr(),
                  subtitle: _user?.role == 'owner'
                      ? 'area.owner_hint'.tr()
                      : 'area.client_hint'.tr(),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) =>
                            SearchAreaPage(isOwner: _user?.role == 'owner'),
                      ),
                    );
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            _SettingsCard(
              children: [
                _SettingsTile(
                  icon: Icons.language_rounded,
                  title: 'settings.language'.tr(),
                  subtitle: currentLanguage,
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
                // _SettingsTile(
                //   icon: Icons.help_rounded,
                //   title: 'settings.help_center'.tr(),
                //   subtitle: 'settings.help_center_desc'.tr(),
                //   onTap: () {
                //     // Help center
                //   },
                // ),
                // const Divider(height: 1, color: Colors.black12),
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

                      const SizedBox(height: 20), // Bottom navigation uchun joy
                    ],
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

