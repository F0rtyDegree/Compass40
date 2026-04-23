import 'package:flutter/material.dart';

class MapCrosshair extends StatelessWidget {
  final bool inCenter;

  const MapCrosshair({super.key, this.inCenter = true});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vp = Size(constraints.maxWidth, constraints.maxHeight);

        final position = inCenter
            ? Offset(vp.width / 2, vp.height / 2)
            : Offset(vp.width / 2, vp.height * 3 / 4);

        return IgnorePointer(
          child: Stack(
            children: [
              Positioned(
                left: position.dx - 24,
                top: position.dy - 24,
                child: CustomPaint(
                  size: const Size(48, 48),
                  painter: _CrosshairPainter(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final lineLen = 16.0;
    final gap = 6.0;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = Colors.white.withAlpha(180)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    // Тени (для видимости на любом фоне)
    _drawLines(canvas, center, lineLen, gap, shadowPaint);
    // Основные линии
    _drawLines(canvas, center, lineLen, gap, paint);

    // Центральная точка
    canvas.drawCircle(
      center,
      2.0,
      Paint()
        ..color = Colors.red
        ..style = PaintingStyle.fill,
    );
  }

  void _drawLines(
    Canvas canvas,
    Offset center,
    double lineLen,
    double gap,
    Paint paint,
  ) {
    // Верх
    canvas.drawLine(
      Offset(center.dx, center.dy - gap),
      Offset(center.dx, center.dy - gap - lineLen),
      paint,
    );
    // Низ
    canvas.drawLine(
      Offset(center.dx, center.dy + gap),
      Offset(center.dx, center.dy + gap + lineLen),
      paint,
    );
    // Лево
    canvas.drawLine(
      Offset(center.dx - gap, center.dy),
      Offset(center.dx - gap - lineLen, center.dy),
      paint,
    );
    // Право
    canvas.drawLine(
      Offset(center.dx + gap, center.dy),
      Offset(center.dx + gap + lineLen, center.dy),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
