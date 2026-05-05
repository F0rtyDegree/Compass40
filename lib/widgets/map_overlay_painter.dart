import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_anchor.dart';
import '../models/map_target.dart';
import '../models/map_transform_state.dart';

class MapOverlayPainter extends CustomPainter {
  final Size imageSize;
  final MapTransformState transformState;
  final Size viewportSize;

  final List<MapAnchor> anchors;
  final List<MapTarget> targets;
  final List<Offset> userPath;
  final List<int> pathJumpIndices;

  final Offset? currentUserImagePoint;
  final Offset? activeTargetImagePoint;

  final double? previewDistanceMeters;
  final double? previewBearingDegrees;
  final double? heading;
  final double mapRotation;
  final double magneticDeclination;

  const MapOverlayPainter({
    required this.imageSize,
    required this.transformState,
    required this.viewportSize,
    required this.anchors,
    required this.targets,
    this.userPath = const [],
    this.pathJumpIndices = const [],
    this.currentUserImagePoint,
    this.activeTargetImagePoint,
    this.previewDistanceMeters,
    this.previewBearingDegrees,
    this.heading,
    this.mapRotation = 0.0,
    this.magneticDeclination = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    _drawUserPath(canvas);

    for (final anchor in anchors) {
      final screen = imageToScreen(Offset(anchor.imageX, anchor.imageY));
      _drawAnchor(canvas, screen);
    }

    for (final target in targets) {
      final screen = imageToScreen(Offset(target.imageX, target.imageY));
      _drawTarget(canvas, screen, target.status);
    }

    if (currentUserImagePoint != null) {
      final screen = imageToScreen(currentUserImagePoint!);

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
      _drawCurrentPosition(canvas, screen);
    }
  }
  
  void _drawUserPath(Canvas canvas) {
    if (userPath.length < 2) return;

    final solidPathPaint = Paint()
      ..color = Colors.blue.withAlpha(204)
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final dashedPathPaint = Paint()
      ..color = Colors.blue.withAlpha(150)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
      
    final jumpIndicesSet = pathJumpIndices.toSet();

    for (int i = 1; i < userPath.length; i++) {
      final p1 = imageToScreen(userPath[i - 1]);
      final p2 = imageToScreen(userPath[i]);

      if (jumpIndicesSet.contains(i)) {
        _drawDashedLine(canvas, p1, p2, dashedPathPaint);
      } else {
        canvas.drawLine(p1, p2, solidPathPaint);
      }
    }
  }

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

  void _drawCurrentPosition(Canvas canvas, Offset screen) {
    final outlinePaint = Paint()
      ..color = Colors.blue.shade500
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final innerShadowPaint = Paint()
      ..color = Colors.black.withAlpha(128)
      ..strokeWidth = 0.75
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;

    final path = Path()
      ..moveTo(0, -30)
      ..lineTo(15, 15)
      ..lineTo(0, 10)
      ..lineTo(-15, 15)
      ..close();

    canvas.save();
    canvas.translate(screen.dx, screen.dy);

    final magneticHeadingRad = (heading ?? 0) * (math.pi / 180);
    final declinationRad = magneticDeclination * (math.pi / 180);
    final trueHeadingRad = magneticHeadingRad + declinationRad;

    final totalRotation =
        trueHeadingRad + transformState.rotationRadians - mapRotation;

    canvas.rotate(totalRotation);
    canvas.drawPath(path, innerShadowPaint);
    canvas.drawPath(path, outlinePaint);
    canvas.restore();
  }

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

  /// Возвращает (t0, t1) — параметры видимой части отрезка p1-p2 внутри rect,
  /// или null, если отрезок полностью вне rect.
  (double t0, double t1)? _clipLineSegment(Offset p1, Offset p2, Rect rect) {
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final p = [-dx, dx, -dy, dy];
    final q = [
      p1.dx - rect.left,
      rect.right - p1.dx,
      p1.dy - rect.top,
      rect.bottom - p1.dy,
    ];
    double t0 = 0.0;
    double t1 = 1.0;

    for (int i = 0; i < 4; i++) {
      if (p[i] == 0) {
        if (q[i] < 0) return null;
      } else {
        final t = q[i] / p[i];
        if (p[i] < 0) {
          if (t > t0) t0 = t;
        } else {
          if (t < t1) t1 = t;
        }
      }
    }
    if (t0 <= t1) return (t0, t1);
    return null;
  }

  /// Возвращает точку на отрезке p1-p2, гарантированно лежащую внутри rect,
  /// или null, если отрезок не пересекает rect.
  Offset? _getLabelPositionInsideViewport(Offset p1, Offset p2, Size viewport) {
    final rect = Rect.fromLTWH(0, 0, viewport.width, viewport.height);
    if (p1 == p2) {
      return rect.contains(p1) ? p1 : null;
    }
    final clip = _clipLineSegment(p1, p2, rect);
    if (clip == null) return null;
    final (t0, t1) = clip;
    final tMid = (t0 + t1) / 2;
    return Offset(
      p1.dx + (p2.dx - p1.dx) * tMid,
      p1.dy + (p2.dy - p1.dy) * tMid,
    );
  }

  void _drawLabels(
    Canvas canvas,
    Offset from,
    Offset to,
    double distanceMeters,
    double bearingDegrees,
  ) {
    final labelPos = _getLabelPositionInsideViewport(from, to, viewportSize);
    if (labelPos == null) return;

    final distText = distanceMeters >= 1000
        ? '${(distanceMeters / 1000).toStringAsFixed(2)} km'
        : '${distanceMeters.round()} m';
    final bearText = '${bearingDegrees.round()}°';

    _drawLabel(canvas, distText, labelPos + const Offset(0, -12), Colors.red);
    _drawLabel(canvas, bearText, labelPos + const Offset(0, 8), Colors.red);
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
    // Быстрые проверки простых полей
    if (oldDelegate.transformState != transformState ||
        oldDelegate.heading != heading ||
        oldDelegate.mapRotation != mapRotation ||
        oldDelegate.magneticDeclination != magneticDeclination ||
        oldDelegate.previewDistanceMeters != previewDistanceMeters ||
        oldDelegate.previewBearingDegrees != previewBearingDegrees ||
        oldDelegate.currentUserImagePoint != currentUserImagePoint ||
        oldDelegate.activeTargetImagePoint != activeTargetImagePoint) {
      return true;
    }

    // Проверка списков: размер и последний элемент для userPath
    if (oldDelegate.anchors.length != anchors.length) return true;
    if (oldDelegate.targets.length != targets.length) return true;
    if (oldDelegate.userPath.length != userPath.length) return true;
    if (oldDelegate.pathJumpIndices.length != pathJumpIndices.length) return true;

    // Если добавилась новая точка пути – перерисовать
    if (userPath.isNotEmpty && oldDelegate.userPath.isNotEmpty) {
      if (userPath.last != oldDelegate.userPath.last) return true;
    } else if (userPath.isNotEmpty != oldDelegate.userPath.isNotEmpty) {
      return true;
    }

    // Для якорей и целей – сравнение последних ID (обычно добавляются в конец)
    if (anchors.isNotEmpty && oldDelegate.anchors.isNotEmpty) {
      if (anchors.last.id != oldDelegate.anchors.last.id) return true;
    } else if (anchors.isNotEmpty != oldDelegate.anchors.isNotEmpty) {
      return true;
    }

    if (targets.isNotEmpty && oldDelegate.targets.isNotEmpty) {
      if (targets.last.id != oldDelegate.targets.last.id) return true;
    } else if (targets.isNotEmpty != oldDelegate.targets.isNotEmpty) {
      return true;
    }

    return false;
  }
}