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
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Рисуем все элементы в экранных координатах

    // Якоря
    for (final anchor in anchors) {
      final screen = imageToScreen(Offset(anchor.imageX, anchor.imageY));
      _drawAnchor(canvas, screen);
    }

    // Текущая позиция
    if (currentUserImagePoint != null) {
      final screen = imageToScreen(currentUserImagePoint!);
      _drawCurrentPosition(canvas, screen);

      // Линия до активной цели или placeholder
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
    }

    // Цели
    for (final target in targets) {
      final screen = imageToScreen(Offset(target.imageX, target.imageY));
      _drawTarget(canvas, screen, target.status);
    }
  }

  // ---------------------------------------------------------
  // Преобразование image -> screen
  // ---------------------------------------------------------

  Offset imageToScreen(Offset imagePoint) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);

    // Вектор от центра изображения
    final local =
        imagePoint - Offset(imageSize.width / 2, imageSize.height / 2);

    // Масштаб
    final scaled = local * transformState.scale;

    // Поворот
    final angle = transformState.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );

    // Перенос
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

    // Якорь — восьмиугольник или простой круг с крестиком
    canvas.drawCircle(screen, 10, borderPaint);
    canvas.drawCircle(
      screen,
      10,
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );

    // Якорь-иконка: просто крестик
    final linePaint = Paint()
      ..color = Colors.purple
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    canvas.drawLine(
      screen + const Offset(-5, 0),
      screen + const Offset(5, 0),
      linePaint,
    );
    canvas.drawLine(
      screen + const Offset(0, -8),
      screen + const Offset(0, 5),
      linePaint,
    );

    // Нижняя часть якоря
    final path = Path()
      ..moveTo(screen.dx - 5, screen.dy + 5)
      ..lineTo(screen.dx, screen.dy + 10)
      ..lineTo(screen.dx + 5, screen.dy + 5);
    canvas.drawPath(path, linePaint);
  }

  // ---------------------------------------------------------
  // Отрисовка текущей позиции
  // ---------------------------------------------------------

  void _drawCurrentPosition(Canvas canvas, Offset screen) {
    // Внешний круг
    final outerPaint = Paint()
      ..color = Colors.blue.withAlpha(60)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screen, 20, outerPaint);

    // Внутренний круг
    final innerPaint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;
    canvas.drawCircle(screen, 7, innerPaint);

    // Белая граница
    final borderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawCircle(screen, 7, borderPaint);
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

    // Флажок: вертикальная палка + треугольник
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

    // Палка
    canvas.drawLine(screen, screen + const Offset(0, -28), staffPaint);

    // Флаг (треугольник)
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

    // Пунктирная линия
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
        canvas.drawLine(
          from + direction * drawn,
          from + direction * end,
          paint,
        );
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
          fontSize: 12,
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
        oldDelegate.previewDistanceMeters != previewDistanceMeters;
  }
}
