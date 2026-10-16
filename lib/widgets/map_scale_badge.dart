import 'package:flutter/material.dart';

/// Показывает расстояние от прицела до текущего положения пользователя.
class MapScaleBadge extends StatelessWidget {
  final int totalCount;
  final int usedCount;
  final double? distanceMeters;

  const MapScaleBadge({
    super.key,
    required this.totalCount,
    required this.usedCount,
    required this.distanceMeters,
  });

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) return const SizedBox.shrink();

    final Color textColor;
    if (totalCount >= 3) {
      textColor = Colors.green.shade900;
    } else if (totalCount == 2 && usedCount == 2) {
      textColor = Colors.orange.shade900;
    } else {
      textColor = Colors.red.shade900;
    }

    final String valueText = distanceMeters != null
        ? (distanceMeters! >= 1000
              ? '${(distanceMeters! / 1000).toStringAsFixed(1)} км'
              : '${distanceMeters!.round()} м')
        : '---';

    return Tooltip(
      message: 'Расстояние от прицела до текущего положения',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(77),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          '📏 $valueText',
          style: TextStyle(
            color: textColor,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}