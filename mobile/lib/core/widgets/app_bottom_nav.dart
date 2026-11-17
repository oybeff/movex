import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Pastki menyu — Figma maketidagi ko'rinishda.
///
/// Maketdan olingan o'lchovlar: oq quti, balandligi 80, yon chekka 16,
/// burchagi 12, soyasi `2 2 10 / 0.1`. Ikonka 24, yozuv 12 Regular.
/// Tanlangan bo'lim — to'ldirilgan ikonka va to'q rang, qolganlari —
/// kontur va kulrang. Yozuvning rangi hammasida bir xil, maketda shunday.
///
/// Nega alohida vidjet: menyu ikkita rolda ham bor (mijoz va texnika egasi)
/// va o'n xil ekranda ko'rinadi. Ilgari u ikki joyda nusxalangan edi, va
/// mijoznikida `Colors.green` qolib ketgandi — brend rangi almashganda u
/// o'zgarmasdi, chunki palitradan olinmagan edi.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.currentIndex,
    required this.onTap,
    required this.items,
  });

  final int currentIndex;
  final ValueChanged<int> onTap;
  final List<AppBottomNavItem> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Pastdagi chekka telefonning JEST CHIZIG'Ini hisobga oladi: qat'iy
      // qiymatda menyu Android 10+ va iPhone X+ da chiziq ustiga tushib,
      // tugmalari bosilmay qolardi.
      margin: EdgeInsets.only(
        left: AppSpacing.gutter,
        right: AppSpacing.gutter,
        bottom: AppSpacing.sm + MediaQuery.of(context).padding.bottom,
      ),
      height: AppSpacing.navHeight,
      decoration: BoxDecoration(
        color: AppPalette.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final item = items[i];
          final active = i == currentIndex;
          return Expanded(
            child: InkWell(
              onTap: () => onTap(i),
              borderRadius: BorderRadius.circular(AppRadius.card),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? item.activeIcon : item.icon,
                    size: AppSpacing.icon,
                    color: active
                        ? AppPalette.textPrimary
                        : AppPalette.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  // Mijozda beshta bo'lim bor, maketda esa to'rtta. Besh
                  // bo'limda uzun nom ("E'lonlar", "Obyavleniya") 12 px da
                  // sig'maydi va qirqilardi — shuning uchun yozuv kerak
                  // bo'lsa KICHRAYADI, qirqilmaydi.
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        maxLines: 1,
                        style: AppTypography.navLabel.copyWith(
                          color: active
                              ? AppPalette.textPrimary
                              : AppPalette.textSecondary,
                          fontWeight:
                              active ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  /// Tanlanmagan holat — kontur ikonka.
  final IconData icon;

  /// Tanlangan holat — to'ldirilgan ikonka (maketda shunday).
  final IconData activeIcon;

  final String label;
}
