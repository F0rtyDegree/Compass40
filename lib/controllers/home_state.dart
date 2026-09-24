import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';

import '../log_entry.dart';

// Режимы компаса
enum CompassMode { auto, magnetic, gps }

/// Состояние главного экрана.
///
/// ВНИМАНИЕ: обычные поля и ValueNotifier смешаны исторически.
/// Часть значений обновляется через setState (waypoint, target, logItems),
/// часть — через ValueNotifier (gpsDataNotifier, headingNotifier и т.д.).
/// Это не ошибка, а следствие эволюции кода: сначала всё было на setState,
/// затем для часто меняющихся значений добавили ValueNotifier.
/// Не рефакторить без явной необходимости — затрагивает все контроллеры
/// и экраны, риск сломать работающее выше пользы.
class HomeState {
  final ValueNotifier<GpsData> gpsDataNotifier = ValueNotifier(GpsData());
  final ValueNotifier<double> headingNotifier = ValueNotifier(0);
  final ValueNotifier<double> accuracyNotifier = ValueNotifier(0);
  final ValueNotifier<int> calibrationProgressNotifier = ValueNotifier(0);
  final ValueNotifier<bool> headingValidNotifier = ValueNotifier(true);
  final ValueNotifier<bool> isGpsCompassActiveNotifier = ValueNotifier(false);
  final ValueNotifier<bool> calibrationStaleNotifier = ValueNotifier(false);

  // Режим компаса
  CompassMode compassMode = CompassMode.auto;

  // Скорость автопереключения км/ч
  double autoSwitchSpeedKmh = 3.0;

  double magneticDeclination = 0.0;
  bool useManualDeclination = false;

  GpsData? waypoint;
  final ValueNotifier<double?> distanceToWaypoint = ValueNotifier(null);
  final ValueNotifier<double?> bearingToWaypoint = ValueNotifier(null);

  Map<String, double>? target;
  final ValueNotifier<double?> distanceToTarget = ValueNotifier(null);
  final ValueNotifier<double?> bearingToTarget = ValueNotifier(null);

  List<LogItem> logItems = [];
  Timer? uiUpdateTimer;

  int uiUpdatePeriod = 250;

  // Запись трека
  bool isRecordingTrack = false;
  final ValueNotifier<bool> isRecordingTrackNotifier = ValueNotifier(false);

  void disposeNotifiers() {
    gpsDataNotifier.dispose();
    headingNotifier.dispose();
    accuracyNotifier.dispose();
    calibrationProgressNotifier.dispose();
    distanceToWaypoint.dispose();
    bearingToWaypoint.dispose();
    distanceToTarget.dispose();
    bearingToTarget.dispose();
    headingValidNotifier.dispose();
    isGpsCompassActiveNotifier.dispose();
    calibrationStaleNotifier.dispose();
    isRecordingTrackNotifier.dispose();
  }
}