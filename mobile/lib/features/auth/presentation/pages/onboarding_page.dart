import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_logo.dart';

/// Onboarding — ilovani BIRINCHI marta ochganda ko'rsatiladigan uch ekran.
///
/// Ikkinchi maketda onboarding YO'Q, lekin egasi uni qoldirishni so'radi.
/// Tuzilishi birinchi maketdan (o'rtada telefon, pastdan gradient, matn va
/// tugma), ranglari esa yangi brenddan: fon — splash dagidek to'q ko'k
/// (bg/inverse), tugma — sariq Accent (Design System: «muhim CTA»).
///
/// Bir marta ko'rsatiladi: [seenKey] bayrog'i SharedPreferences da saqlanadi.
/// Ilova o'chirilib qayta o'rnatilsa — yana ko'rinadi, bu kutilgan narsa.
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  /// SharedPreferences kaliti: onboarding ko'rilganmi.
  ///
  /// Nomi o'zgartirilsa — hamma odam uchun onboarding QAYTADAN chiqadi,
  /// shuning uchun uni shu yerda bir joyda saqlaymiz va boshqa fayllarda
  /// satr sifatida takrorlamaymiz.
  static const String seenKey = 'onboarding_seen';

  /// Onboarding allaqachon ko'rilganmi.
  static Future<bool> isSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(seenKey) ?? false;
  }

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _controller = PageController();
  int _index = 0;

  /// Uch qadam. Matnlar lug'atdan — kodda tirik satr yo'q.
  static const List<_OnboardingStep> _steps = [
    // Rasmlar — ikkinchi maketning o'z ekranlari (mijoz fayli, «Buyurtma
    // oqimi»): 1 — bosh ekran, 4 — texnika va tarif, 8 — texnika yo'lda.
    // Figma ularni faqat asl o'lchamda (375×812) beradi.
    _OnboardingStep(
      image: 'assets/onboarding/step1.png',
      titleKey: 'onboarding.step1_title',
      subtitleKey: 'onboarding.step1_subtitle',
    ),
    _OnboardingStep(
      image: 'assets/onboarding/step2.png',
      titleKey: 'onboarding.step2_title',
      subtitleKey: 'onboarding.step2_subtitle',
    ),
    _OnboardingStep(
      image: 'assets/onboarding/step3.png',
      titleKey: 'onboarding.step3_title',
      subtitleKey: 'onboarding.step3_subtitle',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(OnboardingPage.seenKey, true);
    if (!mounted) return;
    context.go('/language');
  }

  void _next() {
    if (_index >= _steps.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Fon to'q ko'k — status bar belgilari oq.
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppPalette.inverse,
        body: Stack(
          children: [
            // Telefon ustidagi bo'sh joyda — logotip (to'q fon varianti).
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 210,
              child: SafeArea(
                bottom: false,
                child: Center(
                  child: AppLogo(
                    kind: AppLogoKind.horizontal,
                    onDark: true,
                    height: 36,
                  ),
                ),
              ),
            ),
            // Telefon maketi. Maketda u ekranning pastki qismiga "chiqib
            // ketadi" va gradient bilan yopiladi, shuning uchun balandlik
            // ekrandan katta va pastdan kesiladi.
            Positioned.fill(
              top: 210,
              child: PageView.builder(
                controller: _controller,
                itemCount: _steps.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (context, i) => _buildMockup(_steps[i]),
              ),
            ),

            // Gradient + matn + tugma. Ular sahifa bilan birga surilmaydi:
            // maketda tugma joyida turadi, faqat matn almashadi.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 344,
              child: _buildFooter(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMockup(_OnboardingStep step) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 17),
        child: Container(
          decoration: BoxDecoration(
            color: AppPalette.page,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(56)),
            border: const Border(
              top: BorderSide(color: AppPrimitives.navy800, width: 5),
              left: BorderSide(color: AppPrimitives.navy800, width: 5),
              right: BorderSide(color: AppPrimitives.navy800, width: 5),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            step.image,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
          ),
        ),
      );

  Widget _buildFooter() => Container(
        decoration: const BoxDecoration(
          // Tepada butunlay shaffof, pastga borib to'liq fon rangi:
          // telefonning pastki qismi asta-sekin yo'qoladi.
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0x00162438),
              Color(0xD8162438),
              AppPalette.inverse,
            ],
            stops: [0.0, 0.35, 0.64],
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SizedBox(
                  width: 274,
                  child: Text(
                    _steps[_index].titleKey.tr(),
                    textAlign: TextAlign.center,
                    style: AppTypography.h1
                        .copyWith(color: AppPalette.textOnBrand),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                SizedBox(
                  width: 240,
                  child: Text(
                    _steps[_index].subtitleKey.tr(),
                    textAlign: TextAlign.center,
                    style: AppTypography.body
                        .copyWith(color: AppPalette.textOnBrand.withValues(alpha: 0.8)),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildDots(),
                const SizedBox(height: AppSpacing.lg),
                // Design System: Button Accent L — sariq, matn to'q ko'k.
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.button),
                    boxShadow: AppShadows.accent,
                  ),
                  child: SizedBox(
                    height: AppSpacing.buttonHeight,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _next,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppPalette.accent,
                        foregroundColor: AppPalette.textOnAccent,
                      ).copyWith(
                        backgroundColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.pressed)
                              ? AppPalette.accentPressed
                              : AppPalette.accent,
                        ),
                      ),
                      child: Text(
                        'onboarding.continue'.tr(),
                        style: AppTypography.buttonLarge
                            .copyWith(color: AppPalette.textOnAccent),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
      );

  /// Nuqtalar maketda chizilmagan, lekin ularsiz odam uchta ekran borligini
  /// va qaysi birida turganini bilmaydi: surish uchun hech qanday ishora
  /// qolmaydi. Shuning uchun qo'shilgan — maketning ruhiga mos, oq rangda.
  Widget _buildDots() => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(_steps.length, (i) {
          final active = i == _index;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            height: 6,
            width: active ? 20 : 6,
            decoration: BoxDecoration(
              color: active
                  ? AppPalette.accent
                  : AppPalette.textOnBrand.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
          );
        }),
      );
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.image,
    required this.titleKey,
    required this.subtitleKey,
  });

  final String image;
  final String titleKey;
  final String subtitleKey;

}
