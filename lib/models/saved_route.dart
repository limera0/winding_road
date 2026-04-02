import 'dart:convert';

enum RouteType { country, provincial, national }

extension RouteTypeExt on RouteType {
  String get label {
    switch (this) {
      case RouteType.country:
        return '시골길';
      case RouteType.provincial:
        return '지방도';
      case RouteType.national:
        return '국도';
    }
  }

  // 경로 색상
  int get colorValue {
    switch (this) {
      case RouteType.country:
        return 0xFF4CAF50; // 초록
      case RouteType.provincial:
        return 0xFF2196F3; // 파랑
      case RouteType.national:
        return 0xFFFF9800; // 주황
    }
  }
}

class RoutePoint {
  final double lat;
  final double lng;

  const RoutePoint(this.lat, this.lng);

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};
  factory RoutePoint.fromJson(Map<String, dynamic> j) =>
      RoutePoint(j['lat'] as double, j['lng'] as double);
}

class SavedRoute {
  final String id;
  final String name;
  final List<RoutePoint> points;
  final RouteType type;
  final DateTime savedAt;
  final double distanceKm;

  const SavedRoute({
    required this.id,
    required this.name,
    required this.points,
    required this.type,
    required this.savedAt,
    required this.distanceKm,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'points': points.map((p) => p.toJson()).toList(),
        'type': type.index,
        'savedAt': savedAt.toIso8601String(),
        'distanceKm': distanceKm,
      };

  factory SavedRoute.fromJson(Map<String, dynamic> j) => SavedRoute(
        id: j['id'] as String,
        name: j['name'] as String,
        points: (j['points'] as List<dynamic>)
            .map((e) => RoutePoint.fromJson(e as Map<String, dynamic>))
            .toList(),
        type: RouteType.values[j['type'] as int],
        savedAt: DateTime.parse(j['savedAt'] as String),
        distanceKm: (j['distanceKm'] as num).toDouble(),
      );

  String toJsonString() => jsonEncode(toJson());
  factory SavedRoute.fromJsonString(String raw) =>
      SavedRoute.fromJson(jsonDecode(raw) as Map<String, dynamic>);
}
