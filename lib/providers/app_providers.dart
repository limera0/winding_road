import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
import '../models/user_profile.dart';
import '../models/saved_route.dart';
import '../services/poi_service.dart';
import '../services/profile_service.dart';
import '../services/route_service.dart';
import '../services/daylight_service.dart';

// ── Profile ───────────────────────────────────────────────────

final profileServiceProvider = Provider((_) => ProfileService());

final userProfileProvider =
    AsyncNotifierProvider<UserProfileNotifier, UserProfile>(
        UserProfileNotifier.new);

class UserProfileNotifier extends AsyncNotifier<UserProfile> {
  @override
  Future<UserProfile> build() async {
    return ref.read(profileServiceProvider).load();
  }

  Future<void> save(UserProfile profile) async {
    state = AsyncData(profile);
    await ref.read(profileServiceProvider).save(profile);
  }
}

// ── Saved Routes ──────────────────────────────────────────────

final routeServiceProvider = Provider((_) => RouteService());

final savedRoutesProvider =
    AsyncNotifierProvider<SavedRoutesNotifier, List<SavedRoute>>(
        SavedRoutesNotifier.new);

class SavedRoutesNotifier extends AsyncNotifier<List<SavedRoute>> {
  @override
  Future<List<SavedRoute>> build() async {
    return ref.read(routeServiceProvider).loadAll();
  }

  Future<void> add(SavedRoute route) async {
    final current = state.value ?? [];
    final next = [...current, route];
    state = AsyncData(next);
    await ref.read(routeServiceProvider).saveAll(next);
  }

  Future<void> remove(String id) async {
    final current = state.value ?? [];
    final next = current.where((r) => r.id != id).toList();
    state = AsyncData(next);
    await ref.read(routeServiceProvider).saveAll(next);
  }
}

// ── Location state ────────────────────────────────────────────

final currentLocationProvider =
    NotifierProvider<_LatLngNotifier, LatLng?>(_LatLngNotifier.new);

class _LatLngNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng loc) => state = loc;
}

final destinationProvider =
    NotifierProvider<_DestNotifier, LatLng?>(_DestNotifier.new);

class _DestNotifier extends Notifier<LatLng?> {
  @override
  LatLng? build() => null;

  void set(LatLng? loc) => state = loc;
}

// ── Daylight ──────────────────────────────────────────────────

final daylightProgressProvider = Provider<double>((ref) {
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return 0.5;
  return DaylightService.daylightProgress(
    lat: loc.latitude,
    lng: loc.longitude,
    now: DateTime.now(),
  );
});

final daylightTimesProvider =
    Provider<({DateTime bmnt, DateTime eent})?> ((ref) {
  final loc = ref.watch(currentLocationProvider);
  if (loc == null) return null;
  final r = DaylightService.calculate(
    lat: loc.latitude,
    lng: loc.longitude,
    date: DateTime.now(),
  );
  return r;
});

// ── POI ───────────────────────────────────────────────────────

final poiServiceProvider = Provider((_) => PoiService());

/// 현재 지도에 표시 중인 POI 목록 (스냅 후 업데이트)
final poiListProvider =
    NotifierProvider<_PoiListNotifier, List<Poi>>(_PoiListNotifier.new);

class _PoiListNotifier extends Notifier<List<Poi>> {
  @override
  List<Poi> build() => [];

  void set(List<Poi> pois) => state = pois;
  void clear() => state = [];
}

// ── Route type filter ─────────────────────────────────────────

enum RouteTypeFilter { country, provincial, national }

final routeTypeFilterProvider =
    NotifierProvider<_RouteTypeNotifier, RouteTypeFilter>(
        _RouteTypeNotifier.new);

class _RouteTypeNotifier extends Notifier<RouteTypeFilter> {
  @override
  RouteTypeFilter build() => RouteTypeFilter.national;

  void set(RouteTypeFilter t) => state = t;
}
