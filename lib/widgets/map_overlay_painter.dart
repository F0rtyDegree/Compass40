import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_anchor.dart';
import '../models/map_target.dart';
import '../models/map_transform_state.dart';

/// Рисует поверх карты:
/// - якоря (точки привязки)
/// - текущую позицию пользователя
/// - цели (planned, active, passed)
/// - линию до активной цели или до прицела
/// - подписи дистанции и азимута
class MapOverlayPainter extends CustomPainter {
  final Size imageSize;
  final MapTransformState transformState;
  final Size viewportSize;

  final List<MapAnchor> anchors;
  final List<MapTarget> targets;

  final Offset? currentUserImagePoint;
  final Offset? activeTargetImagePoint;

  final double? previewDistanceMeters;
  final double? previewBearingDegrees;
  final double? heading;

  const MapOverlayPainter({
    required this.imageSize,
    required this.transformState,
    required this.viewportSize,
    required this.anchors,
    required this.targets,
    this.currentUserImagePoint,
    this.activeTargetImagePoint,
    this.previewDistanceMeters,
    this.previewBearingDegrees,
    this.heading,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем все элементы в экранных координатах

    // Якоря
    for (final anchor in anchors) {
      final screen = imageToScreen(Offset(anchor.imageX, anchor.imageY));
      _drawAnchor(canvas, screen);
    }

    // Цели
    for (final target in targets) {
      final screen = imageToScreen(Offset(target.imageX, target.imageY));
      _drawTarget(canvas, screen, target.status);
    }

    // Текущая позиция и линия до цели (рисуем последними, чтобы были поверх)
    if (currentUserImagePoint != null) {
      final screen = imageToScreen(currentUserImagePoint!);

      // Линия до активной цели
      if (activeTargetImagePoint != null) {
        final targetScreen = imageToScreen(activeTargetImagePoint!);
        _drawLine(canvas, screen, targetScreen);
        if (previewDistanceMeters != null && previewBearingDegrees != null) {
          _drawLabels(
            canvas,
            screen,
            targetScreen,
            previewDistanceMeters!,
            previewBearingDegrees!,
          );
        }
      }
      // Рисуем сам курсор поверх линии
      _drawCurrentPosition(canvas, screen);
    }
  }

  // ---------------------------------------------------------
  // Преобразование image -> screen
  // ---------------------------------------------------------

  Offset imageToScreen(Offset imagePoint) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final local = imagePoint - Offset(imageSize.width / 2, imageSize.height / 2);
    final scaled = local * transformState.scale;
    final angle = transformState.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );
    return center + transformState.translation + rotated;
  }

  // ---------------------------------------------------------
  // Отрисовка якоря
  // ---------------------------------------------------------

  void _drawAnchor(Canvas canvas, Offset screen) {
    final paint = Paint()
      ..color = Colors.purple
      ..style = PaintingStyle.fill;

    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(screen, 10, borderPaint);
    canvas.drawCircle(
      screen,
      10,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    final linePaint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(screen + const Offset(-5, 0), screen + const Offset(5, 0), linePaint);
    canvas.drawLine(screen + const Offset(0, -8), screen + const Offset(0, 5), linePaint);

    final path = Path()
      ..moveTo(screen.dx - 5, screen.dy + 5)
      ..lineTo(screen.dx, screen.dy + 10)
      ..lineTo(screen.dx + 5, screen.dy + 5);
    canvas.drawPath(path, linePaint);
  }

  // ---------------------------------------------------------
  // Отрисовка текущей позиции (контурный шеврон)
  // ---------------------------------------------------------

  void _drawCurrentPosition(Canvas canvas, Offset screen) {
    final outlinePaint = Paint()
      ..color = Colors.blue.shade500
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round; // Плавные соединения

    final innerShadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.5)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    // Форма стрелки-шеврона
    final path = Path()
      ..moveTo(0, -14) // Вершина чуть выше
      ..lineTo(10, 10) // Правый нижний угол
      ..lineTo(0, 5)   // Центр-низ
      ..lineTo(-10, 10) // Левый нижний угол
      ..close();

    canvas.save();
    canvas.translate(screen.dx, screen.dy);

    // Поворачиваем канву
    final headingRadians = (heading ?? 0) * (math.pi / 180);
    final totalRotation = headingRadians + transformState.rotationRadians;
    canvas.rotate(totalRotation);

    // Рисуем тень/внутреннюю обводку для контраста
    canvas.drawPath(path, innerShadowPaint);
    // Рисуем основную яркую обводку
    canvas.drawPath(path, outlinePaint);

    canvas.restore();
  }


  // ---------------------------------------------------------
  // Отрисовка цели
  // ---------------------------------------------------------

  void _drawTarget(Canvas canvas, Offset screen, MapTargetStatus status) {
    final color = switch (status) {
      MapTargetStatus.planned => Colors.yellow,
      MapTargetStatus.active => Colors.red,
      MapTargetStatus.passed => Colors.green,
    };

    final staffPaint = Paint()
      ..color = Colors.black87
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final flagPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final flagBorder = Paint()
      ..color = Colors.black54
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(screen, screen + const Offset(0, -28), staffPaint);

    final flag = Path()
      ..moveTo(screen.dx, screen.dy - 28)
      ..lineTo(screen.dx + 14, screen.dy - 22)
      ..lineTo(screen.dx, screen.dy - 16)
      ..close();

    canvas.drawPath(flag, flagPaint);
    canvas.drawPath(flag, flagBorder);
  }

  // ---------------------------------------------------------
  // Линия от текущей позиции до цели
  // ---------------------------------------------------------

  void _drawLine(Canvas canvas, Offset from, Offset to) {
    final paint = Paint()
      ..color = Colors.red.withAlpha(180)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    _drawDashedLine(canvas, from, to, paint);
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Paint paint) {
    const dashLength = 10.0;
    const gapLength = 6.0;
    final totalLength = (to - from).distance;
    if (totalLength < 1) return;

    final direction = (to - from) / totalLength;
    double drawn = 0;
    bool drawing = true;

    while (drawn < totalLength) {
      final segLen = drawing ? dashLength : gapLength;
      final end = math.min(drawn + segLen, totalLength);
      if (drawing) {
        canvas.drawLine(from + direction * drawn, from + direction * end, paint);
      }
      drawn = end;
      drawing = !drawing;
    }
  }

  // ---------------------------------------------------------
  // Подписи дистанции и азимута
  // ---------------------------------------------------------

  void _drawLabels(
    Canvas canvas,
    Offset from,
    Offset to,
    double distanceMeters,
    double bearingDegrees,
  ) {
    final mid = (from + to) / 2;
    final distText = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.round()} m';
    final bearText = '${bearingDegrees.round()}°';

    _drawLabel(canvas, distText, mid + const Offset(0, -12), Colors.red);
    _drawLabel(canvas, bearText, mid + const Offset(0, 8), Colors.red);
  }

  void _drawLabel(Canvas canvas, String text, Offset position, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: const [
            Shadow(color: Colors.white, offset: Offset(1, 1), blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant MapOverlayPainter oldDelegate) {
    return oldDelegate.transformState != transformState ||
        oldDelegate.anchors.length != anchors.length ||
        oldDelegate.targets.length != targets.length ||
        oldDelegate.currentUserImagePoint != currentUserImagePoint ||
        oldDelegate.activeTargetImagePoint != activeTargetImagePoint ||
        oldDelegate.previewDistanceMeters != previewDistanceMeters ||
        oldDelegate.heading != heading;
  }
}
