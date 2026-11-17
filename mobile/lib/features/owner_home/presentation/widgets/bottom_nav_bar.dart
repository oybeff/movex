import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:movex_go/core/widgets/app_bottom_nav.dart';

/// Texnika egasining pastki menyusi.
///
/// Ko'rinishi [AppBottomNav] da — u mijozniki bilan BITTA. Ilgari bu yerda
/// menyuning to'liq nusxasi turardi, va ikkala nusxada ham `Colors.green`
/// qotirilgan edi: brend rangi almashganda menyu yashil bo'lib qolgandi,
/// chunki rang palitradan olinmagan.
///
/// Bu yerda faqat bo'limlar ro'yxati qoladi — ular rollarda har xil.
class OwnerBottomNavBar extends StatelessWidget {
  final int currentIndex;
  final Function(int) onTap;

  const OwnerBottomNavBar({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppBottomNav(
      currentIndex: currentIndex,
      onTap: onTap,
      items: [
        AppBottomNavItem(
          icon: Icons.dashboard_outlined,
          activeIcon: Icons.dashboard_rounded,
          label: 'owner.dashboard'.tr(),
        ),
        AppBottomNavItem(
          icon: Icons.build_outlined,
          activeIcon: Icons.build_rounded,
          label: 'owner.my_equipment'.tr(),
        ),
        AppBottomNavItem(
          icon: Icons.campaign_outlined,
          activeIcon: Icons.campaign_rounded,
          label: 'owner.listings'.tr(),
        ),
        AppBottomNavItem(
          icon: Icons.receipt_long_outlined,
          activeIcon: Icons.receipt_long_rounded,
          label: 'owner.orders'.tr(),
        ),
        AppBottomNavItem(
          icon: Icons.chat_bubble_outline_rounded,
          activeIcon: Icons.chat_rounded,
          label: 'owner.chat'.tr(),
        ),
      ],
    );
  }
}
