import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../models/map_project.dart';
import '../models/map_target.dart';
import '../models/map_transform_state.dart';
import '../models/map_working_pair.dart';

/// Состояние экрана карты.
///
/// ВНИМАНИЕ: обычные поля и ValueNotifier смешаны исторически.
/// Часть значений обновляется через setState (workingPair, followMode,
/// transformState и т.д.), часть — через ValueNotifier (crosshairFeedback).
/// Это не ошибка, а следствие эволюции кода. Не рефакторить без явной
/// необходимости — затрагивает все контроллеры и виджеты карты, риск
/// сломать работающее выше пользы.
class MapScreenState {
  // Проект и изображение
  String? imagePath;
  Size? imageSize;
  MapProject? project;

  // Размер области отображения карты
  Size? viewportSize;

  // Трансформация карты (pan / zoom / rotate)
  MapTransformState transformState = const MapTransformState();
    double? magneticHeading;

  // Угол поворота самой карты относительно севера (вычисляется при калибровке)
  double mapRotation = 0.0;

  // Режимы
  bool followMode = false;
  bool crosshairInCenter = true;
  bool rotateMode = false;
  
  // Текущая рабочая пара привязок
  MapWorkingPair? workingPair;

  // Состояния доступности действий
  bool canPlaceTarget = false;

  // Позиция прицела
  Offset? crosshairImagePoint;

  // Обратная связь при копировании
  final ValueNotifier<bool> crosshairFeedback = ValueNotifier<bool>(false);

  /// Временный якорь, отображается серым до получения точных координат GPS.
  MapAnchor? pendingAnchor;

  // Текущая позиция пользователя
  Offset? currentUserImagePoint;
  Offset? currentUserScreenPoint;
  bool isGpsActive = false;

  // Предпросмотр расстояния/азимута (до точки под прицелом или до цели)
  double? previewDistanceMeters;
  double? previewBearingDegrees;

  // Цели
  MapTarget? plannedTarget;
  MapTarget? activeTarget;

  Timer? rotateModeTimer; // Таймер автоматического отключения режима вращения

  // Флаг для предотвращения утечек
  bool isDisposed = false;

  // Удобные геттеры
  Offset get crosshairScreenPoint {
    if (viewportSize == null) return Offset.zero;
    final vp = viewportSize!;
    if (crosshairInCenter) {
      return Offset(vp.width / 2, vp.height / 2);
    } else {
      return Offset(vp.width / 2, vp.height * 3 / 4);
    }
  }

  void recalculateCrosshairImagePoint(Offset Function(Offset) screenToImage) {
    if (imageSize == null || viewportSize == null) return;
    crosshairImagePoint = screenToImage(crosshairScreenPoint);
  }

  void recalculateUserScreenPoint(Offset Function(Offset) imageToScreen) {
    final imagePoint = currentUserImagePoint;
    if (imagePoint == null) return;
    currentUserScreenPoint = imageToScreen(imagePoint);
  }
}
