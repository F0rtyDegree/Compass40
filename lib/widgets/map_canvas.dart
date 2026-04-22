import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

/// Виджет отображения карты с собственной математикой трансформации.
/// Обрабатывает жесты pan / zoom / rotate.
/// Уведомляет родителя через [onTransformChanged] и [onViewportSize].
class MapCanvas extends StatefulWidget {
  final String imagePath;
  final Size imageSize;
  final MapTransformState transformState;
  final ValueChanged<MapTransformState> onTransformChanged;
  final ValueChanged<Size> onViewportSize;

  const MapCanvas({
    super.key,
    required this.imagePath,
    required this.imageSize,
    required this.transformState,
    required this.onTransformChanged,
    required this.onViewportSize,
  });

  @override
  State<MapCanvas> createState() => _MapCanvasState();
}

class _MapCanvasState extends State<MapCanvas> {
  // Начальные значения при старте жеста
  Offset _gestureStartTranslation = Offset.zero;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  Offset _gestureStartFocalPoint = Offset.zero;

  // Предыдущий угол для вращения
  double _previousGestureRotation = 0.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );

        WidgetsBinding.instance.addPostFrameCallback((_) {
          widget.onViewportSize(viewportSize);
        });

        return GestureDetector(
          onScaleStart: (details) => _onScaleStart(details, viewportSize),
          onScaleUpdate: (details) => _onScaleUpdate(details, viewportSize),
          child: ClipRect(
            child: SizedBox(
              width: viewportSize.width,
              height: viewportSize.height,
              child: CustomPaint(
                painter: _MapPainter(
                  imagePath: widget.imagePath,
                  imageSize: widget.imageSize,
                  transformState: widget.transformState,
                  viewportSize: viewportSize,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _onScaleStart(ScaleStartDetails details, Size viewportSize) {
    _gestureStartTranslation = widget.transformState.translation;
    _gestureStartScale = widget.transformState.scale;
    _gestureStartRotation = widget.transformState.rotationRadians;
    _gestureStartFocalPoint = details.focalPoint;
    _previousGestureRotation = 0.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails details, Size viewportSize) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);

    // Смещение фокальной точки с момента начала жеста
    final focalDelta = details.focalPoint - _gestureStartFocalPoint;

    // Новый масштаб
    final newScale = (_gestureStartScale * details.scale).clamp(0.05, 20.0);

    // Поворот: изменение угла с начала жеста
    final deltaRotation = details.rotation - _previousGestureRotation;
    _previousGestureRotation = details.rotation;
    final newRotation = widget.transformState.rotationRadians + deltaRotation;

    // Смещение: комбинация pan + сохранение центра масштаба/поворота
    // Пересчитываем translation так, чтобы focal point оставался на месте
    final scaleRatio = newScale / _gestureStartScale;

    // Вектор от центра viewport до фокальной точки в начале жеста
    final focalFromCenter = _gestureStartFocalPoint - center;

    // После масштаба + поворота этот вектор увеличивается
    final rotDelta = newRotation - _gestureStartRotation;
    final cos = math.cos(rotDelta);
    final sin = math.sin(rotDelta);

    final rotatedFocal = Offset(
      focalFromCenter.dx * cos - focalFromCenter.dy * sin,
      focalFromCenter.dx * sin + focalFromCenter.dy * cos,
    );

    final newTranslation = _gestureStartTranslation +
        focalDelta -
        (rotatedFocal * scaleRatio - focalFromCenter);

    widget.onTransformChanged(
      MapTransformState(
        scale: newScale,
        rotationRadians: newRotation,
        translation: newTranslation,
      ),
    );
  }
}

/// CustomPainter рисует изображение карты с трансформацией.
class _MapPainter extends CustomPainter {
  final String imagePath;
  final Size imageSize;
  final MapTransformState transformState;
  final Size viewportSize;

  _MapPainter({
    required this.imagePath,
    required this.imageSize,
    required this.transformState,
    required this.viewportSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);

    canvas.save();

    // Применяем трансформацию относительно центра viewport
    canvas.translate(center.dx + transformState.translation.dx,
        center.dy + transformState.translation.dy);
    canvas.rotate(transformState.rotationRadians);
    canvas.scale(transformState.scale);

    // Рисуем изображение с центром в (0,0)
    final paint = Paint();
    final imageFile = File(imagePath);

    if (imageFile.existsSync()) {
      final imageRect = Rect.fromCenter(
        center: Offset.zero,
        width: imageSize.width,
        height: imageSize.height,
      );

      // Попытка отрисовать через drawImageRect
      // Если изображение ещё не загружено — инициируем загрузку
      _tryDrawImage(canvas, paint, imageRect);
    }

    canvas.restore();
  }

  void _tryDrawImage(Canvas canvas, Paint paint, Rect destRect) {
    // Рисуем placeholder пока нет изображения
    final placeholderPaint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.fill;

    canvas.drawRect(destRect, placeholderPaint);

    final borderPaint = Paint()
      ..color = const Color(0xFF9E9E9E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawRect(destRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) {
    return oldDelegate.transformState != transformState ||
        oldDelegate.imagePath != imagePath ||
        oldDelegate.viewportSize != viewportSize;
  }
}
