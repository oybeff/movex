import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_tokens.dart';

/// Вариант логотипа. Макет: Design System → «Logo», свойство «Turi».
enum AppLogoKind {
  /// Только знак (пин + экскаватор). Иконка приложения, маркер на карте.
  mark,

  /// Знак слева, надпись справа. Шапки экранов.
  horizontal,

  /// Знак сверху, надпись и «POWER IN MOTION» под ним. Splash, вход.
  vertical,
}

/// Логотип MoveX GO (вариант A «Pin + ekskavator», выбран 09.11.2026).
///
/// Знак — вектор `assets/brand/logo_mark.svg` из макета. Надпись — живой
/// текст шрифтом Montserrat, как в макете: картинкой она мылилась бы,
/// Figma отдаёт растр только в натуральном размере.
///
/// [height] задаёт высоту всего логотипа; пропорции и отступы внутри — из
/// макета, масштабируются вместе.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.kind = AppLogoKind.horizontal,
    this.onDark = false,
    this.height,
  });

  final AppLogoKind kind;

  /// Логотип на тёмном фоне (#162438): «MoveX» белым, подпись жёлтым.
  final bool onDark;

  /// Высота. `null` — натуральный размер из макета.
  final double? height;

  static const String markAsset = 'assets/brand/logo_mark.svg';

  // Натуральные размеры из макета.
  static const double _markW = 80, _markH = 104;
  static const double _hHeight = 64;
  static const double _vHeight = 232;

  @override
  Widget build(BuildContext context) {
    final natural = switch (kind) {
      AppLogoKind.mark => _markH,
      AppLogoKind.horizontal => _hHeight,
      AppLogoKind.vertical => _vHeight,
    };
    final child = switch (kind) {
      AppLogoKind.mark => _mark(_markH),
      AppLogoKind.horizontal => _horizontal(),
      AppLogoKind.vertical => _vertical(),
    };
    return Semantics(
      label: 'MoveX GO',
      image: true,
      child: SizedBox(
        height: height ?? natural,
        child: FittedBox(fit: BoxFit.contain, child: child),
      ),
    );
  }

  Widget _mark(double h) => SvgPicture.asset(
        markAsset,
        height: h,
        width: h * _markW / _markH,
      );

  Widget _wordmark({required double size, required double gap}) {
    final style = TextStyle(
      fontFamily: 'Montserrat',
      fontWeight: FontWeight.w800,
      fontSize: size,
      letterSpacing: -size * 0.02,
      height: 1.22,
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'MoveX',
          style: style.copyWith(
            color: onDark ? AppPalette.textOnBrand : AppPalette.textPrimary,
          ),
        ),
        SizedBox(width: gap),
        Text('GO', style: style.copyWith(color: AppPalette.accent)),
      ],
    );
  }

  // Макет: знак 49×64, отступ 14, надпись 40/-0.8, между словами 11.
  Widget _horizontal() => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mark(_hHeight),
          const SizedBox(width: 14),
          _wordmark(size: 40, gap: 11),
        ],
      );

  // Макет: знак 92×120, отступы 16, надпись 52/-1.04, между словами 15,
  // «POWER IN MOTION» 14 SemiBold, разрядка 3.36.
  Widget _vertical() => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _mark(120),
          const SizedBox(height: 16),
          _wordmark(size: 52, gap: 15),
          const SizedBox(height: 16),
          Text(
            'POWER IN MOTION',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 3.36,
              color: onDark ? AppPalette.accent : AppPalette.textSecondary,
            ),
          ),
        ],
      );
}
