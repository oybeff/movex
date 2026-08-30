import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:movex_go/core/constants/app_colors.dart';

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
    return Container(
      margin: const EdgeInsets.only(left: 12, right: 12, bottom: 6),
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BottomNavigationBar(
          backgroundColor: Colors.white,
          selectedItemColor: Colors.green,
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold),
          selectedIconTheme: const IconThemeData(size: 28),
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          type: BottomNavigationBarType.fixed,
          currentIndex: currentIndex,
          onTap: onTap,
          items: [
            BottomNavigationBarItem(
              icon: const Icon(Icons.dashboard_rounded),
              label: 'owner.dashboard'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.build_rounded),
              label: 'owner.my_equipment'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.receipt_long_rounded),
              label: 'owner.orders'.tr(),
            ),
            BottomNavigationBarItem(
              icon: const Icon(Icons.chat_rounded),
              label: 'owner.chat'.tr(),
            ),
          ],
        ),
      ),
    );
  }
}
