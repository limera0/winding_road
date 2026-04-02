import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';

/// Overpass API를 통해 6종 POI를 실시간 수집하고
/// 오모테나시 목적지 스냅 로직을 수행하는 서비스.
class PoiService {
  static const _overpassUrl = 'https://overpass-api.de/api/interpreter';

  // ── Overpass 쿼리 헬퍼 ────────────────────────────────────────

  /// LatLng 중심, 반경(m)에 해당하는 특정 타입의 POI를 가져온다.
  Future<List<Poi>> fetchPois({
    required LatLng center,
    required double radiusMeters,
    required List<PoiType> types,
  }) async {
    final parts = types.map((t) => _buildFilter(t)).join('\n');
    final query = '''
[out:json][timeout:25];
(
$parts
);
out body;
''';

    // Overpass QL의 around 필터를 위해 위도/경도와 반경 삽입
    final filledQuery = query
        .replaceAll('RADIUS', radiusMeters.toStringAsFixed(0))
        .replaceAll('LAT', center.latitude.toString())
        .replaceAll('LNG', center.longitude.toString());

    try {
      final resp = await http
          .post(
            Uri.parse(_overpassUrl),
            headers: {'Content-Type': 'application/x-www-form-urlencoded'},
            body: {'data': filledQuery},
          )
          .timeout(const Duration(seconds: 30));

      if (resp.statusCode != 200) return [];

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final elements = (json['elements'] as List<dynamic>? ?? []);

      return elements.map((e) => _parseElement(e as Map<String, dynamic>)).whereType<Poi>().toList();
    } catch (_) {
      return [];
    }
  }

  String _buildFilter(PoiType type) {
    switch (type) {
      case PoiType.cafe:
        return '  node["amenity"="cafe"](around:RADIUS,LAT,LNG);\n'
            '  way["amenity"="cafe"](around:RADIUS,LAT,LNG);';
      case PoiType.convenienceStore:
        return '  node["shop"="convenience"](around:RADIUS,LAT,LNG);\n'
            '  way["shop"="convenience"](around:RADIUS,LAT,LNG);';
      case PoiType.gasStation:
        return '  node["amenity"="fuel"](around:RADIUS,LAT,LNG);\n'
            '  way["amenity"="fuel"](around:RADIUS,LAT,LNG);';
      case PoiType.traditionalMarket:
        return '  node["amenity"="marketplace"](around:RADIUS,LAT,LNG);\n'
            '  way["amenity"="marketplace"](around:RADIUS,LAT,LNG);';
      case PoiType.supermarket:
        return '  node["shop"="supermarket"](around:RADIUS,LAT,LNG);\n'
            '  way["shop"="supermarket"](around:RADIUS,LAT,LNG);';
      case PoiType.restaurant:
        return '  node["amenity"="restaurant"](around:RADIUS,LAT,LNG);\n'
            '  way["amenity"="restaurant"](around:RADIUS,LAT,LNG);';
    }
  }

  Poi? _parseElement(Map<String, dynamic> e) {
    final tags = (e['tags'] as Map<String, dynamic>?) ?? {};
    final id = (e['id'] as num).toInt();
    final name = (tags['name'] as String?) ?? '이름 없음';

    double? lat;
    double? lng;

    if (e.containsKey('lat')) {
      lat = (e['lat'] as num).toDouble();
      lng = (e['lon'] as num).toDouble();
    } else if (e.containsKey('center')) {
      final center = e['center'] as Map<String, dynamic>;
      lat = (center['lat'] as num).toDouble();
      lng = (center['lon'] as num).toDouble();
    } else {
      return null;
    }

    final type = _detectType(tags);
    if (type == null) return null;

    final ratingStr = tags['stars'] as String? ?? tags['rating'] as String?;
    final rating = ratingStr != null ? double.tryParse(ratingStr) : null;

    return Poi(
      id: id,
      name: name,
      type: type,
      location: LatLng(lat, lng),
      rating: rating,
    );
  }

  PoiType? _detectType(Map<String, dynamic> tags) {
    final amenity = tags['amenity'] as String?;
    final shop = tags['shop'] as String?;
    if (amenity == 'cafe') return PoiType.cafe;
    if (shop == 'convenience') return PoiType.convenienceStore;
    if (amenity == 'fuel') return PoiType.gasStation;
    if (amenity == 'marketplace') return PoiType.traditionalMarket;
    if (shop == 'supermarket') return PoiType.supermarket;
    if (amenity == 'restaurant') return PoiType.restaurant;
    return null;
  }

  // ── 거리 계산 ─────────────────────────────────────────────────

  static double haversineMeters(LatLng a, LatLng b) {
    const toRad = pi / 180.0;
    final dLat = (b.latitude - a.latitude) * toRad;
    final dLon = (b.longitude - a.longitude) * toRad;
    final sinHLat = sin(dLat / 2);
    final sinHLon = sin(dLon / 2);
    final h =
        sinHLat * sinHLat + cos(a.latitude * toRad) * cos(b.latitude * toRad) * (sinHLon * sinHLon);
    return 6371000 * 2 * asin(sqrt(h));
  }

  /// 두 점이 이루는 방위각(bearing) 계산 (degree)
  static double bearing(LatLng from, LatLng to) {
    const toRad = pi / 180.0;
    final dLon = (to.longitude - from.longitude) * toRad;
    final lat1 = from.latitude * toRad;
    final lat2 = to.latitude * toRad;
    final y = sin(dLon) * cos(lat2);
    final x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon);
    return (atan2(y, x) * 180 / pi + 360) % 360;
  }

  /// 두 방위각의 절대 차이 (0~180)
  static double bearingDiff(double a, double b) {
    final diff = ((a - b).abs()) % 360;
    return diff > 180 ? 360 - diff : diff;
  }

  // ── 오모테나시 스냅 로직 ───────────────────────────────────────

  /// 반환값: (스냅된 POI 또는 null, 사용된 반경km, 모든 POI 목록)
  Future<SnapResult> snapDestination({
    required LatLng origin,
    required LatLng tapped,
    double radiusKm = 1.0,
  }) async {
    final radiusM = radiusKm * 1000;

    // 1. 반경 내 모든 POI 수집
    final allPois = await fetchPois(
      center: tapped,
      radiusMeters: radiusM,
      types: PoiType.values,
    );

    // Step A: 반경 내 카페 중 가장 평점 높은 것
    final cafes = allPois.where((p) => p.type == PoiType.cafe).toList()
      ..sort((a, b) => (b.rating ?? 0).compareTo(a.rating ?? 0));

    if (cafes.isNotEmpty) {
      return SnapResult(
        snappedPoi: cafes.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // Step B: 현재 주행 방향에 인접(±45°)한 편의점 탐색
    final headingBearing = bearing(origin, tapped);
    final convStores = allPois.where((p) => p.type == PoiType.convenienceStore).toList();

    final sameSide = convStores
        .where((p) => bearingDiff(bearing(tapped, p.location), headingBearing) <= 45)
        .toList()
      ..sort((a, b) => haversineMeters(tapped, a.location).compareTo(haversineMeters(tapped, b.location)));

    if (sameSide.isNotEmpty) {
      return SnapResult(
        snappedPoi: sameSide.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // Step C: 반대편(길 건너) 편의점 - 방향차 > 45°인 가장 가까운 편의점
    final otherSide = convStores
        .where((p) => bearingDiff(bearing(tapped, p.location), headingBearing) > 45)
        .toList()
      ..sort((a, b) => haversineMeters(tapped, a.location).compareTo(haversineMeters(tapped, b.location)));

    if (otherSide.isNotEmpty) {
      return SnapResult(
        snappedPoi: otherSide.first,
        allPois: allPois,
        radiusKm: radiusKm,
      );
    }

    // 카페/편의점 없음 -> null 반환 (팝업 트리거)
    return SnapResult(
      snappedPoi: null,
      allPois: allPois,
      radiusKm: radiusKm,
    );
  }
}

class SnapResult {
  final Poi? snappedPoi;
  final List<Poi> allPois;
  final double radiusKm;

  const SnapResult({
    required this.snappedPoi,
    required this.allPois,
    required this.radiusKm,
  });
}
