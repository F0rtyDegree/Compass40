import 'package:flutter/material.dart';

class MapCrosshair extends StatelessWidget {
  final bool inCenter;
  final ValueNotifier<bool>? feedback;

  const MapCrosshair({
    super.key,
    this.inCenter = true,
    this.feedback,
  });

  @override
  Widget build(BuildContext context) {
    if (feedback == null) {
      return _buildCrosshair();
    }
    
    return ValueListenableBuilder<bool>(
      valueListenable: feedback!,
      builder: (context, isActive, child) {
        return _buildCrosshair(copied: isActive);
      },
    );
  }
  
  Widget _buildCrosshair({bool copied = false}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final vp = Size(constraints.maxWidth, constraints.maxHeight);

        final position = inCenter
            ? Offset(vp.width / 2, vp.height / 2)
            : Offset(vp.width / 2, vp.height * 3 / 4);

        return IgnorePointer(
          child: Stack(
            children: [
              // Анимированный круг (рисуем первым, под прицелом)
              if (copied)
                Positioned(
                  left: position.dx - 100,
                  top: position.dy - 100,
                  width: 200,
                  height: 200,
                  child: const _RippleAnimation(),
                ),
              // Прицел
              Positioned(
                left: position.dx - 30,
                top: position.dy - 30,
                child: const CustomPaint(
                  size: Size(60, 60),
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

class _RippleAnimation extends StatefulWidget {
  const _RippleAnimation();

  @override
  State<_RippleAnimation> createState() => _RippleAnimationState();
}

class _RippleAnimationState extends State<_RippleAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600), // Медленнее: 600 мс
      vsync: this,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = _controller.value;
        // Круг расширяется от 30 до 100 радиуса (диаметр 60->200)
        final radius = 30 + (70 * progress);
        // Прозрачность уменьшается, но стартуем с более насыщенного
        final opacity = (1.0 - progress * 0.8).clamp(0.0, 1.0);
        
        return Center(
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.green.withAlpha((opacity * 200).toInt()),
            ),
          ),
        );
      },
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  const _CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    // Пробел 10 пикселей от центра (ориентир шага коррекции 10 px),
    // длина луча 15 пикселей.
    final lineLen = 15.0;
    final gap = 10.0;

    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke;

    final shadowPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 8.0
      ..style = PaintingStyle.stroke;

    // Белая подложка (с выступом 2 px на торцах лучей для полного обрамления)
    _drawLines(canvas, center, lineLen + 4.0, gap - 2.0, shadowPaint);
    // Основные линии
    _drawLines(canvas, center, lineLen, gap, paint);

    // Белая окантовка центральной точки (под точкой)
    canvas.drawCircle(
      center,
      3.5,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill,
    );

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
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) => false;
}