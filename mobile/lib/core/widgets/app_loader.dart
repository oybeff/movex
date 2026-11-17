import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Индикатор загрузки. Макет: «Auth/Loader» — «единый loading: все ожидания
/// в приложении — это вращающееся кольцо, 0.8 с на оборот. S — внутри
/// кнопки, M — рядом с текстом, L — splash и полный экран».
///
/// Рисунок — вектор из макета (`assets/brand/loader.svg`: бледная дорожка
/// и дуга в 3/4 круга), вращается целиком. Системный
/// CircularProgressIndicator меняет длину дуги и выглядит иначе.
class AppLoader extends StatefulWidget {
  const AppLoader({super.key, this.size = 32});

  final double size;

  @override
  State<AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<AppLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'loading',
      child: RotationTransition(
        turns: _c,
        child: SvgPicture.asset(
          'assets/brand/loader.svg',
          width: widget.size,
          height: widget.size,
        ),
      ),
    );
  }
}
