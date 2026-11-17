import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../../core/theme/app_tokens.dart';

/// Метки и линии карты заказа (макет, кадры 3–9).
///
/// MapKit принимает картинку метки только растром, а иконки проекта —
/// SVG. Поэтому метки рисуются здесь на Canvas вместе с подписью-плашкой
/// («Chilonzor 9-kv», «12 daq») и кэшируются по тексту: карта
/// перестраивает объекты на каждый setState.
class TaxiMarkers {
  TaxiMarkers._();

  static final Map<String, Future<TaxiMarker>> _cache = {};

  /// Точка «откуда»: синий круг с белой обводкой.
  static Future<TaxiMarker> pointA(String? label, {bool darkLabel = false}) =>
      _cached('a|$label|$darkLabel', () => _marker(_Kind.a, label, darkLabel));

  /// Точка «куда»: тёмный квадрат.
  static Future<TaxiMarker> pointB(String? label) =>
      _cached('b|$label', () => _marker(_Kind.b, label, false));

  /// Техника: белый круг с синей обводкой и экскаватором.
  static Future<TaxiMarker> equipment(String? label) =>
      _cached('e|$label', () => _marker(_Kind.equipment, label, true));

  static Future<TaxiMarker> _cached(String key, Future<TaxiMarker> Function() build) =>
      _cache.putIfAbsent(key, build);

  static ui.Picture? _excavator;

  static Future<TaxiMarker> _marker(_Kind kind, String? label, bool darkLabel) async {
    final dpr = ui.PlatformDispatcher.instance.views.first.devicePixelRatio;
    final icon = kind == _Kind.equipment ? 44.0 : 26.0;
    const gap = 6.0;

    TextPainter? text;
    var pillW = 0.0, pillH = 0.0;
    if (label != null && label.isNotEmpty) {
      text = TextPainter(
        text: TextSpan(
          text: label.length > 28 ? '${label.substring(0, 27)}…' : label,
          style: TextStyle(
            fontFamily: AppTypography.fontFamily,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: darkLabel ? Colors.white : AppPalette.textPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      pillW = text.width + 20;
      pillH = 26;
    }
    final w = math.max(icon, pillW) + 8;
    final h = (text == null ? 0 : pillH + gap) + icon + 8;

    final rec = ui.PictureRecorder();
    final c = Canvas(rec)..scale(dpr);
    final shadow = Paint()
      ..color = const Color(0x33162438)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    if (text != null) {
      final r = RRect.fromRectAndRadius(
        Rect.fromLTWH((w - pillW) / 2, 2, pillW, pillH),
        const Radius.circular(10),
      );
      c.drawRRect(r.shift(const Offset(0, 1)), shadow);
      c.drawRRect(r, Paint()..color = darkLabel ? AppPalette.inverse : AppPalette.surface);
      text.paint(c, Offset((w - text.width) / 2, 2 + (pillH - text.height) / 2));
    }

    final cy = (text == null ? 4 : pillH + gap + 2) + icon / 2;
    final center = Offset(w / 2, cy);
    switch (kind) {
      case _Kind.a:
        c.drawCircle(center.translate(0, 1), icon / 2, shadow);
        c.drawCircle(center, icon / 2, Paint()..color = Colors.white);
        c.drawCircle(center, icon / 2 - 4, Paint()..color = AppPalette.brand);
      case _Kind.b:
        final outer = RRect.fromRectAndRadius(Rect.fromCircle(center: center, radius: icon / 2), const Radius.circular(7));
        c.drawRRect(outer.shift(const Offset(0, 1)), shadow);
        c.drawRRect(outer, Paint()..color = Colors.white);
        c.drawRRect(outer.deflate(3), Paint()..color = AppPalette.inverse);
        c.drawRRect(
          RRect.fromRectAndRadius(Rect.fromCircle(center: center, radius: 4), const Radius.circular(1.5)),
          Paint()..color = Colors.white,
        );
      case _Kind.equipment:
        c.drawCircle(center.translate(0, 1), icon / 2, shadow);
        c.drawCircle(center, icon / 2, Paint()..color = AppPalette.brand);
        c.drawCircle(center, icon / 2 - 2.5, Paint()..color = Colors.white);
        _excavator ??= (await vg.loadPicture(const SvgAssetLoader('assets/icons/excavator_marker.svg'), null)).picture;
        c.save();
        c.translate(center.dx - 12, center.dy - 12);
        c.drawPicture(_excavator!);
        c.restore();
    }

    final img = await rec.endRecording().toImage((w * dpr).ceil(), (h * dpr).ceil());
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    return TaxiMarker(BitmapDescriptor.fromBytes(bytes!.buffer.asUint8List()), Offset(.5, cy / h));
  }
}

/// Картинка метки и где на ней сама точка (доля ширины и высоты).
class TaxiMarker {
  const TaxiMarker(this.image, this.anchor);

  final BitmapDescriptor image;
  final Offset anchor;

  PlacemarkMapObject at(String id, Point point, {double z = 1}) => PlacemarkMapObject(
        mapId: MapObjectId(id),
        point: point,
        zIndex: z,
        opacity: 1,
        icon: PlacemarkIcon.single(PlacemarkIconStyle(image: image, anchor: anchor)),
      );
}

enum _Kind { a, b, equipment }

/// Линия маршрута по дорогам (Yandex Driving). Роутер не ответил за
/// 6 секунд, нет ключа или это браузер — прямая между точками: пустая
/// карта хуже прямой линии.
class TaxiRoute {
  TaxiRoute._();

  static final Map<String, List<Point>> _cache = {};

  static Future<List<Point>> between(Point a, Point b) async {
    final key = '${a.latitude.toStringAsFixed(5)},${a.longitude.toStringAsFixed(5)}'
        '>${b.latitude.toStringAsFixed(5)},${b.longitude.toStringAsFixed(5)}';
    final hit = _cache[key];
    if (hit != null) return hit;
    try {
      final res = YandexDriving.requestRoutes(
        points: [
          RequestPoint(point: a, requestPointType: RequestPointType.wayPoint),
          RequestPoint(point: b, requestPointType: RequestPointType.wayPoint),
        ],
        drivingOptions: const DrivingOptions(routesCount: 1),
      );
      final r = await res.result.timeout(const Duration(seconds: 6));
      unawaited(res.session.close());
      final pts = r.routes?.firstOrNull?.geometry;
      if (pts != null && pts.length > 1) return _cache[key] = pts;
    } catch (_) {
      // MissingPluginException в браузере, таймаут, ошибка сети — прямая
    }
    return [a, b];
  }

  /// Рамка вокруг точек с запасом, чтобы метки с подписями не упирались в край.
  static BoundingBox bounds(List<Point> pts) {
    var n = -90.0, s = 90.0, e = -180.0, w = 180.0;
    for (final p in pts) {
      n = math.max(n, p.latitude);
      s = math.min(s, p.latitude);
      e = math.max(e, p.longitude);
      w = math.min(w, p.longitude);
    }
    final dLat = math.max((n - s) * .15, .002), dLon = math.max((e - w) * .15, .002);
    return BoundingBox(
      northEast: Point(latitude: n + dLat, longitude: e + dLon),
      southWest: Point(latitude: s - dLat, longitude: w - dLon),
    );
  }
}

/// Шаг 7: расходящиеся круги вокруг точки, пока идёт поиск техники.
class SearchPulse extends StatefulWidget {
  const SearchPulse({super.key, this.size = 220});

  final double size;

  @override
  State<SearchPulse> createState() => _SearchPulseState();
}

class _SearchPulseState extends State<SearchPulse> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return IgnorePointer(
      child: SizedBox.square(
        dimension: widget.size,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => CustomPaint(painter: _PulsePainter(reduce ? .35 : _c.value)),
        ),
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter(this.t);

  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final max = size.width / 2;
    for (var i = 0; i < 3; i++) {
      final p = (t + i / 3) % 1;
      canvas.drawCircle(
        c,
        max * (.15 + .85 * p),
        Paint()..color = AppPalette.brand.withValues(alpha: .22 * (1 - p)),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter old) => old.t != t;
}

/// Короткая вибрация в важные моменты потока (техника найдена, отмена).
void taxiHaptic({bool strong = false}) {
  strong ? HapticFeedback.heavyImpact() : HapticFeedback.mediumImpact();
}
