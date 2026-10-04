import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/services/pin_service.dart';
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

    final prefs = await SharedPreferences.getInstance();

    // Til tanlanganligini tekshirish
    final languageSelected = prefs.getBool('language_selected') ?? false;
    if (!languageSelected) {
      if (mounted) context.go('/language');
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
      if (role == 'client') {
        context.go('/clientHome');
      } else if (role == 'owner') {
        context.go('/ownerHome');
      } else {
        // Noma'lum rol (masalan 'admin' — u faqat panelda ishlaydi):
        // ilgari bu yerda hech narsa bo'lmasdi va ekran sakrash ekranida
        // abadiy qotib qolardi.
        context.go('/');
      }
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
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: Brightness.light,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Color(0xFFFFFFFF),
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: AnimatedBuilder(
            animation: _animationController,
            builder: (context, child) {
              return Opacity(
                opacity: _fadeAnimation.value,
                child: Transform.scale(
                  scale: _scaleAnimation.value,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Logo
                      Image.asset(
                        'assets/logo-png.png',
                        width: 120,
                        height: 120,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 24),
                      // Loading indicator
                      const SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 3,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

