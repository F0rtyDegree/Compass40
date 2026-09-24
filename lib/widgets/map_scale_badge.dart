import 'package:flutter/material.dart';

/// Индикатор масштаба и расстояния до прицела в правом верхнем углу карты.
class MapScaleBadge extends StatelessWidget {
  final int totalCount;
  final int usedCount;
  final double? metersPerPx;
  final double? distanceMeters;

  const MapScaleBadge({
    super.key,
    required this.totalCount,
    required this.usedCount,
    required this.metersPerPx,
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

    double segmentWidth = 0;
    String scaleLabel = '';
    if (metersPerPx != null && metersPerPx! > 0) {
      final screenWidth = MediaQuery.of(context).size.width;
      final maxWidth = screenWidth * 0.4;
      const niceNumbers = [
        1, 2, 5, 10, 20, 50, 100, 150, 200, 250, 500, 1000, 2000, 5000,
      ];
      for (final num in niceNumbers) {
        final w = num / metersPerPx!;
        if (w <= maxWidth) {
          segmentWidth = w;
          scaleLabel = '$num м';
        } else {
          break;
        }
      }
      if (segmentWidth == 0) {
        segmentWidth = niceNumbers.last / metersPerPx!;
        scaleLabel = '${niceNumbers.last} м';
      }
    }

    final String topLeftDisplay = '📏';
    final String topRightDisplay = distanceMeters != null
        ? (distanceMeters! >= 1000
              ? '${(distanceMeters! / 1000).toStringAsFixed(1)} км'
              : '${distanceMeters!.round()} м')
        : '---';

    Widget topRowFullWidth = const SizedBox.shrink();
    if (metersPerPx != null && segmentWidth > 0) {
      topRowFullWidth = SizedBox(
        width: segmentWidth,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _shadowedText(topLeftDisplay, textColor),
            _shadowedText(topRightDisplay, textColor),
          ],
        ),
      );
    }

    Widget scaleWidget;
    if (metersPerPx != null && segmentWidth > 0) {
      scaleWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: topRowFullWidth,
          ),
          Container(
            width: segmentWidth,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(
                  color: Colors.white,
                  blurRadius: 4,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          SizedBox(
            width: segmentWidth,
            child: Text(
              scaleLabel,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.white, blurRadius: 2),
                  Shadow(color: Colors.white, blurRadius: 4),
                  Shadow(color: Colors.white, blurRadius: 6),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      scaleWidget = _shadowedText(topLeftDisplay, textColor);
    }

    return Tooltip(message: 'Масштабная линейка', child: scaleWidget);
  }

  Widget _shadowedText(String text, Color color) {
    return Text(
      text,
      style: TextStyle(
        color: color,
        fontSize: 16,
        fontWeight: FontWeight.bold,
        shadows: [
          Shadow(color: Colors.white, blurRadius: 2),
          Shadow(color: Colors.white, blurRadius: 4),
          Shadow(color: Colors.white, blurRadius: 6),
        ],
      ),
    );
  }
}