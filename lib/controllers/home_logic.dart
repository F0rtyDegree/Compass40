import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';

import '../services/log_service.dart';
import '../services/sensor_service.dart';
import '../utils/geo_utils.dart';
import 'home_state.dart';

class HomeLogic {
  final HomeState state;
  final State hostState;
  final LogService logService;
  final SensorService sensorService;

  HomeLogic({
    required this.state,
    required this.hostState,
    required this.logService,
    required this.sensorService,
  });

  bool get mounted => hostState.mounted;

  void setState(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      hostState.setState(fn);
    }
  }

  Future<void> init() async {
    await _loadAllSettings();
    await loadLogEntries();
    _requestPermissions();
  }

  void dispose() {
    state.uiUpdateTimer?.cancel();
    state.gpsDataSubscription.cancel();
    state.compassSubscription.cancel();
    state.disposeNotifiers();
  }

  // ----------------------------------------------------------------------
  // ----------------------- МАГНИТНАЯ СИСТЕМА ----------------------------
  // ----------------------------------------------------------------------

  Future<void> _loadAllSettings() async {
    final settings = await sensorService.loadSettings();
    if (!mounted) return;

    setState(() {
      state.useManualDeclination = settings.useManualDeclination;
      state.magneticDeclination = settings.magneticDeclination;
      state.averagingPeriod = settings.averagingPeriod;
      state.smoothingFactor = settings.smoothingFactor;
      state.uiUpdatePeriod = settings.uiUpdatePeriod;
    });

    startUiUpdateTimer();
  }

  Future<void> reloadSettings() async {
    await _loadAllSettings();
  }

  void _requestPermissions() async {
    if (await sensorService.requestLocationPermission()) {
      _subscribeToGpsDataStream();
      _subscribeToCompassStream();
    }
  }

  void _subscribeToGpsDataStream() async {
    final settings = await sensorService.loadSettings();

    state.gpsDataSubscription = sensorService.subscribeToGps(
      gpsInfo: state.gpsInfo,
      intervalSeconds: settings.gpsInterval,
      onData: (gpsData) {
        if (!mounted) return;
        state.gpsDataNotifier.value = gpsData;
        if (!state.useManualDeclination) {
          setState(() {
            state.magneticDeclination = gpsData.magneticDeclination ?? 0.0;
          });
        }
      },
    );
  }

  void _subscribeToCompassStream() {
    state.compassSubscription = sensorService.subscribeToCompass(
      onData: (data) {
        if (!mounted || data.isEmpty) return;

        final heading = data[0];
        final accuracy = data.length > 1 ? data[1] : 0.0;
        if (accuracy < 2) return;

        state.headingSamples.add(
          (heading, DateTime.now().millisecondsSinceEpoch),
        );

        if (state.headingSamples.length > HomeState.maxSamples) {
          state.headingSamples.removeAt(0);
        }

        state.accuracyNotifier.value = accuracy;

        if (state.headingSamples.length == 1) {
          state.filteredHeading = heading;
          state.headingNotifier.value = heading;
        }
      },
    );
  }

  void startUiUpdateTimer() {
    state.uiUpdateTimer?.cancel();
    state.uiUpdateTimer = Timer.periodic(
      Duration(milliseconds: state.uiUpdatePeriod),
      (timer) {
        if (mounted) {
          _updateHeading();
          _calculateWaypointData();
          _calculateTargetData();
        }
      },
    );
  }

  void _updateHeading() {
    final now = DateTime.now().millisecondsSinceEpoch;
    state.headingSamples.removeWhere(
      (s) => now - s.$2 > state.averagingPeriod,
    );

    if (state.headingSamples.isEmpty) return;

    double sinSum = 0, cosSum = 0;
    for (var s in state.headingSamples) {
      final a = s.$1 * math.pi / 180;
      sinSum += math.sin(a);
      cosSum += math.cos(a);
    }

    final avgSin = sinSum / state.headingSamples.length;
    final avgCos = cosSum / state.headingSamples.length;
    final avgHeading = math.atan2(avgSin, avgCos) * 180 / math.pi;

    double diff = avgHeading - state.filteredHeading;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;

    state.filteredHeading += state.smoothingFactor * diff;
    state.filteredHeading = (state.filteredHeading + 360) % 360;

    state.headingNotifier.value = state.filteredHeading;
  }

  // ----------------------------------------------------------------------
  // Расчёты навигации
  // ----------------------------------------------------------------------

  void _calculateWaypointData() {
    if (state.waypoint == null || state.gpsDataNotifier.value.latitude == null) {
      return;
    }

    final nowData = state.gpsDataNotifier.value;

    state.distanceToWaypoint.value = calculateDistance(
      state.waypoint!.latitude!,
      state.waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
    );

    final trueBearing = calculateTrueBearing(
      state.waypoint!.latitude!,
      state.waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
    );

    state.bearingToWaypoint.value =
        (trueBearing - state.magneticDeclination + 360) % 360;
  }

  void _calculateTargetData() {
    if (state.target == null || state.gpsDataNotifier.value.latitude == null) {
      return;
    }

    final nowData = state.gpsDataNotifier.value;

    state.distanceToTarget.value = calculateDistance(
      nowData.latitude!,
      nowData.longitude!,
      state.target!['latitude']!,
      state.target!['longitude']!,
    );

    final trueBearing = calculateTrueBearing(
      nowData.latitude!,
      nowData.longitude!,
      state.target!['latitude']!,
      state.target!['longitude']!,
    );

    state.bearingToTarget.value =
        (trueBearing - state.magneticDeclination + 360) % 360;
  }

  // ----------------------------------------------------------------------
  // --- Работа с логами и контрольными точками --------------------------
  // ----------------------------------------------------------------------

  Future<void> loadLogEntries() async {
    final items = await logService.loadLogEntries();
    if (!mounted) return;

    setState(() {
      state.logItems = items;
    });
  }

  Future<void> setWaypoint() async {
    final result = await logService.setWaypoint(
      currentLogItems: state.logItems,
      currentGpsData: state.gpsDataNotifier.value,
      magneticDeclination: state.magneticDeclination,
    );

    if (result == null || !mounted) return;

    setState(() {
      state.logItems = result.logItems;
      state.waypoint = result.waypoint;
    });
  }

  Future<void> clearWaypoint() async {
    final result = await logService.clearWaypoint(
      currentLogItems: state.logItems,
      currentGpsData: state.gpsDataNotifier.value,
      magneticDeclination: state.magneticDeclination,
    );

    if (!mounted) return;

    setState(() {
      state.logItems = result.logItems;
      state.waypoint = result.waypoint;
      state.distanceToWaypoint.value = null;
      state.bearingToWaypoint.value = null;
    });
  }

  void clearTarget() {
    setState(() {
      state.target = null;
      state.distanceToTarget.value = null;
      state.bearingToTarget.value = null;
    });
  }

  Future<void> addTargetCreationLogEntry({
    required double baseLatitude,
    required double baseLongitude,
    required double azimuth,
    required double distance,
    required double targetLatitude,
    required double targetLongitude,
  }) async {
    final items = await logService.addTargetCreationLogEntry(
      currentLogItems: state.logItems,
      baseLatitude: baseLatitude,
      baseLongitude: baseLongitude,
      azimuth: azimuth,
      distance: distance,
      targetLatitude: targetLatitude,
      targetLongitude: targetLongitude,
    );

    if (!mounted) return;

    setState(() {
      state.logItems = items;
    });
  }

  void setTarget(Map<String, double>? target) {
    setState(() {
      state.target = target;
    });
  }

  void setTargetCalculationStartPoint(GpsData gpsData) {
    state.targetCalculationStartPoint = gpsData;
  }

  // ----------------------------------------------------------------------
  // --- Сервисная информация и цвета ------------------------------------
  // ----------------------------------------------------------------------

  String getAccuracyText(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return 'Низкая (калибруйте)';
      case 1:
        return 'Средняя';
      case 2:
        return 'Высокая';
      case 3:
        return 'Отличная';
      default:
        return 'Неизвестно';
    }
  }

  Color getAccuracyStatusColor(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String getCardinalDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'Север';
    if (heading >= 22.5 && heading < 67.5) return 'С-Восток';
    if (heading >= 67.5 && heading < 112.5) return 'Восток';
    if (heading >= 112.5 && heading < 157.5) return 'Ю-Восток';
    if (heading >= 157.5 && heading < 202.5) return 'Юг';
    if (heading >= 202.5 && heading < 247.5) return 'Ю-Запад';
    if (heading >= 247.5 && heading < 292.5) return 'Запад';
    if (heading >= 292.5 && heading < 337.5) return 'С-Запад';
    return '--';
  }
}
