import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:slider_button/slider_button.dart';
import 'package:vibration/vibration.dart';

class SliderStartButton extends StatelessWidget {
  final VoidCallback onSlideComplete;

  const SliderStartButton({super.key, required this.onSlideComplete});

  Future<void> _triggerHaptic() async {
    // 1차: Flutter 내장 햅틱 (모든 플랫폼)
    await HapticFeedback.heavyImpact();
    // 2차: vibration 패키지 (Android 진동 강도 제어)
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(
        pattern: [0, 80, 60, 120],
        intensities: [0, 200, 0, 255],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: SliderButton(
        action: () async {
          await _triggerHaptic();
          onSlideComplete();
          return true;
        },
        label: const Text(
          'Start your Engine',
          style: TextStyle(
            color: Color(0xFF004D4D),
            fontWeight: FontWeight.bold,
            fontSize: 16,
            letterSpacing: 0.8,
          ),
        ),
        icon: const Center(
          child: Icon(
            Icons.chevron_right,
            color: Colors.white,
            size: 28,
          ),
        ),
        width: double.infinity,
        radius: 16,
        buttonColor: const Color(0xFF008080),
        backgroundColor: const Color(0xFFD0F0EE),
        highlightedColor: const Color(0xFFB2E5E2),
        baseColor: const Color(0xFF008080),
        buttonSize: 56,
        shimmer: true,
      ),
    );
  }
}
