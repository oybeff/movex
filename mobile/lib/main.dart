import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movex_go/core/theme/app_theme.dart';
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
import 'package:movex_go/features/auth/presentation/pages/onboarding_page.dart';
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
import 'package:movex_go/features/balance/presentation/pages/balance_topup_page.dart';
import 'package:movex_go/core/models/equipment_model.dart';
import 'dart:async';
import 'package:movex_go/core/app_flavor.dart';
import 'package:movex_go/features/driver/presentation/driver_home_page.dart';

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
      // Birinchi ochilishda ko'rsatiladigan uch ekran. Splash undan
      // oldin turadi va bayroqqa qarab shu yerga yoki to'g'ri /language ga
      // yuboradi.
      GoRoute(
        path: '/onboarding',
        builder: (context, state) => const OnboardingPage(),
      ),
      GoRoute(
        path: '/language',
        builder: (context, state) => const LanguageSelectPage(),
      ),
      GoRoute(
        path: '/',
        // В приложении водителя — 'owner', в клиентском приложении — 'client'.
        // Никакого экрана выбора роли («Rolingizni tanlang»): клиентское
        // приложение строго для клиентов («Mijoz»).
        builder: (context, state) =>
            AppFlavor.isDriver ? const LoginPage(role: 'owner') : const LoginPage(role: 'client'),
      ),
      GoRoute(
        path: '/driverHome',
        builder: (context, state) => const DriverHomePage(),
      ),
      GoRoute(
        path: '/driver-wrong-role',
        builder: (context, state) => const DriverWrongRolePage(),
      ),
      GoRoute(
        path: '/register',
        builder: (context, state) {
          final role = state.extra as String? ?? (AppFlavor.isDriver ? 'owner' : 'client');
          return RegisterPage(role: role);
        },
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginPage(
          role: state.extra as String? ?? (AppFlavor.isDriver ? 'owner' : 'client'),
        ),
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
          final navContext = widget.router.routerDelegate.navigatorKey.currentContext;
          if (navContext != null && navContext.mounted) {
            toastification.show(
              context: navContext,
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
        title: AppFlavor.isDriver ? 'MoveX GO Driver' : 'Movex Go',
        // Тема из токенов макета (core/theme/app_tokens.dart). До 12.11.2026
        // здесь стоял ThemeData(primarySwatch: green), и AppTheme не
        // применялся вовсе: кнопки и поля рисовались цветами Material.
        theme: AppTheme.lightTheme,
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        routerConfig: widget.router,
        // Системные панели по умолчанию — светлые, как большинство экранов.
        // Экран со своим AnnotatedRegion (заставка, онбординг) перекрывает
        // это значение. Без него экраны без своего региона (U3, U2, ПИН)
        // наследовали тёмную полосу навигации и белые значки статус-бара
        // на белом фоне — от заставки.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarBrightness: Brightness.light,
            statusBarIconBrightness: Brightness.dark,
            systemNavigationBarColor: Color(0xFFFFFFFF), // AppPalette.surface
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    );
  }
}
