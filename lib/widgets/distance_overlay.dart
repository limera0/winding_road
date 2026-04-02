import 'package:flutter/material.dart';

class DistanceOverlay extends StatelessWidget {
  final double distanceKm;

  const DistanceOverlay({super.key, required this.distanceKm});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: const Color(0xFF008080), width: 2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.straighten,
                color: Color(0xFF008080), size: 20),
            const SizedBox(width: 8),
            Text(
              '${distanceKm.toStringAsFixed(0)} km',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF008080),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
