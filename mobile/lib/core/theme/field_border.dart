import 'package:flutter/material.dart';

/// Рамка поля ввода из Design System («Input»): скруглённая, а подпись
/// при вводе поднимается ВНУТРЬ поля, а не встаёт в разрыв рамки.
///
/// Обычный [OutlineInputBorder] кладёт всплывшую подпись на линию рамки и
/// вырезает под неё разрыв — так рисует Material, в макете иначе.
/// InputDecorator решает, куда ставить подпись, по [isOutline]: `false`
/// даёт расположение «внутри», как у заливного поля. Разрыв при этом не
/// рисуется вообще.
class FieldBorder extends OutlineInputBorder {
  const FieldBorder({
    super.borderSide,
    super.borderRadius,
  });

  @override
  bool get isOutline => false;

  @override
  FieldBorder copyWith({
    BorderSide? borderSide,
    BorderRadius? borderRadius,
    double? gapPadding,
  }) =>
      FieldBorder(
        borderSide: borderSide ?? this.borderSide,
        borderRadius: borderRadius ?? this.borderRadius,
      );

  @override
  FieldBorder scale(double t) => FieldBorder(
        borderSide: borderSide.scale(t),
        borderRadius: borderRadius * t,
      );

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is FieldBorder) {
      return FieldBorder(
        borderSide: BorderSide.lerp(a.borderSide, borderSide, t),
        borderRadius: BorderRadius.lerp(a.borderRadius, borderRadius, t)!,
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is FieldBorder) {
      return FieldBorder(
        borderSide: BorderSide.lerp(borderSide, b.borderSide, t),
        borderRadius: BorderRadius.lerp(borderRadius, b.borderRadius, t)!,
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    double? gapStart,
    double gapExtent = 0.0,
    double gapPercentage = 0.0,
    TextDirection? textDirection,
  }) {
    // Разрыв не нужен никогда — подпись внутри.
    super.paint(canvas, rect, textDirection: textDirection);
  }
}
