import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/map_project.dart';
import '../models/map_target.dart';
import '../models/map_transform_state.dart';
import '../models/map_working_pair.dart';

class MapScreenState {
  // Проект и изображение
  String? imagePath;
  Size? imageSize;
  MapProject? project;

  // Размер области отображения карты
  Size? viewportSize;

  // Трансформация карты (pan / zoom / rotate)
  MapTransformState transformState = const MapTransformState();

  // Угол поворота самой карты относительно севера (вычисляется при калибровке)
  double mapRotation = 0.0;

  // Режимы
  bool followMode = false;
  bool rotateMapByHeading = false;
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

  // Текущая позиция пользователя
  Offset? currentUserImagePoint;
  Offset? currentUserScreenPoint;
  double? heading; // Азимут
  bool isGpsActive = false;

  // Предпросмотр расстояния/азимута (до точки под прицелом или до цели)
  double? previewDistanceMeters;
  double? previewBearingDegrees;

  // Цели
  MapTarget? plannedTarget;
  MapTarget? activeTarget;

  // Таймер восстановления режима сопровождения
  Timer? followRestoreTimer;
  Timer?
  rotateModeTimer; // Таймер для автоматического отключения режима вращения

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

  List<MapTarget> get passedTargets =>
      project?.targets
          .where((t) => t.status == MapTargetStatus.passed)
          .toList() ??
      [];

  List<MapTarget> get allTargets => project?.targets ?? [];
}
