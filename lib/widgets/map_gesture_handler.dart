import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

/// Обработчик жестов для карты (панорамирование, масштабирование, поворот).
/// Не содержит UI, только математику преобразований.
class MapGestureHandler {
  // Состояния жеста
  Offset _gestureStartTranslation = Offset.zero;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  Offset _gestureStartFocalPoint = Offset.zero;
  Offset? _gestureStartPivotImage; // точка изображения под прицелом
  double _accumulatedRotation = 0.0;
  double _lastAngle = 0.0;

  // Размеры, которые должны обновляться извне
  Size? viewportSize;
  Size? imageSize;

  // Зависимости, получаемые при создании
  final MapTransformState transformState;
  final void Function(MapTransformState) onUpdateTransform;
  final Offset Function() getCrosshairScreenPoint;
  final Offset Function(Offset) screenToImage;
  final Offset Function(Offset) imageToScreen;
  final bool Function() getRotateMode;

  MapGestureHandler({
    required this.transformState,
    required this.onUpdateTransform,
    required this.getCrosshairScreenPoint,
    required this.screenToImage,
    required this.imageToScreen,
    required this.getRotateMode,
  });

  void onScaleStart(ScaleStartDetails details) {
    _gestureStartTranslation = transformState.translation;
    _gestureStartScale = transformState.scale;
    _gestureStartRotation = transformState.rotationRadians;
    _gestureStartFocalPoint = details.focalPoint;

    if (viewportSize != null && imageSize != null) {
      final pivotScreen = getCrosshairScreenPoint();
      _gestureStartPivotImage = screenToImage(pivotScreen);
    } else {
      _gestureStartPivotImage = null;
    }

    _accumulatedRotation = 0.0;
    if (viewportSize != null && imageSize != null) {
      final pivotScreen = getCrosshairScreenPoint();
      final startVector = _gestureStartFocalPoint - pivotScreen;
      _lastAngle = math.atan2(startVector.dy, startVector.dx);
    } else {
      _lastAngle = 0.0;
    }
  }

  void onScaleUpdate(ScaleUpdateDetails details) {
    if (viewportSize == null || imageSize == null) return;

    final pointerCount = details.pointerCount;

    if (pointerCount == 1) {
      _handleOneFinger(details);
    } else if (pointerCount == 2) {
      _handleTwoFingers(details);
    } else if (pointerCount >= 3) {
      _handleThreeFingers(details);
    }
  }

  void _handleOneFinger(ScaleUpdateDetails details) {
    final rotateMode = getRotateMode();
    if (rotateMode) {
      _handleOneFingerRotate(details);
    } else {
      _handleOneFingerPan(details);
    }
  }

  void _handleOneFingerPan(ScaleUpdateDetails details) {
    final delta = details.focalPoint - _gestureStartFocalPoint;
    final newTranslation = _gestureStartTranslation + delta;
    onUpdateTransform(MapTransformState(
      scale: transformState.scale,
      rotationRadians: transformState.rotationRadians,
      translation: newTranslation,
    ));
  }

  void _handleOneFingerRotate(ScaleUpdateDetails details) {
    final pivotScreen = getCrosshairScreenPoint();
    final currentVector = details.focalPoint - pivotScreen;
    final currentAngle = math.atan2(currentVector.dy, currentVector.dx);
    double deltaAngle = currentAngle - _lastAngle;
    if (deltaAngle > math.pi) deltaAngle -= 2 * math.pi;
    if (deltaAngle < -math.pi) deltaAngle += 2 * math.pi;
    _accumulatedRotation += deltaAngle;
    _lastAngle = currentAngle;
    const sensitivity = 0.8;
    final newRotation = _gestureStartRotation + _accumulatedRotation * sensitivity;

    if (_gestureStartPivotImage != null) {
      final pivotScreenAfterRotate = imageToScreen(_gestureStartPivotImage!);
      final delta = pivotScreen - pivotScreenAfterRotate;
      final newTranslation = _gestureStartTranslation + delta;
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: newTranslation,
      ));
    } else {
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: transformState.translation,
      ));
    }
  }

  void _handleTwoFingers(ScaleUpdateDetails details) {
    final scaleChange = (details.scale - 1.0).abs();
    final rotationChange = details.rotation.abs();

    if (scaleChange > rotationChange) {
      _handleTwoFingerScale(details);
    } else {
      _handleTwoFingerRotate(details);
    }
  }

  void _handleTwoFingerScale(ScaleUpdateDetails details) {
    final newScale = (_gestureStartScale * details.scale).clamp(0.05, 20.0);
    if (_gestureStartPivotImage != null) {
      final pivotScreen = getCrosshairScreenPoint();
      final pivotScreenAfterScale = imageToScreen(_gestureStartPivotImage!);
      final delta = pivotScreen - pivotScreenAfterScale;
      final newTranslation = _gestureStartTranslation + delta;
      onUpdateTransform(MapTransformState(
        scale: newScale,
        rotationRadians: transformState.rotationRadians,
        translation: newTranslation,
      ));
    } else {
      onUpdateTransform(MapTransformState(
        scale: newScale,
        rotationRadians: transformState.rotationRadians,
        translation: _gestureStartTranslation,
      ));
    }
  }

  void _handleTwoFingerRotate(ScaleUpdateDetails details) {
    final pivotScreen = getCrosshairScreenPoint();
    final currentRotation = _gestureStartRotation + details.rotation;
    if (_gestureStartPivotImage != null) {
      final pivotScreenAfterRotate = imageToScreen(_gestureStartPivotImage!);
      final delta = pivotScreen - pivotScreenAfterRotate;
      final newTranslation = _gestureStartTranslation + delta;
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: currentRotation,
        translation: newTranslation,
      ));
    } else {
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: currentRotation,
        translation: transformState.translation,
      ));
    }
  }

  void _handleThreeFingers(ScaleUpdateDetails details) {
    final pivotScreen = getCrosshairScreenPoint();
    final startVector = _gestureStartFocalPoint - pivotScreen;
    final currentVector = details.focalPoint - pivotScreen;
    final startAngle = math.atan2(startVector.dy, startVector.dx);
    final currentAngle = math.atan2(currentVector.dy, currentVector.dx);
    double deltaAngle = currentAngle - startAngle;
    if (deltaAngle > math.pi) deltaAngle -= 2 * math.pi;
    if (deltaAngle < -math.pi) deltaAngle += 2 * math.pi;
    const sensitivity = 0.8;
    final newRotation = _gestureStartRotation + deltaAngle * sensitivity;

    if (_gestureStartPivotImage != null) {
      final pivotScreenAfterRotate = imageToScreen(_gestureStartPivotImage!);
      final delta = pivotScreen - pivotScreenAfterRotate;
      final newTranslation = _gestureStartTranslation + delta;
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: newTranslation,
      ));
    } else {
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: transformState.translation,
      ));
    }
  }

  // Публичные методы для кнопок масштабирования и сброса поворота
  void zoomIn() {
    final newScale = (transformState.scale * 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(newScale);
  }

  void zoomOut() {
    final newScale = (transformState.scale / 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(newScale);
  }

  void resetRotation() {
    const newRotation = 0.0;
    if (viewportSize != null && imageSize != null) {
      final pivotScreen = getCrosshairScreenPoint();
      final pivotImage = screenToImage(pivotScreen);
      final pivotScreenAfterReset = imageToScreen(pivotImage);
      final delta = pivotScreen - pivotScreenAfterReset;
      final newTranslation = transformState.translation + delta;
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: newTranslation,
      ));
    } else {
      onUpdateTransform(MapTransformState(
        scale: transformState.scale,
        rotationRadians: newRotation,
        translation: transformState.translation,
      ));
    }
  }

  void _scaleAroundCrosshair(double newScale) {
    if (viewportSize == null || imageSize == null) return;
    final pivotScreen = getCrosshairScreenPoint();
    final pivotImage = screenToImage(pivotScreen);
    final pivotScreenAfterScale = imageToScreen(pivotImage);
    final delta = pivotScreen - pivotScreenAfterScale;
    final newTranslation = transformState.translation + delta;
    onUpdateTransform(MapTransformState(
      scale: newScale,
      rotationRadians: transformState.rotationRadians,
      translation: newTranslation,
    ));
  }
}
