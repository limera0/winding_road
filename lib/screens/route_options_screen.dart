import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/saved_route.dart';
import '../providers/app_providers.dart';
import '../services/route_service.dart';

class RouteOptionsScreen extends ConsumerStatefulWidget {
  const RouteOptionsScreen({super.key});

  @override
  ConsumerState<RouteOptionsScreen> createState() =>
      _RouteOptionsScreenState();
}

class _RouteOptionsScreenState extends ConsumerState<RouteOptionsScreen> {
  RouteType _selectedType = RouteType.national;

  @override
  Widget build(BuildContext context) {
    final savedRoutes = ref.watch(savedRoutesProvider).value ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('경로 옵션'),
        backgroundColor: const Color(0xFF008080),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // ── 경로 타입 선택 ─────────────────────────────────
          const _SectionTitle(title: '경로 타입'),
          const SizedBox(height: 12),
          Row(
            children: RouteType.values.map((type) {
              final isSelected = _selectedType == type;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedType = type),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Color(type.colorValue)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected
                            ? Color(type.colorValue)
                            : Colors.grey.shade200,
                      ),
                      boxShadow: isSelected
                          ? [
                              BoxShadow(
                                color: Color(type.colorValue)
                                    .withValues(alpha: 0.35),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : [],
                    ),
                    child: Column(
                      children: [
                        Icon(
                          _typeIcon(type),
                          color: isSelected ? Colors.white : Colors.grey,
                          size: 26,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          type.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 12),

          // 선택된 타입 색상 미리보기 (지도 경로 색상)
          _ColorPreviewBar(type: _selectedType),

          const SizedBox(height: 28),

          // ── 코스 등록 버튼 ─────────────────────────────────
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF008080),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () => _registerDummyCourse(context),
            icon: const Icon(Icons.add_road),
            label: const Text('현재 코스 등록', style: TextStyle(fontSize: 16)),
          ),

          const SizedBox(height: 28),

          // ── 저장된 코스 목록 ───────────────────────────────
          const _SectionTitle(title: '저장된 코스'),
          const SizedBox(height: 12),

          if (savedRoutes.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Text('저장된 코스가 없습니다',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...savedRoutes.map((route) => _RouteCard(
                  route: route,
                  onDelete: () =>
                      ref.read(savedRoutesProvider.notifier).remove(route.id),
                )),
        ],
      ),
    );
  }

  IconData _typeIcon(RouteType type) {
    switch (type) {
      case RouteType.country:
        return Icons.park_outlined;
      case RouteType.provincial:
        return Icons.alt_route;
      case RouteType.national:
        return Icons.add_road;
    }
  }

  /// 더미 코스를 생성하고 중복 검사 후 등록
  Future<void> _registerDummyCourse(BuildContext context) async {
    final rng = Random();
    // 현재 위치 기준 임의 경로 생성
    final points = List.generate(
      20,
      (i) => RoutePoint(
        37.5665 + (rng.nextDouble() - 0.5) * 0.3,
        126.9780 + (rng.nextDouble() - 0.5) * 0.3,
      ),
    );

    final candidate = SavedRoute(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: '코스 ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
      points: points,
      type: _selectedType,
      savedAt: DateTime.now(),
      distanceKm: 25 + rng.nextDouble() * 50,
    );

    // 중복 검사 (70% 이상 유사 경고)
    final savedRoutes = ref.read(savedRoutesProvider).value ?? [];
    final similar = RouteService.findSimilar(candidate, savedRoutes);

    if (similar.isNotEmpty && context.mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => _DuplicateWarningDialog(similar: similar),
      );
      if (proceed != true) return;
    }

    await ref.read(savedRoutesProvider.notifier).add(candidate);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '"${candidate.name}" 코스가 저장되었습니다 (${_selectedType.label})'),
          backgroundColor: const Color(0xFF008080),
        ),
      );
    }
  }
}

// ── 색상 미리보기 바 ──────────────────────────────────────────

class _ColorPreviewBar extends StatelessWidget {
  final RouteType type;
  const _ColorPreviewBar({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 8,
      decoration: BoxDecoration(
        color: Color(type.colorValue),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

// ── 저장 코스 카드 ────────────────────────────────────────────

class _RouteCard extends StatelessWidget {
  final SavedRoute route;
  final VoidCallback onDelete;

  const _RouteCard({required this.route, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 44,
            decoration: BoxDecoration(
              color: Color(route.type.colorValue),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  route.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Text(
                  '${route.type.label} · ${route.distanceKm.toStringAsFixed(1)} km',
                  style:
                      const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onDelete,
            child:
                Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
          ),
        ],
      ),
    );
  }
}

// ── 중복 경고 다이얼로그 ──────────────────────────────────────

class _DuplicateWarningDialog extends StatelessWidget {
  final List<({SavedRoute route, double sim})> similar;

  const _DuplicateWarningDialog({required this.similar});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: Colors.orange.shade600, size: 26),
          const SizedBox(width: 8),
          const Text('유사한 코스 감지'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '이미 저장된 코스와 경로가 70% 이상 겹칩니다.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          ...similar.take(3).map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    const Icon(Icons.route, size: 14, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        s.route.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${(s.sim * 100).toStringAsFixed(0)}% 유사',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF008080),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('그래도 저장'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: Color(0xFF333333)),
    );
  }
}
