import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/widgets/daylight_bar.dart';
import '../../map/providers/map_providers.dart';

const LatLng _kDefaultPos = LatLng(37.5665, 126.9780);

// ── Navigation palette ────────────────────────────────────────────────────────
const _kBg      = Color(0xFF0D0D0D);
const _kCard    = Color(0xFF1E1E1E);
const _kSurface = Color(0xFF242424);
const _kAccent  = Color(0xFF00B1F0); // YuruNavi tertiary (light blue)
const _kText    = Color(0xFFF0F0F0);
const _kSub     = Color(0xFF888888);

class NavScreen extends ConsumerStatefulWidget {
  final LatLng? destination;
  final List<LatLng> waypoints;
  final List<LatLng> routePolyline;

  const NavScreen({
    super.key,
    this.destination,
    this.waypoints = const [],
    this.routePolyline = const [],
  });

  @override
  ConsumerState<NavScreen> createState() => _NavScreenState();
}

class _NavScreenState extends ConsumerState<NavScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapCtrl = MapController();
  LatLng _currentPos = _kDefaultPos;
  double _speedKmh = 0;
  bool _isManualMode = false;
  Timer? _recenterTimer;
  Timer? _speedTimer;
  int _tick = 0;
  StreamSubscription<Position>? _locationSub;

  // Turn-by-turn demo steps
  final List<_TurnStep> _steps = const [
    _TurnStep(Icons.turn_right_rounded, '17m 후 우회전', '300m'),
    _TurnStep(Icons.straight_rounded,   '직진',         '1.2km'),
    _TurnStep(Icons.turn_left_rounded,  '좌회전',       '500m'),
    _TurnStep(Icons.flag_rounded,       '목적지 도착',  ''),
  ];
  int _stepIdx = 0;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ));
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
    _startLocation();
    _startSpeedSim();
  }

  @override
  void dispose() {
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarIconBrightness: Brightness.dark,
    ));
    _recenterTimer?.cancel();
    _speedTimer?.cancel();
    _locationSub?.cancel();
    _pulseCtrl.dispose();
    _mapCtrl.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) return;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;

    _locationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 5,
      ),
    ).listen((pos) {
      final loc = LatLng(pos.latitude, pos.longitude);
      ref.read(currentLocationProvider.notifier).set(loc);
      setState(() {
        _currentPos = loc;
        if (pos.speed > 0.5) _speedKmh = pos.speed * 3.6;
      });
      if (!_isManualMode) _recenter(loc);
    });
  }

  void _startSpeedSim() {
    _speedTimer = Timer.periodic(const Duration(milliseconds: 800), (_) {
      if (_speedKmh > 1) return;
      setState(() {
        _tick++;
        final phase = (_tick * 0.15) % (2 * 3.14159);
        final norm = phase.clamp(0.0, 3.14159);
        final wave = (norm < 1.57) ? norm / 1.57 : (3.14159 - norm) / 1.57;
        _speedKmh = (60 + 40 * wave).clamp(0.0, 120.0);
      });
    });
  }

  void _recenter(LatLng loc) => _mapCtrl.move(loc, 15.0);

  void _onMapGesture() {
    setState(() => _isManualMode = true);
    _recenterTimer?.cancel();
    _recenterTimer = Timer(const Duration(seconds: 10), () {
      setState(() => _isManualMode = false);
      _recenter(_currentPos);
    });
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_stepIdx];
    final daylightProgress = ref.watch(daylightProgressProvider);
    final daylightTimes = ref.watch(daylightTimesProvider);

    return Scaffold(
      backgroundColor: _kBg,
      body: Stack(
        children: [
          // ── 지도 ────────────────────────────────────────────────────────────
          FlutterMap(
            mapController: _mapCtrl,
            options: MapOptions(
              initialCenter: widget.destination ?? _currentPos,
              initialZoom: 15,
              onMapEvent: (event) {
                if (event is MapEventMoveStart && event.source != MapEventSource.mapController) {
                  _onMapGesture();
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.yurunavi.app',
                maxZoom: 19,
              ),
              // 야간 다크 오버레이
              ColorFiltered(
                colorFilter: ColorFilter.matrix([
                  -0.88, 0, 0, 0, 255,
                  0, -0.88, 0, 0, 255,
                  0, 0, -0.88, 0, 255,
                  0, 0, 0, 0.82, 0,
                ]),
                child: const SizedBox.expand(),
              ),
              // 경로 폴리라인
              if (widget.routePolyline.length >= 2)
                PolylineLayer(polylines: [
                  Polyline(
                    points: widget.routePolyline,
                    color: const Color(0xFFF28C28).withValues(alpha: 0.9),
                    strokeWidth: 4.5,
                    strokeCap: StrokeCap.round,
                    strokeJoin: StrokeJoin.round,
                  ),
                ]),

              MarkerLayer(markers: [
                // 현위치
                Marker(
                  point: _currentPos,
                  width: 24,
                  height: 24,
                  child: Container(
                    decoration: BoxDecoration(
                      color: _kAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 3),
                      boxShadow: [
                        BoxShadow(color: _kAccent.withValues(alpha: 0.5), blurRadius: 12),
                      ],
                    ),
                  ),
                ),
                // 경유지
                ...widget.waypoints.map(
                  (wp) => Marker(
                    point: wp,
                    width: 34,
                    height: 34,
                    alignment: Alignment.topCenter,
                    child: const Icon(
                      Icons.location_pin,
                      color: Color(0xFFFFB300),
                      size: 34,
                    ),
                  ),
                ),
                // 목적지
                if (widget.destination != null)
                  Marker(
                    point: widget.destination!,
                    width: 38,
                    height: 38,
                    alignment: Alignment.topCenter,
                    child: const Icon(Icons.location_pin, color: Colors.redAccent, size: 38),
                  ),
              ]),
            ],
          ),

          // ── 수동모드 복귀 알림 ──────────────────────────────────────────────
          if (_isManualMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 88,
              left: 60,
              right: 60,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.gps_fixed, color: _kAccent, size: 14),
                    SizedBox(width: 6),
                    Text('10초 후 현위치 복귀', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ],
                ),
              ),
            ),

          // ── 상단 회전 안내 ──────────────────────────────────────────────────
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: GestureDetector(
                onTap: () {
                  if (_stepIdx < _steps.length - 1) setState(() => _stepIdx++);
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        LinearProgressIndicator(
                          value: (_stepIdx + 1) / _steps.length,
                          backgroundColor: _kSurface,
                          color: _kAccent,
                          minHeight: 3,
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: 58,
                                height: 58,
                                decoration: BoxDecoration(
                                  color: _kAccent,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Icon(step.icon, color: Colors.white, size: 30),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (step.dist.isNotEmpty)
                                      Text(
                                        step.dist,
                                        style: const TextStyle(
                                          color: _kAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    Text(
                                      step.label,
                                      style: const TextStyle(
                                        color: _kText,
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── 좌측 속도계 ─────────────────────────────────────────────────────
          Positioned(
            left: 12,
            bottom: 110,
            child: ScaleTransition(
              scale: _pulseAnim,
              child: _Speedometer(speedKmh: _speedKmh),
            ),
          ),

          // ── 우측: Daylight + 컨트롤 ─────────────────────────────────────────
          Positioned(
            right: 12,
            top: 200,
            bottom: 110,
            child: Column(
              children: [
                Expanded(
                  child: DaylightBar(
                    progress: daylightProgress,
                    sunriseLabel: daylightTimes != null
                        ? DateFormat('HH:mm').format(daylightTimes.bmnt)
                        : '--:--',
                    sunsetLabel: daylightTimes != null
                        ? DateFormat('HH:mm').format(daylightTimes.eent)
                        : '--:--',
                  ),
                ),
                const SizedBox(height: 10),
                _NavIconBtn(
                  icon: _isManualMode ? Icons.gps_fixed : Icons.my_location,
                  onTap: () {
                    _recenterTimer?.cancel();
                    setState(() => _isManualMode = false);
                    _recenter(_currentPos);
                  },
                ),
              ],
            ),
          ),

          // ── 하단 ETA 바 ─────────────────────────────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: const BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '14:32 도착',
                              style: TextStyle(
                                color: _kText,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Row(
                              children: [
                                const Text('38분', style: TextStyle(color: _kAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                                const SizedBox(width: 8),
                                Text('23.4km', style: TextStyle(color: _kSub, fontSize: 14)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Container(width: 1, height: 40, color: _kSurface, margin: const EdgeInsets.symmetric(horizontal: 16)),
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.red.shade900.withValues(alpha: 0.8),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.close_rounded, color: Colors.white, size: 20),
                              SizedBox(height: 2),
                              Text('종료', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Speedometer extends StatelessWidget {
  final double speedKmh;
  const _Speedometer({required this.speedKmh});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _kCard,
        border: Border.all(color: _kAccent, width: 2.5),
        boxShadow: [BoxShadow(color: _kAccent.withValues(alpha: 0.25), blurRadius: 16)],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            speedKmh.toStringAsFixed(0),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: _kAccent, height: 1.0),
          ),
          const Text('km/h', style: TextStyle(fontSize: 10, color: _kSub)),
        ],
      ),
    );
  }
}

class _NavIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _NavIconBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _kCard,
          border: Border.all(color: _kSurface, width: 1),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 8)],
        ),
        child: Icon(icon, color: _kAccent, size: 20),
      ),
    );
  }
}

class _TurnStep {
  final IconData icon;
  final String label;
  final String dist;
  const _TurnStep(this.icon, this.label, this.dist);
}
