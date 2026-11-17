/// Дизайн-токены MoveX GO — единственный источник правды по виду приложения.
///
/// Значения сняты с файла Figma **«MoveX GO — Design System»**
/// (`vSKu09oNTzZ0Q1iB3st3yh`, страница Foundations), 12 ноября 2026.
/// Это второй макет: первый (оранжевый, файл Movex-Go-APP) заменён целиком.
/// Рядом с токеном — имя переменной или стиля из макета, чтобы было видно,
/// что менять, когда дизайнер пришлёт правку.
///
/// Правило: НИКАКИХ Color(0x...) и fontSize: прямо в экранах. Всё берётся
/// отсюда. Иначе смена бренда снова превращается в правку всех экранов
/// руками — так было и с зелёной темой, и с оранжевой.
///
/// Имена вроде [AppPalette.primary] или [AppTypography.subtitle] остались от
/// первого макета: на них завязан уже написанный код. Каждое указывает на
/// ближайший по смыслу токен нового макета; новые экраны пусть берут
/// токены с именами макета ([AppPalette.brand], [AppTypography.bodyM] и т.д.).
library;

import 'package:flutter/material.dart';

/// Примитивы палитры. Макет: «Ranglar — Primitives» (палитра hemu.uz).
///
/// В экранах их НЕ использовать — только семантические токены
/// [AppPalette]. Примитивы нужны, чтобы семантика ссылалась на одно место.
abstract final class AppPrimitives {
  static const Color blue50 = Color(0xFFEAF2FB);
  static const Color blue100 = Color(0xFFD6E5F7);
  static const Color blue400 = Color(0xFF4A99E9);
  static const Color blue500 = Color(0xFF316DC8);
  static const Color blue600 = Color(0xFF2A5DAB);

  static const Color yellow100 = Color(0xFFFDF3D6);
  static const Color yellow400 = Color(0xFFF6C849);
  static const Color yellow500 = Color(0xFFE9B52E);

  static const Color navy800 = Color(0xFF193250);
  static const Color navy900 = Color(0xFF162438);

  static const Color gray0 = Color(0xFFFFFFFF);
  static const Color gray100 = Color(0xFFF1F3F7);
  static const Color gray200 = Color(0xFFE5E9EE);
  static const Color gray400 = Color(0xFF8E97A2);
  static const Color gray500 = Color(0xFF7D8793);

  static const Color green50 = Color(0xFFE8F4EF);
  static const Color green500 = Color(0xFF4CA194);

  static const Color red50 = Color(0xFFFDECEC);
  static const Color red500 = Color(0xFFE5484D);
}

/// Семантические цвета. Макет: «Ranglar — Semantik tokenlar» — «в дизайне
/// используйте только эти токены».
abstract final class AppPalette {
  // ── Фон ────────────────────────────────────────────────────────────────
  /// bg/page. Фон страницы, заливка полей ввода.
  static const Color page = AppPrimitives.gray100;

  /// bg/surface. Карточки, шапка, нижнее меню.
  static const Color surface = AppPrimitives.gray0;

  /// bg/brand. Главная кнопка, активные элементы.
  static const Color brand = AppPrimitives.blue500;

  /// bg/brand-pressed.
  static const Color brandPressed = AppPrimitives.blue600;

  /// bg/brand-subtle. Вторичная кнопка, нажатая «ghost».
  static const Color brandSubtle = AppPrimitives.blue50;

  /// Нажатая вторичная кнопка. В макете это примитив blue/100 напрямую,
  /// семантического токена у него нет.
  static const Color brandSubtlePressed = AppPrimitives.blue100;

  /// bg/accent. Жёлтая кнопка важного действия.
  static const Color accent = AppPrimitives.yellow400;

  /// bg/accent-pressed.
  static const Color accentPressed = AppPrimitives.yellow500;

  /// Светло-жёлтая подложка. Примитив yellow/100.
  static const Color accentSubtle = AppPrimitives.yellow100;

  /// bg/disabled. Фон отключённой кнопки и поля.
  static const Color disabledBg = AppPrimitives.gray100;

  /// bg/success-subtle.
  static const Color successSubtle = AppPrimitives.green50;

  /// bg/danger-subtle. Фон поля с ошибкой.
  static const Color dangerSubtle = AppPrimitives.red50;

  /// bg/inverse. Тёмные плашки.
  static const Color inverse = AppPrimitives.navy900;

  // ── Текст ──────────────────────────────────────────────────────────────
  /// text/primary.
  static const Color textPrimary = AppPrimitives.navy900;

  /// text/secondary.
  static const Color textSecondary = AppPrimitives.gray500;

  /// text/placeholder.
  static const Color textPlaceholder = AppPrimitives.gray400;

  /// text/brand.
  static const Color textBrand = AppPrimitives.blue500;

  /// text/on-brand.
  static const Color textOnBrand = AppPrimitives.gray0;

  /// text/on-accent. На жёлтом текст тёмный, не белый.
  static const Color textOnAccent = AppPrimitives.navy900;

  /// text/disabled.
  static const Color textDisabled = AppPrimitives.gray400;

  /// text/success.
  static const Color textSuccess = AppPrimitives.green500;

  /// text/danger.
  static const Color textDanger = AppPrimitives.red500;

  // ── Рамки ──────────────────────────────────────────────────────────────
  /// border/default.
  static const Color borderDefault = AppPrimitives.gray200;

  /// border/focus.
  static const Color borderFocus = AppPrimitives.blue500;

  /// border/danger.
  static const Color borderDanger = AppPrimitives.red500;

  /// border/strong. Рамка нажатой «outline»-кнопки.
  static const Color borderStrong = AppPrimitives.gray400;

  // ── Иконки ─────────────────────────────────────────────────────────────
  static const Color iconPrimary = AppPrimitives.navy900;
  static const Color iconSecondary = AppPrimitives.gray500;
  static const Color iconBrand = AppPrimitives.blue500;

  /// icon/verified. Галочка «проверено».
  static const Color iconVerified = AppPrimitives.blue400;
  static const Color iconOnBrand = AppPrimitives.gray0;
  static const Color iconSuccess = AppPrimitives.green500;

  // ── Старые имена (первый макет) ────────────────────────────────────────
  // Указывают на ближайший смысл в новом макете. Новый код их не берёт.

  /// Фирменный цвет. Был оранжевым, стал синим.
  static const Color primary = brand;

  /// Был «Dark 80». Ближайший — navy/800.
  static const Color dark80 = AppPrimitives.navy800;

  /// Неактивный текст и подсказки → text/placeholder.
  static const Color textMuted = textPlaceholder;

  /// Отключённое. В новом макете отключённая кнопка — светло-серая с серым
  /// текстом, а не серая с белым; см. [disabledBg] и [textDisabled].
  /// Здесь цвет, который годится и для иконки-заглушки.
  static const Color disabled = textDisabled;

  /// Жёлтый → bg/accent.
  static const Color yellow = accent;

  /// Рамка поля → border/default.
  static const Color border = borderDefault;

  /// Серая заливка полей и карточек → bg/page.
  static const Color surfaceMuted = page;

  /// Вторая серая заливка. В новом макете серый один.
  static const Color surfaceAlt = page;

  /// Ошибка → text/danger.
  static const Color error = textDanger;

  /// «Свободно» → text/success.
  static const Color success = textSuccess;

  /// «Занято». Отдельного токена в макете нет — danger.
  static const Color busy = textDanger;
}

/// Скругления. Макет: «Spacing va Radius» — «кнопка/поле — md(12),
/// карточка — lg(16), chip — sm(8)/full». На деле у кнопки L и у поля
/// 56px в компонентах стоит lg(16), md(12) — у кнопок M и S.
abstract final class AppRadius {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double full = 999;

  // Старые имена.

  /// Карточки → lg.
  static const double card = lg;

  /// Главная (большая) кнопка → lg, как у Button L.
  static const double button = lg;

  /// Верхние углы нижней шторки → xl. Сверить с «Pastki panel», когда
  /// дойдёт до экранов заказа.
  static const double sheet = xl;

  static const double pill = full;
}

/// Отступы. Макет: сетка 4px, space/0…space/12.
abstract final class AppSpacing {
  /// space/1
  static const double xs = 4;

  /// space/2
  static const double sm = 8;

  /// space/3
  static const double md = 12;

  /// space/4
  static const double lg = 16;

  /// space/5
  static const double s5 = 20;

  /// space/6
  static const double xl = 24;

  /// space/8
  static const double xxl = 32;

  /// space/10
  static const double s10 = 40;

  /// space/12
  static const double s12 = 48;

  /// Боковое поле экрана: 375 − 343 = 32, по 16 с каждой стороны.
  static const double gutter = 16;

  /// Кнопка L.
  static const double buttonHeight = 52;

  /// Кнопка M.
  static const double buttonHeightM = 44;

  /// Кнопка S.
  static const double buttonHeightS = 36;

  /// Поле ввода (Input, Select).
  static const double fieldHeight = 56;

  /// Поле поиска (Search Bar). Имя старое: так оно уже называется в коде.
  static const double inputHeight = 48;

  /// Иконка-кнопка (Icon Button).
  static const double iconButton = 40;

  /// Высота нижнего меню. Сверить с «Navigatsiya», когда дойдёт до меню.
  static const double navHeight = 80;

  /// Иконка в интерфейсе. У кнопки L — 22, M — 20, S — 18.
  static const double icon = 24;
}

/// Тени. Макет: «Soyalar» плюс тени из компонентов кнопок и поля.
/// Цвет у всех — navy/900 или бренд с прозрачностью, не чёрный.
abstract final class AppShadows {
  /// Shadow/Card.
  static const List<BoxShadow> card = [
    BoxShadow(color: Color(0x0F162438), offset: Offset(0, 2), blurRadius: 8),
  ];

  /// Shadow/Floating. Плавающие кнопки и шторки поверх карты.
  static const List<BoxShadow> floating = [
    BoxShadow(color: Color(0x1F162438), offset: Offset(0, 8), blurRadius: 24),
  ];

  /// Shadow/XS. Outline-кнопка.
  static const List<BoxShadow> xs = [
    BoxShadow(color: Color(0x0F162438), offset: Offset(0, 1), blurRadius: 2),
  ];

  /// Shadow/Brand. Синяя кнопка в покое.
  static const List<BoxShadow> brand = [
    BoxShadow(
      color: Color(0x47316DC8),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -4,
    ),
  ];

  /// Shadow/Accent. Жёлтая кнопка в покое.
  static const List<BoxShadow> accent = [
    BoxShadow(
      color: Color(0x4DD9990D),
      offset: Offset(0, 6),
      blurRadius: 16,
      spreadRadius: -4,
    ),
  ];

  /// Focus ring. Кольцо 4px вокруг поля в фокусе.
  static const List<BoxShadow> focusRing = [
    BoxShadow(color: Color(0x2E316DC8), spreadRadius: 4),
  ];
}

/// Типографика. Макет: «Tipografiya — Inter», шрифт лежит в
/// `assets/fonts/` и объявлен в pubspec.yaml.
///
/// `height` — это lineHeight / fontSize из макета.
abstract final class AppTypography {
  static const String? fontFamily = 'Inter';

  /// Display/32 Bold · 32/40.
  static const TextStyle display = TextStyle(
    fontFamily: fontFamily,
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: -0.5,
    color: AppPalette.textPrimary,
  );

  /// Heading/H1 24 Bold · 24/32.
  static const TextStyle h1 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
    letterSpacing: -0.3,
    color: AppPalette.textPrimary,
  );

  /// Heading/H2 20 Bold · 20/28.
  static const TextStyle h2 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    height: 28 / 20,
    letterSpacing: -0.2,
    color: AppPalette.textPrimary,
  );

  /// Heading/H3 17 Semibold · 17/24.
  static const TextStyle h3 = TextStyle(
    fontFamily: fontFamily,
    fontSize: 17,
    fontWeight: FontWeight.w600,
    height: 24 / 17,
    color: AppPalette.textPrimary,
  );

  /// Price/22 Bold · 22/28.
  static const TextStyle price = TextStyle(
    fontFamily: fontFamily,
    fontSize: 22,
    fontWeight: FontWeight.w700,
    height: 28 / 22,
    letterSpacing: -0.2,
    color: AppPalette.textPrimary,
  );

  /// Body/L 16 Regular · 16/24.
  static const TextStyle body = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppPalette.textPrimary,
  );

  /// Body/L 16 Medium · 16/24.
  static const TextStyle bodyMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 24 / 16,
    color: AppPalette.textPrimary,
  );

  /// Body/M 14 Regular · 14/20.
  static const TextStyle bodyM = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppPalette.textPrimary,
  );

  /// Body/M 14 Medium · 14/20.
  static const TextStyle bodyMMedium = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    color: AppPalette.textPrimary,
  );

  /// Caption/12 Regular · 12/16.
  static const TextStyle captionS = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 16 / 12,
    color: AppPalette.textSecondary,
  );

  /// Caption/12 Semibold · 12/16.
  static const TextStyle captionSemibold = TextStyle(
    fontFamily: fontFamily,
    fontSize: 12,
    fontWeight: FontWeight.w600,
    height: 16 / 12,
    color: AppPalette.textSecondary,
  );

  /// Label/Button L 16 Semibold · 16/20. Надпись на кнопке L.
  static const TextStyle buttonLarge = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    height: 20 / 16,
    letterSpacing: -0.1,
    color: AppPalette.textOnBrand,
  );

  /// Label/Button S 14 Semibold · 14/18. Надпись на кнопках M и S.
  static const TextStyle button = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w600,
    height: 18 / 14,
    letterSpacing: -0.1,
    color: AppPalette.textOnBrand,
  );

  // ── Старые имена (первый макет) ────────────────────────────────────────

  // Константы, а не copyWith: их подставляют в const-виджеты.

  /// Подзаголовок под заголовком экрана → Body/M 14 Regular, вторичный.
  static const TextStyle subtitle = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    color: AppPalette.textSecondary,
  );

  /// Мелкий текст → Caption/12 Regular.
  static const TextStyle small = captionS;

  /// Подпись под названием → Body/M 14 Medium, вторичный.
  static const TextStyle caption = TextStyle(
    fontFamily: fontFamily,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    height: 20 / 14,
    color: AppPalette.textSecondary,
  );

  /// Подсказка в поле → Body/L 16 Regular, вторичный (так в компоненте Input).
  static const TextStyle hint = TextStyle(
    fontFamily: fontFamily,
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    color: AppPalette.textSecondary,
  );

  /// Подпись вкладки нижнего меню. Сверить с «Navigatsiya».
  static const TextStyle navLabel = captionS;
}
