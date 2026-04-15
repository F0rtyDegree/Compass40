import 'dart:async';
import 'package:flutter/widgets.dart';
import '../models/map_project.dart';
import '../models/map_transform_state.dart';
import '../models/map_target.dart';

class MapScreenState {
  // Проект и изображение
  String? imagePath;
  Size? imageSize;
  MapProject? project;
  
  // Трансформация карты
  MapTransformState transformState = const MapTransformState();
  
  // Режимы
  bool followMode = false;
  bool rotateMapByHeading = false;
  bool crosshairInCenter = true;
  
  // Позиции
  Offset? currentUserScreenPoint;  // позиция пользователя в экранных координатах
  Offset? currentUserImagePoint;   // позиция пользователя в координатах изображения
  Offset? crosshairImagePoint;      // позиция прицела в координатах изображения
  
  // Цели
  MapTarget? plannedTarget;
  MapTarget? activeTarget;
  
  // Таймеры
  Timer? followRestoreTimer;
  
  // Флаг, открыт ли экран (для предотвращения утечек)
  bool isDisposed = false;
}