import 'package:flutter/material.dart';

/// 우측 세로 Daylight 인디케이터 바
/// [progress] 0.0(BMNT) ~ 1.0(EENT), 현재 태양 위치
class DaylightBar extends StatelessWidget {
  final double progress; // 0.0 ~ 1.0
  final String bmntLabel;
  final String eentLabel;

  const DaylightBar({
    super.key,
    required this.progress,
    required this.bmntLabel,
    required this.eentLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── BMNT (일출) ──────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Column(
              children: [
                const Icon(Icons.wb_sunny, size: 14, color: Colors.orange),
                Text(
                  bmntLabel,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.orange,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),

          // ── 그래프 바 + 썬 마커 ──────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalH = constraints.maxHeight;
                  final sunY = totalH * progress.clamp(0.0, 1.0);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 배경 그라디언트
                      Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFD54F), // 낮
                              Color(0xFF90CAF9), // 황혼
                              Color(0xFF1A237E), // 밤
                            ],
                          ),
                        ),
                      ),
                      // 현재 위치 마커
                      Positioned(
                        top: sunY - 6,
                        left: -3,
                        right: -3,
                        child: Container(
                          height: 12,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color: Colors.orange.shade400, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.4),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // ── EENT (일몰) ──────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              children: [
                Text(
                  eentLabel,
                  style: const TextStyle(
                    fontSize: 7,
                    color: Colors.blueGrey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Icon(Icons.nightlight_round,
                    size: 14, color: Colors.blueGrey),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
