import 'dart:async';
import 'dart:math' show cos, sqrt, asin;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../models/poi.dart';
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

// ── 간단한 클러스터 그리드 셀 ────────────────────────────────────

class _ClusterCell {
  final List<Poi> pois;
  _ClusterCell(this.pois);

  Poi get representative => pois.first;
  int get count => pois.length;
  LatLng get center {
    final lat = pois.map((p) => p.location.latitude).reduce((a, b) => a + b) / pois.length;
    final lng = pois.map((p) => p.location.longitude).reduce((a, b) => a + b) / pois.length;
    return LatLng(lat, lng);
  }
}

/// 그리드 기반 간단 클러스터: zoom이 낮을수록 더 많이 뭉친다.
List<_ClusterCell> _clusterPois(List<Poi> pois, double zoom) {
  final cellSize = zoom >= 14 ? 0.005 : zoom >= 12 ? 0.015 : 0.04;
  final Map<String, List<Poi>> grid = {};
  for (final p in pois) {
    final row = (p.location.latitude / cellSize).floor();
    final col = (p.location.longitude / cellSize).floor();
    final key = '$row:$col:${p.type.name}';
    grid.putIfAbsent(key, () => []).add(p);
  }
  return grid.values.map((ps) => _ClusterCell(ps)).toList();
}

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
  bool _isSnapping = false;
  double _currentZoom = 11;

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
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
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

  double _haversineKm(LatLng a, LatLng b) {
    const double toRad = 0.017453292519943295;
    final dLat = (b.latitude - a.latitude) * toRad;
    final dLon = (b.longitude - a.longitude) * toRad;
    final sinHLat = dLat / 2;
    final sinHLon = dLon / 2;
    final h = (sinHLat * sinHLat) +
        cos(a.latitude * toRad) * cos(b.latitude * toRad) * (sinHLon * sinHLon);
    return 12742 * asin(sqrt(h));
  }

  // ── 오모테나시 스냅 로직 ─────────────────────────────────────────

  Future<void> _onMapTap(TapPosition _, LatLng tapped) async {
    if (_isSnapping) return;
    setState(() => _isSnapping = true);

    final poiSvc = ref.read(poiServiceProvider);

    try {
      final result = await poiSvc.snapDestination(
        origin: _origin,
        tapped: tapped,
        radiusKm: 1.0,
      );

      ref.read(poiListProvider.notifier).set(result.allPois);

      if (result.snappedPoi != null) {
        _applyDestination(result.snappedPoi!.location);
        _showSnapToast(result.snappedPoi!);
      } else {
        // 카페/편의점 없음 → 팝업
        final expand = await _showNoPoiDialog();
        if (!mounted) return;

        if (expand == true) {
          // 범위 3km로 재탐색
          final result3 = await poiSvc.snapDestination(
            origin: _origin,
            tapped: tapped,
            radiusKm: 3.0,
          );
          ref.read(poiListProvider.notifier).set(result3.allPois);
          if (result3.snappedPoi != null) {
            _applyDestination(result3.snappedPoi!.location);
            _showSnapToast(result3.snappedPoi!);
          } else {
            _applyDestination(tapped);
          }
        } else {
          // "이대로" → 터치 위치 그대로 사용
          _applyDestination(tapped);
        }
      }
    } finally {
      if (mounted) setState(() => _isSnapping = false);
    }
  }

  void _applyDestination(LatLng dest) {
    final dist = _haversineKm(_origin, dest);
    setState(() => _distanceKm = dist);
    ref.read(destinationProvider.notifier).set(dest);

    final sw = LatLng(
      _origin.latitude < dest.latitude ? _origin.latitude : dest.latitude,
      _origin.longitude < dest.longitude ? _origin.longitude : dest.longitude,
    );
    final ne = LatLng(
      _origin.latitude > dest.latitude ? _origin.latitude : dest.latitude,
      _origin.longitude > dest.longitude ? _origin.longitude : dest.longitude,
    );
    _mapCtrl.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds(sw, ne),
        padding: const EdgeInsets.all(60),
      ),
    );
  }

  void _showSnapToast(Poi poi) {
    final msg = poi.type == PoiType.cafe
        ? '근처의 좋은 카페로 목적지를 안내합니다. 커피 한 잔 어떠세요?'
        : '근처의 편의점으로 목적지를 안내합니다. 잠깐 쉬어가세요!';

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              poi.type == PoiType.cafe ? Icons.local_cafe : Icons.store,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 13),
              ),
            ),
          ],
        ),
        backgroundColor: Color(poi.type.colorValue),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 100),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  /// 팝업 반환값: true = 찾아보기(3km 재탐색), false/null = 이대로
  Future<bool?> _showNoPoiDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.search_off, color: Color(0xFF008080)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                '쉴 곳을 못 찾았어요',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          '목적지 인근에 쉴 만한 장소가 없습니다.\n조금 범위를 넓혀서 찾아볼까요?',
          style: TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('이대로', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('찾아보기', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _navigateToDriving() {
    final dest = ref.read(destinationProvider);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DrivingScreen(destination: dest)),
    );
  }

  // ── POI 마커 빌더 ────────────────────────────────────────────

  List<Marker> _buildPoiMarkers(List<Poi> pois) {
    final clusters = _clusterPois(pois, _currentZoom);
    return clusters.map((cell) {
      final color = Color(cell.representative.type.colorValue);
      return Marker(
        point: cell.center,
        width: cell.count > 1 ? 36 : 22,
        height: cell.count > 1 ? 36 : 22,
        child: Tooltip(
          message: cell.count > 1
              ? '${cell.representative.type.label} 외 ${cell.count - 1}곳'
              : '${cell.representative.type.label}: ${cell.representative.name}',
          child: cell.count > 1
              ? _ClusterDot(color: color, count: cell.count)
              : _PoiDot(color: color),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final dest = ref.watch(destinationProvider);
    final daylightProgress = ref.watch(daylightProgressProvider);
    final daylightTimes = ref.watch(daylightTimesProvider);
    final profile = ref.watch(userProfileProvider).value ?? UserProfile.empty;
    final pois = ref.watch(poiListProvider);

    return Scaffold(
      body: Stack(
        children: [
          // ── OSM 지도 ──────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: _origin,
              initialZoom: _currentZoom,
              onTap: _onMapTap,
              onMapEvent: (event) {
                if (event is MapEventMoveEnd) {
                  setState(() => _currentZoom = _mapCtrl.camera.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.windingroad.app',
                maxZoom: 19,
              ),
              // POI 마커 (클러스터링 적용)
              if (pois.isNotEmpty)
                MarkerLayer(markers: _buildPoiMarkers(pois)),
              // 현재 위치 + 목적지 마커
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
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF008080).withValues(alpha: 0.4),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (dest != null)
                    Marker(
                      point: dest,
                      width: 36,
                      height: 36,
                      alignment: Alignment.topCenter,
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 36),
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
                      borderColor: const Color(0xFF008080).withValues(alpha: 0.4),
                      borderStrokeWidth: 1.5,
                    ),
                  ],
                ),
            ],
          ),

          // ── 스냅 중 로딩 인디케이터 ───────────────────────────
          if (_isSnapping)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.12),
                child: const Center(
                  child: Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF008080),
                            ),
                          ),
                          SizedBox(width: 14),
                          Text('좋은 장소를 찾고 있어요…',
                              style: TextStyle(fontSize: 14)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

          // ── 상단 바 ───────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => setState(() => _showProfileCard = !_showProfileCard),
                      child: _TopCard(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircleAvatar(
                              radius: 14,
                              backgroundColor: Color(0xFF008080),
                              child: Icon(Icons.person, size: 16, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              profile.nickname.isEmpty ? 'WR' : profile.nickname,
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
                        MaterialPageRoute(builder: (_) => const RouteOptionsScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _TopIconButton(icon: Icons.history, onTap: () {}),
                    const SizedBox(width: 8),
                    _TopIconButton(icon: Icons.bookmark_outline, onTap: () {}),
                    const SizedBox(width: 8),
                    _TopIconButton(
                      icon: Icons.settings_outlined,
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const ProfileScreen()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── 플로팅 프로필 카드 ─────────────────────────────────
          if (_showProfileCard)
            Positioned(
              top: 110,
              left: 16,
              child: FloatingProfileCard(
                profile: profile,
                onClose: () => setState(() => _showProfileCard = false),
              ),
            ),

          // ── 직선거리 오버레이 ──────────────────────────────────
          if (dest != null)
            Positioned(
              top: 120,
              left: 0,
              right: 0,
              child: DistanceOverlay(distanceKm: _distanceKm),
            ),

          // ── POI 범례 (POI 표시 중일 때) ───────────────────────
          if (pois.isNotEmpty)
            Positioned(
              bottom: 230,
              left: 16,
              child: _PoiLegend(pois: pois),
            ),

          // ── 우측 Daylight 바 ──────────────────────────────────
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

          // ── 우측 하단: 주행 버튼 ──────────────────────────────
          Positioned(
            right: 16,
            bottom: 220,
            child: FloatingActionButton(
              heroTag: 'drive_fab',
              backgroundColor: const Color(0xFF008080),
              onPressed: _navigateToDriving,
              child: const Icon(Icons.navigation, color: Colors.white),
            ),
          ),

          // ── 하단 슬라이더 영역 ────────────────────────────────
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
                  BoxShadow(color: Colors.black12, blurRadius: 16, offset: Offset(0, -4)),
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
                      child: Text('광고 영역', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ),
                  ),
                  SliderStartButton(onSlideComplete: _navigateToDriving),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── POI 마커 위젯 ──────────────────────────────────────────────

class _PoiDot extends StatelessWidget {
  final Color color;
  const _PoiDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.5),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 4)],
      ),
    );
  }
}

class _ClusterDot extends StatelessWidget {
  final Color color;
  final int count;
  const _ClusterDot({required this.color, required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.85),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6)],
      ),
      alignment: Alignment.center,
      child: Text(
        '$count',
        style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── POI 범례 위젯 ──────────────────────────────────────────────

class _PoiLegend extends StatelessWidget {
  final List<Poi> pois;
  const _PoiLegend({required this.pois});

  @override
  Widget build(BuildContext context) {
    final presentTypes = pois.map((p) => p.type).toSet().toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: presentTypes.map((type) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(type.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(type.label, style: const TextStyle(fontSize: 11)),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── 보조 위젯 ──────────────────────────────────────────────────

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
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 2)),
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
            BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF444444)),
      ),
    );
  }
}
