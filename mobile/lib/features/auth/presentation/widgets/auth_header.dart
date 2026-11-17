import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/app_logo.dart';

/// Шапка экранов входа. Макет: клиентский файл, «Auth/Header» — 56 px,
/// слева логотип (горизонтальный, 28 px) или кнопка «назад», справа
/// переключатель языка UZ | RU.
///
/// Язык меняется прямо здесь: в новом макете отдельного экрана выбора
/// языка в пути входа нет («Rol va til so'ralmaydi»).
class AuthHeader extends StatelessWidget {
  const AuthHeader({super.key, this.onBack, this.showLanguage = true});

  /// Если задано — вместо логотипа стрелка «назад».
  final VoidCallback? onBack;

  final bool showLanguage;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
        child: Row(
          children: [
            if (onBack != null)
              _BackButton(onTap: onBack!)
            else
              const AppLogo(kind: AppLogoKind.horizontal, height: 28),
            const Spacer(),
            if (showLanguage) const AuthLanguageToggle(),
          ],
        ),
      ),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'auth.back'.tr(),
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: const SizedBox(
          width: AppSpacing.iconButton,
          height: AppSpacing.iconButton,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: AppPalette.iconPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Переключатель языка. Макет: «Auth/Til (UZ | RU)» — серая подложка
/// bg/page, активный сегмент белый с лёгкой тенью.
class AuthLanguageToggle extends StatelessWidget {
  const AuthLanguageToggle({super.key});

  static const _langs = ['uz', 'ru'];

  Future<void> _select(BuildContext context, String code) async {
    if (context.locale.languageCode == code) return;
    // Тот же ключ, что у экрана выбора языка и настроек: при следующем
    // запуске язык поднимется из него.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_language', code);
    if (!context.mounted) return;
    await context.setLocale(Locale(code));
  }

  @override
  Widget build(BuildContext context) {
    final current = context.locale.languageCode;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: AppPalette.page,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final code in _langs) ...[
            if (code != _langs.first) const SizedBox(width: 2),
            _segment(context, code, active: code == current),
          ],
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, String code, {required bool active}) {
    return Semantics(
      button: true,
      selected: active,
      child: GestureDetector(
        onTap: () => _select(context, code),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppPalette.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            boxShadow: active
                ? const [
                    BoxShadow(
                      color: Color(0x14162438),
                      offset: Offset(0, 1),
                      blurRadius: 3,
                    ),
                  ]
                : null,
          ),
          child: Text(
            code.toUpperCase(),
            style: TextStyle(
              fontFamily: AppTypography.fontFamily,
              fontSize: 13,
              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
              color: active ? AppPalette.textPrimary : AppPalette.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
