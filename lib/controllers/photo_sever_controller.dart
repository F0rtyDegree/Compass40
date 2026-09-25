import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';

class PhotoSeverController {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final Future<double?> Function() askDistanceDialog;
  final void Function(MapTransformState newTransform) updateTransform;
  final MapStorageService storageService;
  final Offset Function(Offset imagePoint) imageToScreen;
  final VoidCallback? onFinish;
  final VoidCallback? onEnableFollowMode;

  bool isActive = false;
  final List<Offset> points = [];

  /// Трансформация карты до поворота в _applyNorthRotation.
  /// Восстанавливается, если пользователь отменяет ввод расстояния.
  MapTransformState? _savedTransformBeforeRotation;

  /// Был ли follow mode включён до старта PhotoSever.
  bool _followWasEnabled = false;

  PhotoSeverController({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.askDistanceDialog,
    required this.updateTransform,
    required this.storageService,
    required this.imageToScreen,
    this.onFinish,
    this.onEnableFollowMode,
  });

  void start() {
    setState(() {
      // Запоминаем, был ли follow mode включён, чтобы восстановить его
      // при отмене.
      _followWasEnabled = state.followMode;
      // Выключаем follow mode: в нём прицел смещён в 3/4 высоты,
      // точки ФотоСевера ставятся в неудобной позиции.
      if (state.followMode) {
        state.followMode = false;
        state.crosshairInCenter = true;
      }
      isActive = true;
      points.clear();
      _savedTransformBeforeRotation = null;
    });
    showSnackBar('Укажите первую точку (юг)');
  }

  void handleTap(Offset imagePoint) {
    if (!isActive) return;
    setState(() {
      points.add(imagePoint);
    });

    switch (points.length) {
      case 1:
        showSnackBar('Укажите вторую точку (север)');
        break;
      case 2:
        showSnackBar('Укажите третью точку (масштаб)');
        _applyNorthRotation();
        break;
      case 3:
        finish();
        break;
    }
  }

  void _applyNorthRotation() {
    final p1 = points[0];
    final p2 = points[1];
    final imageVec = p2 - p1;
    const northVec = Offset(0, -1);

    final targetAngle = math.atan2(northVec.dy, northVec.dx);
    final vecAngle = math.atan2(imageVec.dy, imageVec.dx);
    final neededRotation = targetAngle - vecAngle;

    final current = state.transformState;
    final pivotImage = p2; // Вторая точка остается под прицелом

    final tempTransform = current.copyWith(rotationRadians: neededRotation);
    final saved = state.transformState;

    state.transformState = tempTransform;
    final pivotScreenAfter = imageToScreen(pivotImage);
    state.transformState = saved;

    final pivotScreen = imageToScreen(pivotImage);
    final delta = pivotScreen - pivotScreenAfter;
    final newTranslation = current.translation + delta;

    _savedTransformBeforeRotation = state.transformState;

    updateTransform(
      current.copyWith(
        rotationRadians: neededRotation,
        translation: newTranslation,
      ),
    );
  }

  Future<void> finish() async {
    final dist = await askDistanceDialog();
    if (dist == null) {
      final saved = _savedTransformBeforeRotation;
      final restoreFollow = _followWasEnabled;
      setState(() {
        isActive = false;
        points.clear();
        _savedTransformBeforeRotation = null;
        _followWasEnabled = false;
      });
      // Откатываем поворот карты, сделанный на третьей точке.
      if (saved != null) {
        updateTransform(saved);
      }
      // Восстанавливаем follow mode, если он был включён до старта.
      if (restoreFollow) {
        onEnableFollowMode?.call();
      }
//      showSnackBar('ФотоСевер отменён');
      return;
    }
    final project = state.project;
    if (project == null) return;

    // ✅ Вычисляем новые поля для ФотоСевера
    final p1 = points[0];
    final p2 = points[1];
    final p3 = points[2];

    // Магнитный угол (как задал пользователь)
    final northAngle = math.atan2(p2.dy - p1.dy, p2.dx - p1.dx);

    // Длина перпендикуляра от p3 к линии p1-p2 (в пикселях)
    final lineVec = p2 - p1;
    final lineLen = lineVec.distance;
    double linePixels = 0.0;
    if (lineLen > 1e-6) {
      final toP3 = p3 - p1;
      final projection =
          (toP3.dx * lineVec.dx + toP3.dy * lineVec.dy) / lineLen;
      final projectedPoint = p1 + lineVec * (projection / lineLen);
      linePixels = (p3 - projectedPoint).distance;
    }

    // ✅ Сохраняем магнитный угол (без пересчёта в истинный)
    final updatedProject = project.copyWith(
      photoSeverLineMeters: dist,
      photoSeverLinePixels: linePixels,
      photoSeverNorthAngle: northAngle,
    );

    await storageService.saveProject(updatedProject);
    setState(() {
      state.project = updatedProject;
      isActive = false;
      points.clear();
      _savedTransformBeforeRotation = null;
      _followWasEnabled = false;
      // Устанавливаем mapRotation, чтобы курсор направления учитывал ориентацию снимка
      state.mapRotation = -math.pi / 2 - northAngle;
    });
//    showSnackBar('Калибровка ФотоСевер сохранена');
    
    // Вызываем callback после сохранения
    onFinish?.call();
  }
}
