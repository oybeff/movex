import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../constants/app_colors.dart';
import '../services/notification_service.dart';

/// Sarlavhadagi qo'ng'iroq — o'qilmagan xabarnomalar soni bilan.
///
/// Sonni o'zi yuklaydi va xabarnomalar ekranidan qaytgach yangilaydi.
/// Xato bo'lsa hech narsa ko'rsatmaydi: sarlavhadagi belgi tufayli ekran
/// buzilmasligi kerak.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final NotificationService _service = NotificationService();
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final count = await _service.getUnreadCount();
      if (mounted) setState(() => _unread = count);
    } catch (_) {
      // Jim qolamiz — soni ko'rsatilmaydi, xolos
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'notifications.title'.tr(),
      onPressed: () async {
        await context.push('/notifications');
        _refresh();
      },
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_none),
          if (_unread > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                constraints: const BoxConstraints(minWidth: 17),
                decoration: BoxDecoration(
                  color: AppColors.error,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  _unread > 99 ? '99+' : '$_unread',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: AppColors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
