import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/pin_service.dart';
import '../theme/app_tokens.dart';
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
  const DeleteAccountButton({super.key, this.large = false});

  /// Кнопка Ghost L (52) из макета Pr2 — у клиента; маленькая — у владельца.
  final bool large;

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

    final confirmed = large ? await _sheet(context) : await showDialog<bool>(
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

  /// U7 · Akkauntni o'chirish (клиент). Пункты — правда о том, что
  /// делает сервер: заказы и платежи остаются обезличенными, поэтому
  /// «история удалится» тут не пишем.
  Future<bool?> _sheet(BuildContext context) => showModalBottomSheet<bool>(
        context: context,
        backgroundColor: AppPalette.surface,
        barrierColor: const Color(0x730B1220),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.gutter, 8, AppSpacing.gutter, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: const Color(0xFFD3D8DF), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(color: AppPalette.dangerSubtle, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: SvgPicture.asset('assets/icons/logout.svg', width: 24, height: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text('taxi.delete_title'.tr(), style: AppTypography.h3)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: BoxDecoration(color: AppPalette.page, borderRadius: BorderRadius.circular(AppRadius.lg)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final k in const ['personal', 'addresses', 'active', 'final'])
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                margin: const EdgeInsets.only(top: 7),
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(color: AppPalette.textDanger, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 8),
                              Expanded(child: Text('taxi.delete_$k'.tr(), style: AppTypography.bodyM)),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: TextButton.styleFrom(
                      backgroundColor: AppPalette.brandSubtle,
                      foregroundColor: AppPalette.textDanger,
                      textStyle: AppTypography.buttonLarge,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
                    ),
                    child: Text('taxi.delete_yes'.tr()),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: AppSpacing.buttonHeight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    style: TextButton.styleFrom(
                      foregroundColor: AppPalette.textBrand,
                      textStyle: AppTypography.buttonLarge,
                    ),
                    child: Text('taxi.cancel'.tr()),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (large) {
      return SizedBox(
        height: AppSpacing.buttonHeight,
        child: TextButton(
          onPressed: () => _run(context),
          style: TextButton.styleFrom(
            foregroundColor: AppPalette.textDanger,
            textStyle: AppTypography.buttonLarge,
          ),
          child: Text('taxi.delete_account'.tr()),
        ),
      );
    }
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
