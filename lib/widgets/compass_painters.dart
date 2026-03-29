import 'dart:math' as math;
import 'package:flutter/material.dart';

class TargetPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.blueAccent..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.black.withAlpha(178)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(_) => false;
}

class WaypointPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = Colors.orange..style = PaintingStyle.fill;
    final border = Paint()
      ..color = Colors.black.withAlpha(178)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final path = Path()
      ..moveTo(size.width / 2, 0)
      ..lineTo(0, size.height)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, fill);
    canvas.drawPath(path, border);
  }

  @override
  bool shouldRepaint(_) => false;
}

class WindRosePainter extends CustomPainter {
  final bool isDarkMode;
  final double heading;
  WindRosePainter({required this.isDarkMode, required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 22.0;
    final radius = size.width / 2 - stroke / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final colors = [
      Colors.red,
      Colors.green,
      Colors.yellow,
      Colors.cyan,
      Colors.red,
      Colors.green,
      Colors.yellow,
      Colors.cyan
    ];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;

    const sect = math.pi / 4;
    for (int i = 0; i < 8; i++) {
      paint.color = colors[i];
      final start = -math.pi / 2 - sect / 2 + i * sect;
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius), start, sect, false, paint);
    }

    // Разделительные линии (15 градусов)
    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    const subSect = math.pi / 12; // 15 градусов
    for (int i = 0; i < 8; i++) {
      final sectorColor = colors[i];
      final lineLuminance = sectorColor.computeLuminance();
      linePaint.color = lineLuminance > 0.5
          ? Colors.black.withAlpha(128)
          : Colors.white.withAlpha(128);

      final majorStart = -math.pi / 2 - sect / 2 + i * sect;
      final line1Angle = majorStart + subSect;
      final line2Angle = majorStart + 2 * subSect;

      void drawLineAtAngle(double angle) {
        final startPoint = Offset(
          center.dx + (radius - stroke / 2) * math.cos(angle),
          center.dy + (radius - stroke / 2) * math.sin(angle),
        );
        final endPoint = Offset(
          center.dx + (radius + stroke / 2) * math.cos(angle),
          center.dy + (radius + stroke / 2) * math.sin(angle),
        );
        canvas.drawLine(startPoint, endPoint, linePaint);
      }

      drawLineAtAngle(line1Angle);
      drawLineAtAngle(line2Angle);
    }

    // координатные метки N,E,S,W
    final letters = {0: 'С', 2: 'В', 4: 'Ю', 6: 'З'};
    for (var e in letters.entries) {
      final i = e.key;
      final t = e.value;
      final col = colors[i];
      final textColor = col.computeLuminance() > 0.5 ? Colors.black : Colors.white;
      final tp = TextPainter(
        text: TextSpan(
            text: t,
            style: TextStyle(
                color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
        textDirection: TextDirection.ltr,
      )..layout();
      final ang = -math.pi / 2 + i * sect;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(ang);
      canvas.translate(radius, 0);
      canvas.rotate(-ang + heading * math.pi / 180);
      tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant WindRosePainter old) =>
      old.isDarkMode != isDarkMode || old.heading != heading;
}

class UprightTrianglePainter extends CustomPainter {
  final Color color;
  const UprightTrianglePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(s.width / 2, 0)
      ..lineTo(0, s.height)
      ..lineTo(s.width, s.height)
      ..close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant UprightTrianglePainter o) => o.color != color;
}

class DownwardTrianglePainter extends CustomPainter {
  final Color color;
  const DownwardTrianglePainter({required this.color});
  @override
  void paint(Canvas c, Size s) {
    final p = Paint()..color = color..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(s.width, 0)
      ..lineTo(s.width / 2, s.height)
      ..close();
    c.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant DownwardTrianglePainter o) => o.color != color;
}
