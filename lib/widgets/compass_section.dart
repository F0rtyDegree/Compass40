import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../log_entry.dart';
import '../widgets/compass_painters.dart';

class CompassSection extends StatelessWidget {
  final ValueNotifier<double> headingNotifier;
  final ValueNotifier<double> accuracyNotifier;
  final ValueNotifier<double?> bearingToTarget;
  final ValueNotifier<double?> bearingToWaypoint;
  final List<LogItem> logItems;
  final Function() setWaypoint;
  final Function() clearWaypoint;
  final Function(DragEndDetails) onVerticalDragEnd;
  final String Function(double) getCardinalDirection;
  final Color Function(double) getAccuracyStatusColor;
  final String Function(double) getAccuracyText;



  const CompassSection({
    super.key,
    required this.headingNotifier,
    required this.accuracyNotifier,
    required this.bearingToTarget,
    required this.bearingToWaypoint,
    required this.logItems,
    required this.setWaypoint,
    required this.clearWaypoint,
    required this.onVerticalDragEnd,
    required this.getCardinalDirection,
    required this.getAccuracyStatusColor,
    required this.getAccuracyText,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: setWaypoint,
      onVerticalDragEnd: onVerticalDragEnd,
      child: ValueListenableBuilder<double>(
        valueListenable: headingNotifier,
        builder: (context, heading, child) {
          final roseRotation = -heading * math.pi / 180;
          final textColor = Theme.of(context).brightness == Brightness.dark
              ? Colors.grey[400]
              : Colors.grey[700];
          return Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CustomPaint(painter: UprightTrianglePainter(color: Colors.blue)),
                ),
                const SizedBox(height: 4),
                Text(
                  getCardinalDirection(heading),
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: textColor),
                ),
                const SizedBox(height: 4),
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CustomPaint(painter: DownwardTrianglePainter(color: Colors.blue)),
                ),
                Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.rotate(
                      angle: roseRotation,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 275,
                            height: 275,
                            child: CustomPaint(
                              painter: WindRosePainter(
                                isDarkMode: Theme.of(context).brightness == Brightness.dark,
                                heading: heading,
                              ),
                            ),
                          ),
                          _buildTargetArrow(),
                          _buildWaypointArrow(),
                        ],
                      ),
                    ),
                    Text(
                      '${heading.round()}°',
                      style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
                    ),
                    Positioned(
                      bottom: 60,
                      child: ValueListenableBuilder<double>(
                        valueListenable: accuracyNotifier,
                        builder: (context, acc, _) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield_outlined,
                                color: getAccuracyStatusColor(acc), size: 28),
                            Text(getAccuracyText(acc),
                                style: TextStyle(
                                    color: getAccuracyStatusColor(acc), fontSize: 10)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildTargetArrow() {
    return ValueListenableBuilder<double?>(
      valueListenable: bearingToTarget,
      builder: (c, b, _) {
        if (b == null) return const SizedBox.shrink();
        return Transform.rotate(
          angle: b * math.pi / 180,
          child: SizedBox(
            width: 275,
            height: 275,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: CustomPaint(size: const Size(12, 22), painter: TargetPainter()),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildWaypointArrow() {
    return ValueListenableBuilder<double?>(
      valueListenable: bearingToWaypoint,
      builder: (c, b, _) {
        if (b == null) return const SizedBox.shrink();
        return Transform.rotate(
          angle: b * math.pi / 180,
          child: SizedBox(
            width: 275,
            height: 275,
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: CustomPaint(size: const Size(12, 22), painter: WaypointPainter()),
              ),
            ),
          ),
        );
      },
    );
  }
}
