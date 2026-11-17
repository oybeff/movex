import 'package:flutter/material.dart';

import 'app_tokens.dart';
import 'field_border.dart';

/// Тема приложения, собранная из токенов макета ([AppPalette], [AppTypography]
/// и соседей в `app_tokens.dart`).
///
/// Здесь НЕ должно быть ни одного литерала цвета или размера — только ссылки
/// на токены. Если значения нет в токенах, значит его нет и в макете: сначала
/// заводится токен, потом используется тут.
class AppTheme {
  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    fontFamily: AppTypography.fontFamily,
    primaryColor: AppPalette.primary,

    // Макет белый. Прежний серый фон (#F9F9F9) делал карточки на нём
    // неразличимыми — в макете разделение даёт не фон, а заливка карточки.
    scaffoldBackgroundColor: AppPalette.surface,

    colorScheme: ColorScheme.fromSeed(
      seedColor: AppPalette.brand,
      primary: AppPalette.brand,
      onPrimary: AppPalette.textOnBrand,
      secondary: AppPalette.accent,
      onSecondary: AppPalette.textOnAccent,
      surface: AppPalette.surface,
      onSurface: AppPalette.textPrimary,
      error: AppPalette.textDanger,
    ),

    // В макете шапка белая с тёмным текстом, а не залита брендовым цветом.
    appBarTheme: const AppBarTheme(
      backgroundColor: AppPalette.surface,
      foregroundColor: AppPalette.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypography.h2,
    ),

    textTheme: const TextTheme(
      headlineLarge: AppTypography.display,
      headlineMedium: AppTypography.h1,
      titleLarge: AppTypography.h2,
      titleMedium: AppTypography.bodyMedium,
      bodyLarge: AppTypography.body,
      titleSmall: AppTypography.h3,
      bodyMedium: AppTypography.bodyM,
      bodySmall: AppTypography.captionS,
      labelLarge: AppTypography.buttonLarge,
      labelMedium: AppTypography.button,
      labelSmall: AppTypography.navLabel,
    ),

    // Макет: компонент Input — серый фон без рамки, высота 56, радиус lg.
    // Фокус — белый фон и синяя рамка 1.5, ошибка — розовый фон и красная.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // Фокус — белый фон (макет: Input/Focus), иначе серый bg/page.
      // Ошибка — розовый bg/danger-subtle (макет: Input/Error).
      fillColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.error)
            ? AppPalette.dangerSubtle
            : states.contains(WidgetState.focused)
                ? AppPalette.surface
                : AppPalette.page,
      ),
      hoverColor: Colors.transparent,
      constraints: const BoxConstraints(minHeight: AppSpacing.fieldHeight),
      hintStyle: AppTypography.hint,
      labelStyle: AppTypography.hint,
      // Flutter уменьшает всплывшую подпись до 0.75 — 16 даёт 12 из макета.
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => AppTypography.hint.copyWith(
          color: states.contains(WidgetState.error)
              ? AppPalette.textDanger
              : states.contains(WidgetState.focused)
                  ? AppPalette.textBrand
                  : AppPalette.textSecondary,
        ),
      ),
      errorStyle: AppTypography.captionS.copyWith(color: AppPalette.textDanger),
      contentPadding: const EdgeInsets.symmetric(
        vertical: AppSpacing.lg,
        horizontal: AppSpacing.lg,
      ),
      border: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      enabledBorder: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      disabledBorder: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: BorderSide.none,
      ),
      focusedBorder: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderFocus, width: 1.5),
      ),
      errorBorder: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderDanger, width: 1.5),
      ),
      focusedErrorBorder: FieldBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        borderSide: const BorderSide(color: AppPalette.borderDanger, width: 1.5),
      ),
    ),

    // Макет: Button Primary L — 52, радиус lg, надпись 16 Semibold.
    // Отключённая — светло-серая с серым текстом, а не серая с белым.
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        foregroundColor: AppPalette.textOnBrand,
        backgroundColor: AppPalette.brand,
        disabledBackgroundColor: AppPalette.disabledBg,
        disabledForegroundColor: AppPalette.textDisabled,
        elevation: 0,
        minimumSize: const Size(double.infinity, AppSpacing.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppTypography.buttonLarge,
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return AppPalette.disabledBg;
          if (states.contains(WidgetState.pressed)) return AppPalette.brandPressed;
          return AppPalette.brand;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    // Макет: Button Outline — белая, рамка border/default, тёмный текст.
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppPalette.textPrimary,
        backgroundColor: AppPalette.surface,
        disabledForegroundColor: AppPalette.textDisabled,
        minimumSize: const Size(double.infinity, AppSpacing.buttonHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
        side: const BorderSide(color: AppPalette.borderDefault),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.button),
        ),
        textStyle: AppTypography.buttonLarge,
      ),
    ),

    // Макет: Button Ghost — текст бренда без фона.
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppPalette.textBrand,
        textStyle: AppTypography.button,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
    ),

    // В новом макете карточка белая с Shadow/Card на сером bg/page. Но фон
    // у ещё не переделанных экранов белый, и белая карточка на нём исчезла
    // бы. Поэтому по умолчанию серая; переделанные экраны ставят белую сами.
    cardTheme: CardThemeData(
      color: AppPalette.page,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),

    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppPalette.surface,
      selectedItemColor: AppPalette.brand,
      unselectedItemColor: AppPalette.textSecondary,
      selectedLabelStyle: AppTypography.navLabel,
      unselectedLabelStyle: AppTypography.navLabel,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    dividerTheme: const DividerThemeData(
      color: AppPalette.borderDefault,
      thickness: 1,
      space: 1,
    ),
  );
}
