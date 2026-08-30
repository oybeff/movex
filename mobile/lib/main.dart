import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:app_links/app_links.dart';
import 'package:toastification/toastification.dart';
import 'package:movex_go/features/owner_home/presentation/pages/franchise_manage_page.dart';
import 'package:movex_go/features/settings/presentation/pages/settings_page.dart';
import 'package:movex_go/features/notifications/presentation/pages/notifications_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/payout_page.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movex_go/features/auth/presentation/pages/splash_screen_page.dart';
import 'package:movex_go/features/auth/presentation/pages/language_select_page.dart';
import 'package:movex_go/features/auth/presentation/pages/role_select_page.dart';
import 'package:movex_go/features/auth/presentation/pages/register_page.dart';
import 'package:movex_go/features/auth/presentation/pages/register_complete_page.dart';
import 'package:movex_go/features/auth/presentation/pages/otp_verification_page.dart';
import 'package:movex_go/features/auth/presentation/pages/login_page.dart';
import 'package:movex_go/features/client_home/presentation/client_home_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/owner_home_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/add_equipment_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/edit_equipment_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/equipment_detail_page.dart';
import 'package:movex_go/features/owner_home/presentation/pages/order_statistics_page.dart';
import 'package:movex_go/features/client_home/presentation/pages/rent_equipment_page.dart';
import 'package:movex_go/features/balance/presentation/pages/balance_topup_page.dart';
import 'package:movex_go/core/models/equipment_model.dart';
import 'dart:async';

// Global GoRouter instance
late final GoRouter appRouter;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  final prefs = await SharedPreferences.getInstance();
  final savedLanguage = prefs.getString('selected_language') ?? 'uz';

  // Global router'ni initsializatsiya qilamiz
  appRouter = GoRouter(
    initialLocation: '/splash',
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreenPage(),
      ),
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguageSelectPage(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const RoleSelectPage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final role = state.extra as String? ?? 'client';
          return RegisterPage(role: role);
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      GoRoute(
        path: '/clientHome',
        builder: (context, state) => const ClientHomePage(),
      ),
      GoRoute(
        path: '/ownerHome',
        builder: (context, state) => const OwnerHomePage(),
      ),
      GoRoute(
        path: '/order-statistics',
        builder: (context, state) => const OrderStatisticsPage(),
      ),
      GoRoute(
        path: '/franchise',
        builder: (context, state) => const FranchiseManagePage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/notifications',
        builder: (context, state) => const NotificationsPage(),
      ),
      GoRoute(
        path: '/payout',
        builder: (context, state) => const PayoutPage(),
      ),
      GoRoute(
        path: '/add-equipment',
        builder: (context, state) => const AddEquipmentPage(),
      ),
      GoRoute(
        path: '/edit-equipment/:id',
        builder: (context, state) {
          final id = int.parse(state.pathParameters['id']!);
          return EditEquipmentPage(equipmentId: id);
        },
      ),
      GoRoute(
        path: '/equipment-detail',
        builder: (context, state) {
          final equipment = state.extra as EquipmentModel;
          return EquipmentDetailPage(equipment: equipment);
        },
      ),
      GoRoute(
        path: '/rent-equipment',
        builder: (context, state) {
          final equipment = state.extra as EquipmentModel;
          return RentEquipmentPage(equipment: equipment);
        },
      ),
      GoRoute(
        path: '/otp-verification',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return OTPVerificationPage(
            phoneNumber: extra['phoneNumber'] as String,
            isRegistration: extra['isRegistration'] as bool? ?? false,
            role: extra['role'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/register-complete',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>;
          return RegisterCompletePage(
            phone: extra['phone'] as String,
            role: extra['role'] as String? ?? 'client',
          );
        },
      ),
      GoRoute(
        path: '/balance-topup',
        builder: (context, state) {
          final requiredAmount = state.extra as double?;
          return BalanceTopUpPage(requiredAmount: requiredAmount);
        },
      ),
    ],
  );

  runApp(
    EasyLocalization(
      supportedLocales: const [Locale('uz'), Locale('ru')],
      path: 'assets/translations',
      fallbackLocale: const Locale('uz'),
      startLocale: Locale(savedLanguage),
      child: MyApp(router: appRouter),
    ),
  );
}

class MyApp extends StatefulWidget {
  final GoRouter router;
  const MyApp({super.key, required this.router});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initDeepLinks() async {
    _appLinks = AppLinks();

    // Initial link'ni tekshirish (ilova yopiq holatdan ochilganda)
    try {
      final uri = await _appLinks.getInitialLink();
      if (uri != null) {
        _handleDeepLink(uri);
      }
    } catch (e) {
      debugPrint('Deep link error: $e');
    }

    // Link stream'ni tinglash (ilova ochiq holatda)
    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleDeepLink(uri);
      },
      onError: (err) {
        debugPrint('Deep link stream error: $err');
      },
    );
  }

  void _handleDeepLink(Uri uri) {
    debugPrint('Deep link received: $uri');

    // movexgo://payment/success
    if (uri.scheme == 'movexgo' && uri.host == 'payment') {
      if (uri.path == '/success' || uri.pathSegments.contains('success')) {
        // To'lov muvaffaqiyatli - balance topup page'ga qaytish
        widget.router.go('/balance-topup');

        // Toast ko'rsatish
        Future.delayed(const Duration(milliseconds: 500), () {
          if (!mounted) return;
          final context = widget.router.routerDelegate.navigatorKey.currentContext;
          if (context != null) {
            toastification.show(
              context: context,
              type: ToastificationType.success,
              style: ToastificationStyle.flatColored,
              title: Text('messages.payment_processing'.tr()),
              autoCloseDuration: const Duration(seconds: 3),
              alignment: Alignment.topCenter,
            );
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ToastificationWrapper(
      child: MaterialApp.router(
        debugShowCheckedModeBanner: false,
        title: 'Movex Go',
        theme: ThemeData(
          primarySwatch: Colors.green,
          useMaterial3: true,
        ),
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        routerConfig: widget.router,
      ),
    );
  }
}
