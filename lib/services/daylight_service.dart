import 'package:sunrise_sunset_calc/sunrise_sunset_calc.dart';

/// BMNT/EENT 계산 서비스 — sunrise_sunset_calc 패키지 기반
///
/// BMNT (시민박명 시작) = sunrise − 30분
/// EENT (시민박명 종료) = sunset  + 30분
///
/// 극지방·계산 불가 시 안전 fallback: 06:00 ~ 20:00
class DaylightService {
  static const _civilOffset = Duration(minutes: 30);

  static ({DateTime bmnt, DateTime eent}) calculate({
    required double lat,
    required double lng,
    required DateTime date,
  }) {
    try {
      final utcOffset = date.timeZoneOffset;
      final result = getSunriseSunset(lat, lng, utcOffset, date);

      // null·NaN 방어
      final sunrise = result.sunrise;
      final sunset = result.sunset;
      if (!sunrise.isFinite || !sunset.isFinite) {
        return _fallback(date);
      }

      return (
        bmnt: sunrise.subtract(_civilOffset),
        eent: sunset.add(_civilOffset),
      );
    } catch (_) {
      return _fallback(date);
    }
  }

  static ({DateTime bmnt, DateTime eent}) _fallback(DateTime date) {
    final base = DateTime(date.year, date.month, date.day);
    return (
      bmnt: base.add(const Duration(hours: 6)),
      eent: base.add(const Duration(hours: 20)),
    );
  }

  static bool isDaytime({
    required double lat,
    required double lng,
    required DateTime now,
  }) {
    try {
      final r = calculate(lat: lat, lng: lng, date: now);
      return now.isAfter(r.bmnt) && now.isBefore(r.eent);
    } catch (_) {
      return true;
    }
  }

  static double daylightProgress({
    required double lat,
    required double lng,
    required DateTime now,
  }) {
    try {
      final r = calculate(lat: lat, lng: lng, date: now);
      if (now.isBefore(r.bmnt)) return 0.0;
      if (now.isAfter(r.eent)) return 1.0;
      final total = r.eent.difference(r.bmnt).inSeconds.toDouble();
      if (total <= 0) return 0.5;
      final elapsed = now.difference(r.bmnt).inSeconds.toDouble();
      return (elapsed / total).clamp(0.0, 1.0);
    } catch (_) {
      return 0.5;
    }
  }
}

// DateTime.isFinite extension (DateTime은 isFinite가 없으므로 범위 검사로 대체)
extension _DateTimeCheck on DateTime {
  bool get isFinite {
    try {
      return year > 1 && year < 9999;
    } catch (_) {
      return false;
    }
  }
}
