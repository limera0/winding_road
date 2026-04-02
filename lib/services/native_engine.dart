import 'dart:math' as math;

/// GPS 포인트
class GpsPoint {
  final double lat;
  final double lng;
  const GpsPoint(this.lat, this.lng);
}

/// 유사도 결과
class SimilarityResult {
  final double score;
  final bool isDuplicate;
  const SimilarityResult({required this.score, required this.isDuplicate});
}

/// 와인딩 점수 결과
class WindingScore {
  final double score;
  final String roadType; // "country" | "provincial" | "national"
  const WindingScore({required this.score, required this.roadType});
}

/// Rust native engine의 Dart fallback 구현.
///
/// flutter_rust_bridge codegen 완료 후 native 바인딩으로 교체 가능.
/// API 시그니처는 native/src/api.rs 와 1:1 대응.
class NativeEngine {
  static const double _gridSize = 0.01;
  static const double _interpStep = 0.005;

  // ── 경로 유사도 (Jaccard) ─────────────────────────────────

  static SimilarityResult checkRouteSimilarity(
    List<GpsPoint> routeA,
    List<GpsPoint> routeB,
  ) {
    if (routeA.isEmpty || routeB.isEmpty) {
      return const SimilarityResult(score: 0.0, isDuplicate: false);
    }
    final cellsA = _routeToCells(routeA);
    final cellsB = _routeToCells(routeB);

    final intersection = cellsA.intersection(cellsB).length;
    final union = cellsA.union(cellsB).length;
    final score = union == 0 ? 0.0 : intersection / union;

    return SimilarityResult(score: score, isDuplicate: score >= 0.70);
  }

  static Set<String> _routeToCells(List<GpsPoint> points) {
    final cells = <String>{};
    for (int i = 0; i < points.length - 1; i++) {
      final p1 = points[i];
      final p2 = points[i + 1];
      final dist = math.sqrt(
          math.pow(p2.lat - p1.lat, 2) + math.pow(p2.lng - p1.lng, 2));
      final steps = (dist / _interpStep).ceil().clamp(1, 9999);
      for (int s = 0; s <= steps; s++) {
        final t = s / steps;
        final lat = p1.lat + (p2.lat - p1.lat) * t;
        final lng = p1.lng + (p2.lng - p1.lng) * t;
        final key =
            '${(lat / _gridSize).floor()}_${(lng / _gridSize).floor()}';
        cells.add(key);
      }
    }
    return cells;
  }

  // ── 와인딩 필터 ───────────────────────────────────────────

  static WindingScore calcWindingScore(List<GpsPoint> route) {
    if (route.length < 3) {
      return const WindingScore(score: 0.0, roadType: 'national');
    }

    double totalAngle = 0;
    double totalDistM = 0;

    for (int i = 1; i < route.length - 1; i++) {
      totalAngle += _bearingChange(route[i - 1], route[i], route[i + 1]);
      totalDistM += _haversineM(route[i - 1], route[i]);
    }

    if (totalDistM < 1.0) {
      return const WindingScore(score: 0.0, roadType: 'national');
    }

    final scoreRaw = (totalAngle / (totalDistM / 1000.0)).clamp(0.0, 200.0);
    final score = (scoreRaw / 200.0 * 100.0).clamp(0.0, 100.0);

    final roadType =
        score < 20 ? 'national' : score < 50 ? 'provincial' : 'country';

    return WindingScore(score: score, roadType: roadType);
  }

  static double _bearingChange(GpsPoint p0, GpsPoint p1, GpsPoint p2) {
    final b1 = _bearing(p0, p1);
    final b2 = _bearing(p1, p2);
    double delta = (b2 - b1).abs();
    if (delta > 180) delta = 360 - delta;
    return delta;
  }

  static double _bearing(GpsPoint a, GpsPoint b) {
    final lat1 = a.lat * math.pi / 180;
    final lat2 = b.lat * math.pi / 180;
    final dlon = (b.lng - a.lng) * math.pi / 180;
    final x = math.sin(dlon) * math.cos(lat2);
    final y = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dlon);
    return math.atan2(x, y) * 180 / math.pi;
  }

  static double _haversineM(GpsPoint a, GpsPoint b) {
    const R = 6371000.0;
    final dLat = (b.lat - a.lat) * math.pi / 180;
    final dLon = (b.lng - a.lng) * math.pi / 180;
    final sinHalfLat = math.sin(dLat / 2);
    final sinHalfLon = math.sin(dLon / 2);
    final h = sinHalfLat * sinHalfLat +
        math.cos(a.lat * math.pi / 180) *
            math.cos(b.lat * math.pi / 180) *
            sinHalfLon *
            sinHalfLon;
    return 2 * R * math.asin(math.sqrt(h));
  }
}
