import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';

/// Цвета приложения.
///
/// С ноября 2026 реальные значения живут в [AppPalette]
/// (`core/theme/app_tokens.dart`) и сняты с макета Figma. Здесь остались
/// ИМЕНА, на которые завязан старый код: одних только `primaryGreen` в
/// проекте больше 450 штук. Имена указывают на новые значения, поэтому
/// приложение стало оранжевым целиком, без правки каждого экрана.
///
/// В НОВОМ коде используй [AppPalette], а не этот класс. Имена отсюда
/// вычищаются по мере переделки экранов по макету.
///
/// Аннотации `@Deprecated` здесь СОЗНАТЕЛЬНО не стоят: на них завязано
/// больше 700 мест, и `flutter analyze` выдал бы столько же предупреждений,
/// похоронив настоящие. Ставить их можно только вместе с вычисткой
/// последних обращений.
class AppColors {
  // Основные цвета.
  //
  // Названия врут про цвет — бренд стал оранжевым, зелёного в макете нет.
  // Это временная плата за то, чтобы не править 450 мест вслепую.
  static const Color primaryGreen = AppPalette.primary;
  static const Color secondaryGreen = AppPalette.primary;
  static const Color accentGreen = AppPalette.primary;

  // Фон, текст
  static const Color background = AppPalette.surface;
  static const Color white = AppPalette.surface;
  static const Color black = AppPalette.textPrimary;
  static const Color grey = AppPalette.textSecondary;
  static const Color lightGrey = AppPalette.surfaceMuted;

  // Ошибки
  static const Color error = AppPalette.error;
}
