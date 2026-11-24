import 'package:flutter/material.dart';

import '../../../../core/theme/app_tokens.dart';
import '../../../../core/widgets/h_icon.dart';

/// Общие куски экранов входа из второго макета (клиентский файл,
/// страница «00 Kirish»). Вынесены, чтобы телефон, код и PIN выглядели
/// одинаково, а не «примерно похоже».

/// Заголовок экрана входа: 26 Bold. В макете он крупнее H1 (24) —
/// стиль задан прямо в экранах «Kirish», не в Design System.
const TextStyle authTitleStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 26,
  fontWeight: FontWeight.w700,
  height: 1.25,
  letterSpacing: -0.3,
  color: AppPalette.textPrimary,
);

/// Подзаголовок: 15 Regular, интерлиньяж 1.4, вторичный цвет.
const TextStyle authSubtitleStyle = TextStyle(
  fontFamily: AppTypography.fontFamily,
  fontSize: 15,
  fontWeight: FontWeight.w400,
  height: 1.4,
  color: AppPalette.textSecondary,
);

/// Текст ошибки под полем: красная иконка и Caption 12.
/// Макет: «A3 · Telefon — xato», «B4 · Kod noto'g'ri».
class AuthFieldError extends StatelessWidget {
  const AuthFieldError(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Padding(
        padding: const EdgeInsets.only(left: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 1),
              child: HIcon(
                Icons.error_outline_rounded,
                size: 14,
                color: AppPalette.textDanger,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                message,
                style: AppTypography.captionS
                    .copyWith(color: AppPalette.textDanger),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Главная кнопка экранов входа — Button Primary L из Design System:
/// 52 px, радиус lg, синяя с тенью Shadow/Brand; отключённая — светло-серая
/// с серым текстом и без тени.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.loading = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.button),
        boxShadow: enabled ? AppShadows.brand : null,
      ),
      child: SizedBox(
        width: double.infinity,
        height: AppSpacing.buttonHeight,
        child: ElevatedButton(
          // Пока идёт запрос, кнопка выглядит активной (крутится индикатор),
          // но второй раз не нажимается.
          onPressed: loading ? () {} : onPressed,
          child: loading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: AppPalette.textOnBrand,
                  ),
                )
              : Text(label),
        ),
      ),
    );
  }
}
