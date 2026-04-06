import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 우측 세로 Daylight 인디케이터
/// 와이어프레임: 일출(태양 아이콘) ~ 일몰(달 아이콘) 그라디언트 게이지,
///              현재 시간 위치에 주황색 원형 핸들 표시
class DaylightBar extends StatelessWidget {
  final double progress; // 0.0(일출) ~ 1.0(일몰)
  final String sunriseLabel;
  final String sunsetLabel;

  const DaylightBar({
    super.key,
    required this.progress,
    required this.sunriseLabel,
    required this.sunsetLabel,
  });

  // Legacy named params compatibility
  factory DaylightBar.legacy({
    Key? key,
    required double progress,
    required String bmntLabel,
    required String eentLabel,
  }) =>
      DaylightBar(
        key: key,
        progress: progress,
        sunriseLabel: bmntLabel,
        sunsetLabel: eentLabel,
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 38,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(19),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── 일출 라벨 + 아이콘 ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                Icon(Icons.wb_sunny_rounded, size: 18, color: AppColors.sunrise),
                const SizedBox(height: 2),
                Text(
                  sunriseLabel,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: AppColors.sunrise,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── 게이지 바 ────────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalH = constraints.maxHeight;
                  final handleY =
                      (totalH * progress.clamp(0.0, 1.0)) - 8;

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 그라디언트 트랙
                      Container(
                        width: 6,
                        height: totalH,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(3),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFD54F), // 일출 황금
                              Color(0xFFFFB300), // 정오
                              Color(0xFF90CAF9), // 황혼 파랑
                              Color(0xFF1A237E), // 일몰 심야
                            ],
                            stops: [0.0, 0.45, 0.75, 1.0],
                          ),
                        ),
                      ),

                      // 현재 위치 핸들
                      Positioned(
                        top: handleY,
                        left: -5,
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primary,
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.4),
                                blurRadius: 6,
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

          const SizedBox(height: 8),

          // ── 일몰 라벨 + 아이콘 ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              children: [
                Text(
                  sunsetLabel,
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w700,
                    color: AppColors.sunset,
                  ),
                ),
                const SizedBox(height: 2),
                Icon(Icons.nightlight_round, size: 18, color: AppColors.sunset),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
