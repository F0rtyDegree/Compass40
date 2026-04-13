import 'dart:async';

import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';

import '../log_entry.dart';

// Режимы компаса
enum CompassMode { magnetic, gps, auto }

class HomeState {
  final GpsInfo gpsInfo = GpsInfo();

  late StreamSubscription<GpsData> gpsDataSubscription;
  late StreamSubscription<List<double>> compassSubscription;

  final ValueNotifier<GpsData> gpsDataNotifier = ValueNotifier(GpsData());
  final ValueNotifier<double> headingNotifier = ValueNotifier(0);
  final ValueNotifier<double> accuracyNotifier = ValueNotifier(0);
  final ValueNotifier<double?> gpsBearingNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isGpsCompassActiveNotifier = ValueNotifier(false);

  // Режим компаса
  CompassMode compassMode = CompassMode.magnetic;

  // Скорость автопереключения км/ч
  double autoSwitchSpeedKmh = 3.0;

  double magneticDeclination = 0.0;
  bool useManualDeclination = false;

  GpsData? waypoint;
  final ValueNotifier<double?> distanceToWaypoint = ValueNotifier(null);
  final ValueNotifier<double?> bearingToWaypoint = ValueNotifier(null);

  GpsData? targetCalculationStartPoint;
  Map<String, double>? target;
  final ValueNotifier<double?> distanceToTarget = ValueNotifier(null);
  final ValueNotifier<double?> bearingToTarget = ValueNotifier(null);

  List<LogItem> logItems = [];
  final List<(double, int)> headingSamples = [];
  final List<(double, int)> gpsBearingSamples = [];
  Timer? uiUpdateTimer;

  int averagingPeriod = 500;
  int uiUpdatePeriod = 250;

  double filteredHeading = 0.0;
  double smoothingFactor = 0.5;

  static const int maxSamples = 50;

  void disposeNotifiers() {
    gpsDataNotifier.dispose();
    headingNotifier.dispose();
    accuracyNotifier.dispose();
    gpsBearingNotifier.dispose();
    distanceToWaypoint.dispose();
    bearingToWaypoint.dispose();
    distanceToTarget.dispose();
    bearingToTarget.dispose();
    isGpsCompassActiveNotifier.dispose();
  }
}
