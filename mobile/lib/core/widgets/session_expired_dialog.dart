import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_tokens.dart';

/// U1 · Sessiya muddati tugadi. [blockedReason] — аккаунт заблокирован
/// администратором: то же окно, но с причиной от сервера.
Future<void> showSessionExpiredDialog(BuildContext context, {String? blockedReason}) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: const Color(0x730B1220),
      builder: (ctx) => Dialog(
        backgroundColor: AppPalette.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.xl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: const BoxDecoration(color: AppPalette.brandSubtle, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: SvgPicture.asset('assets/icons/lock.svg', width: 28, height: 28),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                blockedReason == null ? 'taxi.session_title'.tr() : 'taxi.blocked_title'.tr(),
                textAlign: TextAlign.center,
                style: AppTypography.h3,
              ),
              const SizedBox(height: 10),
              Text(
                blockedReason ?? 'taxi.session_body'.tr(),
                textAlign: TextAlign.center,
                style: AppTypography.subtitle,
              ),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('taxi.login_again'.tr())),
            ],
          ),
        ),
      ),
    );
