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
  Offset? crosshairScreenPoint;
  Offset? crosshairImagePoint;

  // Обратная связь при копировании
  final ValueNotifier<bool> crosshairFeedback = ValueNotifier<bool>(false);

  // Текущая позиция пользователя
  Offset? currentUserImagePoint;
  Offset? currentUserScreenPoint;
  double? heading; // Азимут

  // Предпросмотр расстояния/азимута (до точки под прицелом или до цели)
  double? previewDistanceMeters;
  double? previewBearingDegrees;

  // Цели
  MapTarget? plannedTarget;
  MapTarget? activeTarget;

  // Таймер восстановления режима сопровождения
  Timer? followRestoreTimer;

  // Флаг для предотвращения утечек
  bool isDisposed = false;

  // Удобные геттеры

  List<MapTarget> get passedTargets =>
      project?.targets
          .where((t) => t.status == MapTargetStatus.passed)
          .toList() ??
      [];

  List<MapTarget> get allTargets => project?.targets ?? [];
}
