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
      textColor = Colors.green;
    } else if (totalCount == 2 && usedCount == 2) {
      textColor = Colors.orange;
    } else {
      textColor = Colors.red;
    }

    final String valueText = distanceMeters != null
        ? (distanceMeters! >= 1000
              ? '${(distanceMeters! / 1000).toStringAsFixed(1)} км'
              : '${distanceMeters!.round()} м')
        : '---';

    return Tooltip(
      message: 'Расстояние от прицела до текущего положения',
      child: Text(
        '📏 $valueText',
        style: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.white, blurRadius: 2),
            Shadow(color: Colors.white, blurRadius: 4),
            Shadow(color: Colors.white, blurRadius: 6),
          ],
        ),
      ),
    );
  }
}