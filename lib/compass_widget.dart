import 'dart:math' as math;
import 'package:flutter/material.dart';

// The main compass widget that brings everything together.
class CompassWidget extends StatelessWidget {
  final double heading;
  final double? targetAzimuth;
  final double? bearingToWaypoint;

  const CompassWidget({
    super.key,
    required this.heading,
    this.targetAzimuth,
    this.bearingToWaypoint,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Transform.rotate(
          angle: -heading * (math.pi / 180),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The main compass rose
              SizedBox(
                width: 275,
                height: 275,
                child: CustomPaint(
                  painter: _WindRosePainter(
                    isDarkMode: Theme.of(context).brightness == Brightness.dark,
                    heading: heading,
                  ),
                ),
              ),
              // The target pointer (blue)
              if (targetAzimuth != null)
                Transform.rotate(
                  angle: targetAzimuth! * (math.pi / 180),
                  child: SizedBox(
                    width: 275,
                    height: 275,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 22.0),
                        child: CustomPaint(
                          size: const Size(12, 22),
                          painter: _TargetPainter(),
                        ),
                      ),
                    ),
                  ),
                ),
              // The waypoint pointer (orange)
              if (bearingToWaypoint != null)
                Transform.rotate(
                  angle: bearingToWaypoint! * (math.pi / 180),
                  child: SizedBox(
                    width: 275,
                    height: 275,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 22.0),
                        child: CustomPaint(
                          size: const Size(12, 22),
                          painter: _WaypointPainter(),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // The heading text in the center
        Text(
          '${heading.round()}°',
          style: const TextStyle(fontSize: 60, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// Painter for the target indicator (the blue triangle).
class _TargetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.blueAccent
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withAlpha(179)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(size.width / 2, 0); // Top point
    path.lineTo(0, size.height); // Bottom-left
    path.lineTo(size.width, size.height); // Bottom-right
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint); // Draw border over the fill
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Painter for the waypoint indicator (the orange triangle).
class _WaypointPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..color = Colors.orange
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.black.withAlpha(179)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final path = Path();
    path.moveTo(size.width / 2, 0); // Top point
    path.lineTo(0, size.height); // Bottom-left
    path.lineTo(size.width, size.height); // Bottom-right
    path.close();

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, borderPaint); // Draw border over the fill
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Painter for the main compass rose background.
class _WindRosePainter extends CustomPainter {
  final bool isDarkMode;
  final double heading;
  _WindRosePainter({this.isDarkMode = false, this.heading = 0.0});

  @override
  void paint(Canvas canvas, Size size) {
    const double strokeWidth = 22.0;
    final double radius = size.width / 2 - strokeWidth / 2;
    final Offset center = Offset(size.width / 2, size.height / 2);

    final List<Color> colors = [
      Colors.red, // N
      Colors.green, // NE
      Colors.yellow, // E
      Colors.cyan, // SE
      Colors.red, // S
      Colors.green, // SW
      Colors.yellow, // W
      Colors.cyan, // NW
    ];

    final Paint paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    const double majorSectorAngle = math.pi / 4; // 45 degrees

    for (int i = 0; i < 8; i++) {
      paint.color = colors[i];
      final double startAngle = -math.pi / 2 - majorSectorAngle / 2 + i * majorSectorAngle;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        majorSectorAngle,
        false,
        paint,
      );
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const double subSectorAngle = math.pi / 12; // 15 degrees

    for (int i = 0; i < 8; i++) {
      final sectorColor = colors[i];
      final lineLuminance = sectorColor.computeLuminance();
      linePaint.color = lineLuminance > 0.5 ? Colors.black.withAlpha(128) : Colors.white.withAlpha(128);
      
      final double majorSectorStart = -math.pi / 2 - majorSectorAngle / 2 + i * majorSectorAngle;

      final double line1Angle = majorSectorStart + subSectorAngle;
      final double line2Angle = majorSectorStart + 2 * subSectorAngle;

      void drawLineAtAngle(double angle) {
        final Offset startPoint = Offset(
          center.dx + (radius - strokeWidth / 2) * math.cos(angle),
          center.dy + (radius - strokeWidth / 2) * math.sin(angle),
        );
        final Offset endPoint = Offset(
          center.dx + (radius + strokeWidth / 2) * math.cos(angle),
          center.dy + (radius + strokeWidth / 2) * math.sin(angle),
        );
        canvas.drawLine(startPoint, endPoint, linePaint);
      }
      
      drawLineAtAngle(line1Angle);
      drawLineAtAngle(line2Angle);
    }
    
    final cardinalPoints = {
      0: 'С', // N
      2: 'В', // E
      4: 'Ю', // S
      6: 'З', // W
    };

    for (var entry in cardinalPoints.entries) {
      final i = entry.key;
      final letter = entry.value;
      final sectorColor = colors[i];
      final letterLuminance = sectorColor.computeLuminance();
      final textColor = letterLuminance > 0.5 ? Colors.black : Colors.white;

      final textStyle = TextStyle(
        color: textColor,
        fontSize: 14,
        fontWeight: FontWeight.bold,
      );

      final textSpan = TextSpan(text: letter, style: textStyle);
      final textPainter = TextPainter(text: textSpan, textDirection: TextDirection.ltr);
      textPainter.layout();

      final double letterAngleOnRose = -math.pi / 2 + i * majorSectorAngle;

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(letterAngleOnRose);
      canvas.translate(radius, 0);
      canvas.rotate(-letterAngleOnRose);
      canvas.rotate(heading * math.pi / 180);
      textPainter.paint(canvas, Offset(-textPainter.width / 2, -textPainter.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _WindRosePainter oldDelegate) {
     if (oldDelegate.isDarkMode != isDarkMode || 
         oldDelegate.heading != heading) {
      return true;
    }
    return false;
  }
}
