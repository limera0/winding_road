import 'dart:async';
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/user_profile.dart';
import '../providers/app_providers.dart';
import '../widgets/daylight_bar.dart';
import '../widgets/distance_overlay.dart';
import '../widgets/floating_profile_card.dart';
import '../widgets/slider_start_button.dart';
import 'driving_screen.dart';
import 'profile_screen.dart';
import 'route_options_screen.dart';

const LatLng kDefaultOrigin = LatLng(37.5665, 126.9780);

class MainMapScreen extends ConsumerStatefulWidget {
  const MainMapScreen({super.key});

  @override
  ConsumerState<MainMapScreen> createState() => _MainMapScreenState();
}

class _MainMapScreenState extends ConsumerState<MainMapScreen> {
  final MapController _mapCtrl = MapController();
  LatLng _origin = kDefaultOrigin;
  double _distanceKm = 0;
  bool _showProfileCard = false;
  StreamSubscription<Position>? _locationSub;

  @override
  void initState() {
    super.initState();
    _startLocationTracking();
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLocationTracking() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      ref.read(currentLocationProvider.notifier).set(loc);
      setState(() => _origin = loc);
    });
  }

  double _haversine(LatLng a, LatLng b) {
    const double toRad = 0.017453292519943295;
    final dLat = (b.latitude - a.latitude) * toRad;
    final dLon = (b.longitude - a.longitude) * toRad;
    final sinHalfLat = dLat / 2;
    final sinHalfLon = dLon / 2;
    final h = (sinHalfLat * sinHalfLat) +
        cos(a.latitude * toRad) *
            cos(b.latitude * toRad) *
            (sinHalfLon * sinHalfLon);
    return 12742 * asin(sqrt(h));
  }

  void _onMapTap(TapPosition _, LatLng tapped) {
    final dist = _haversine(_origin, tapped);
    setState(() => _distanceKm = dist);
    ref.read(destinationProvider.notifier).set(tapped);

    // autofit: 내 위치 + 목적지 모두 보이도록
    final sw = LatLng(
      _origin.latitude < tapped.latitude ? _origin.latitude : tapped.latitude,
      _origin.longitude < tapped.longitude
          ? _origin.longitude
          : tapped.longitude,
    );
    final ne = LatLng(
      _origin.latitude > tapped.latitude ? _origin.latitude : tapped.latitude,
      _origin.longitude > tapped.longitude
          ? _origin.longitude
          : tapped.longitude,
    );
    final bounds = LatLngBounds(sw, ne);
    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  void _navigateToDriving() {
    final dest = ref.read(destinationProvider);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DrivingScreen(destination: dest),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dest = ref.watch(destinationProvider);
    final daylightProgress = ref.watch(daylightProgressProvider);
    final daylightTimes = ref.watch(daylightTimesProvider);
    final profile =
        ref.watch(userProfileProvider).value ?? UserProfile.empty;

    return Scaffold(
      body: Stack(
        children: [
          // ── OSM 지도 ──────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _origin,
              initialZoom: 11,
              onTap: _onMapTap,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.windingroad.app',
                maxZoom: 19,
              ),
              // 현재 위치 마커
              MarkerLayer(
                markers: [
                  Marker(
                    point: _origin,
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF008080),
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF008080)
                                .withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // 목적지 핀
                  if (dest != null)
                    Marker(
                      point: dest,
                      width: 36,
                      height: 36,
                      alignment: Alignment.topCenter,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 36,
                      ),
                    ),
                ],
              ),
              // 직선거리 원
              if (dest != null)
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _origin,
                      radius: _distanceKm * 1000,
                      useRadiusInMeter: true,
                      color: const Color(0xFF008080).withValues(alpha: 0.06),
                      borderColor:
                          const Color(0xFF008080).withValues(alpha: 0.4),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
            ],
          ),

          // ── 상단 바 ───────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(
                          () => _showProfileCard = !_showProfileCard),
                      child: _TopCard(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFF008080),
                              child: Icon(Icons.person,
                                  size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              profile.nickname.isEmpty
                                  ? 'WR'
                                  : profile.nickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: Color(0xFF008080),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    _TopIconButton(
                      icon: Icons.add_road,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const RouteOptionsScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TopIconButton(icon: Icons.history, onTap: () {}),
                    const SizedBox(width: 8),
                    _TopIconButton(
                        icon: Icons.bookmark_outline, onTap: () {}),
                    const SizedBox(width: 8),
                    _TopIconButton(
                      icon: Icons.settings_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const ProfileScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 플로팅 프로필 카드 ─────────────────────────────
          if (_showProfileCard)
            Positioned(
              top: 110,
              left: 16,
              child: FloatingProfileCard(
                profile: profile,
                onClose: () =>
                    setState(() => _showProfileCard = false),
              ),
            ),

          // ── 직선거리 오버레이 ────────────────────────────
          if (dest != null)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: DistanceOverlay(distanceKm: _distanceKm),
            ),

          // ── 우측 Daylight 바 ──────────────────────────────
          Positioned(
            right: 16,
            top: 180,
            bottom: 220,
            child: DaylightBar(
              progress: daylightProgress,
              bmntLabel: daylightTimes != null
                  ? DateFormat('HH:mm').format(daylightTimes.bmnt)
                  : '--:--',
              eentLabel: daylightTimes != null
                  ? DateFormat('HH:mm').format(daylightTimes.eent)
                  : '--:--',
            ),
          ),

          // ── 우측 하단: 주행 버튼 ──────────────────────────
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              heroTag: 'drive_fab',
              backgroundColor: const Color(0xFF008080),
              onPressed: _navigateToDriving,
              child:
                  const Icon(Icons.navigation, color: Colors.white),
            ),
          ),

          // ── 하단 슬라이더 영역 ────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 16,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 48,
                    margin: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: const Center(
                      child: Text(
                        '광고 영역',
                        style: TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ),
                  ),
                  SliderStartButton(
                      onSlideComplete: _navigateToDriving),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 보조 위젯 ─────────────────────────────────────────────────

class _TopCard extends StatelessWidget {
  final Widget child;
  const _TopCard({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _TopIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF444444)),
      ),
    );
  }
}
