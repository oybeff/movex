import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geolocator/geolocator.dart';
import 'package:yandex_mapkit/yandex_mapkit.dart';

import '../../../core/services/permission_service.dart';

/// Точка с адресом — «Qayerdan» и «Qayerga».
class TaxiPlace {
  const TaxiPlace(this.lat, this.lon, [this.address, this.title]);

  final double lat;
  final double lon;

  /// Адрес без страны и города: «Chilonzor tumani, 9-kvartal, 12».
  /// Он уходит в заказ и показывается в полях «Qayerdan»/«Qayerga».
  final String? address;

  /// Короткое имя места для списка подсказок: «Sergeli tumani»,
  /// «Amir Temur ko'chasi, 108». null — первая часть адреса.
  final String? title;

  Point get point => Point(latitude: lat, longitude: lon);

  String get label => title ?? (address ?? '').split(',').first;

  TaxiPlace withAddress(String? a) => TaxiPlace(lat, lon, a);
}

/// Геолокация и адреса.
///
/// Адрес по точке и поиск адреса — через поиск самой Yandex MapKit
/// (YandexSearch). HTTP-геокодер в проекте с ключом-заглушкой и не
/// работает. MapKit есть только на телефоне: в браузере адрес вводится
/// руками, а точкой служит текущее местоположение.
class TaxiGeo {
  /// Центр Ташкента — если геолокация недоступна.
  static const TaxiPlace tashkent = TaxiPlace(41.2995, 69.2401);

  /// E1: последний запрос геолокации отказан — показать «Joylashuv o'chirilgan».
  static bool denied = false;

  static Future<TaxiPlace> current() async {
    try {
      final perm = await PermissionService.requestLocationPermission();
      denied = !perm.isGranted;
      if (!perm.isGranted) return tashkent;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 8),
        ),
      );
      return TaxiPlace(pos.latitude, pos.longitude);
    } catch (_) {
      return tashkent;
    }
  }

  static bool get canSearch => !kIsWeb;

  /// Расстояние по прямой, км (гаверсинус).
  static double distanceKm(TaxiPlace a, TaxiPlace b) {
    const r = 6371.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lon - a.lon) * math.pi / 180;
    final h = math.pow(math.sin(dLat / 2), 2) +
        math.cos(a.lat * math.pi / 180) * math.cos(b.lat * math.pi / 180) * math.pow(math.sin(dLon / 2), 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// Адрес по точке. null — не нашли или браузер.
  static Future<String?> addressAt(TaxiPlace p) async {
    if (kIsWeb) return null;
    try {
      final res = YandexSearch.searchByPoint(
        point: p.point,
        zoom: 17,
        searchOptions: const SearchOptions(searchType: SearchType.geo, resultPageSize: 1),
      );
      final r = await res.result.timeout(const Duration(seconds: 8));
      await res.session.close();
      final item = (r.items ?? const []).isEmpty ? null : r.items!.first;
      final meta = item?.toponymMetadata;
      return meta != null ? shortAddress(meta.address) : item?.name;
    } catch (_) {
      return null;
    }
  }

  /// Поиск адреса по тексту рядом с точкой. Пусто — браузер или ничего,
  /// null — поиск не ответил (нет сети): экран скажет об этом прямо.
  static Future<List<TaxiPlace>?> search(String text, TaxiPlace near) async {
    if (kIsWeb || text.trim().length < 3) return const [];
    try {
      final res = YandexSearch.searchByText(
        searchText: text,
        geometry: Geometry.fromBoundingBox(BoundingBox(
          northEast: Point(latitude: near.lat + 0.6, longitude: near.lon + 0.8),
          southWest: Point(latitude: near.lat - 0.6, longitude: near.lon - 0.8),
        )),
        searchOptions: const SearchOptions(searchType: SearchType.geo, resultPageSize: 8),
      );
      final r = await res.result.timeout(const Duration(seconds: 8));
      await res.session.close();
      final out = <TaxiPlace>[];
      for (final item in r.items ?? const <SearchItem>[]) {
        final meta = item.toponymMetadata;
        if (meta == null) continue;
        out.add(TaxiPlace(
          meta.balloonPoint.latitude,
          meta.balloonPoint.longitude,
          shortAddress(meta.address),
          item.name,
        ));
      }
      if (r.error != null && out.isEmpty) return null;
      return out;
    } catch (_) {
      return null;
    }
  }

  /// Адрес для человека: без «Uzbekistan», области и «Tashkent» —
  /// все заказы и так в Ташкенте и области. В списке подсказок все
  /// результаты начинались с одной и той же страны, и заголовком у всех
  /// восьми было «Uzbekistan».
  static String shortAddress(SearchAddress a) {
    const drop = {
      SearchComponentKind.country,
      SearchComponentKind.region,
      SearchComponentKind.province,
      SearchComponentKind.locality,
    };
    final skip = {
      for (final e in a.addressComponents.entries)
        if (drop.contains(e.key)) e.value.trim().toLowerCase(),
    };
    final parts = a.formattedAddress
        .split(',')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    final kept = parts.where((p) => !skip.contains(p.toLowerCase())).toList();
    // Совсем пусто (искали сам город) — оставить последнюю часть.
    return kept.isEmpty ? (parts.isEmpty ? a.formattedAddress : parts.last) : kept.join(', ');
  }
}
