import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pin_service.dart';
import '../services/user_service.dart';

/// "Hisobni o'chirish" (Google Play talabi).
///
/// Bitta vidjet ikkala profil uchun — mijozniki (client_profile_page) va
/// egasiniki (settings_page). Ilgari tugma faqat egada bor edi, va Play
/// tekshiruvchisi mijoz hisobi bilan kirib, o'chirishni topa olmasdi.
///
/// Avval serverdan "mumkinmi" so'raladi: pul yoki tugallanmagan bitim
/// bo'lsa tasdiqlash oynasi ochilmaydi, sababi ko'rsatiladi. Qoidani server
/// hal qiladi — ilova faqat natijani ko'rsatadi.
class DeleteAccountButton extends StatelessWidget {
  const DeleteAccountButton({super.key});

  Future<void> _run(BuildContext context) async {
    final service = UserService();
    final messenger = ScaffoldMessenger.of(context);
    void snack(String text) => messenger.showSnackBar(SnackBar(content: Text(text)));

    final ({bool canDelete, List<String> reasons}) check;
    try {
      check = await service.accountDeletionCheck();
    } catch (_) {
      snack('settings.delete_account_error'.tr());
      return;
    }
    if (!context.mounted) return;

    if (!check.canDelete) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          backgroundColor: Colors.white,
          title: Text('settings.delete_account_blocked_title'.tr()),
          content: Text(check.reasons.join('\n\n')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('settings.confirm'.tr()),
            ),
          ],
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        title: Text('settings.delete_account_confirm_title'.tr()),
        content: Text('settings.delete_account_confirm_message'.tr()),
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
            child: Text('settings.delete_account'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await service.deleteAccount();
    } catch (e) {
      snack(e.toString().replaceFirst('Exception: ', ''));
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('role');
    await PinService.resetOnLogout();
    snack('settings.delete_account_done'.tr());
    if (context.mounted) context.go('/');
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: () => _run(context),
        child: Text(
          'settings.delete_account'.tr(),
          style: TextStyle(fontSize: 14, color: Colors.red.shade400),
        ),
      ),
    );
  }
}
