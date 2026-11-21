import 'package:movex_go/core/app_flavor.dart';
import '../../../taxi/presentation/pages/app_status_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_loader.dart';
import '../../../../core/widgets/app_logo.dart';

import '../../../../core/services/pin_service.dart';
import 'onboarding_page.dart';
import 'pin_page.dart';

class SplashScreenPage extends StatefulWidget {
  const SplashScreenPage({super.key});

  @override
  State<SplashScreenPage> createState() => _SplashScreenPageState();
}

class _SplashScreenPageState extends State<SplashScreenPage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();

    // Animation controller
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // Fade animation
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeIn),
      ),
    );

    // Scale animation
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOutBack),
      ),
    );

    // Start animation
    _animationController.forward();

    // Navigate after 2 seconds
    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;

    // U2/U3: majburiy yangilanish va texnik ishlar — hammadan oldin
    if (!await passAppStatus(context)) return;
    if (!mounted) return;

    final prefs = await SharedPreferences.getInstance();

    // Til tanlanganligini tekshirish
    final languageSelected = prefs.getBool('language_selected') ?? false;
    if (!languageSelected) {
      // Ilova BIRINCHI marta ochilgan bo'lsa — avval onboarding, keyin til.
      // Tekshiruv aynan shu yerda: til tanlangandan keyin onboarding
      // ko'rsatish kech, odam allaqachon ichkarida.
      final seen = prefs.getBool(OnboardingPage.seenKey) ?? false;
      // Онбординг — клиентский («выберите технику»), водителю он не про него.
      if (mounted) context.go(seen || AppFlavor.isDriver ? '/language' : '/onboarding');
      return;
    }

    final token = prefs.getString('token');
    final role = prefs.getString('role');

    if (token != null && role != null) {
      // Kirish saqlanadi va qaytadan so'ralmaydi, shuning uchun telefonni
      // PIN kod himoya qiladi — va u MAJBURIY.
      //
      // PIN qo'yilmagan holat baribir bo'ladi: ilgari o'rnatish taklif edi
      // va undan voz kechish mumkin edi, ya'ni yangilanishdan keyin kirgan
      // odamda kod yo'q. Shuning uchun bu yerda ichkariga qo'yib
      // yubormaymiz, balki o'rnatishni so'raymiz.
      if (!mounted) return;
      if (await PinService.hasPin()) {
        if (!mounted) return;
        final unlocked = await Navigator.of(context).push<bool>(
          MaterialPageRoute(
            builder: (_) => const PinPage(mode: PinMode.unlock),
            fullscreenDialog: true,
          ),
        );
        if (unlocked != true) return;
      } else {
        if (!mounted) return;
        await requirePinSetup(context);
        if (!mounted) return;
      }

      if (!mounted) return;
      // Noma'lum rol (masalan 'admin' — u faqat panelda ishlaydi) '/' ga
      // ketadi: ilgari bu yerda hech narsa bo'lmasdi va ekran sakrash
      // ekranida abadiy qotib qolardi.
      context.go(AppFlavor.homeFor(role));
    } else {
      if (mounted) context.go('/');
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Fon to'q ko'k — status bar belgilari OQ.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.dark,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: AppPalette.inverse,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      child: Scaffold(
        // Maket «S0 · Splash»: fon bg/inverse, markazda logotip
        // (belgi 88×114, yozuv 212×30, «POWER IN MOTION») va yuklanish halqasi.
        backgroundColor: AppPalette.inverse,
        body: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) => Opacity(
              opacity: _fadeAnimation.value,
              child: Transform.scale(
                scale: _scaleAnimation.value,
                child: child,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Semantics(
                  label: 'MoveX GO',
                  image: true,
                  child: Column(
                    children: [
                      SvgPicture.asset(
                        AppLogo.markAsset,
                        width: 88,
                        height: 114.4,
                      ),
                      const SizedBox(height: 20),
                      SvgPicture.asset(
                        'assets/brand/wordmark_on_dark.svg',
                        width: 212,
                        height: 30,
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'POWER IN MOTION',
                        style: TextStyle(
                          fontFamily: AppTypography.fontFamily,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 2.88,
                          color: Color(0xD9F6C849),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
                const AppLoader(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
