import 'dart:async';

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
  // Настройки
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
      state.compassMode = settings.compassMode;
      state.autoSwitchSpeedKmh = settings.autoSwitchSpeedKmh;
    });

    startUiUpdateTimer();
  }

  Future<void> reloadSettings() async {
    await _loadAllSettings();
  }

  Future<void> setCompassMode(CompassMode mode) async {
    setState(() {
      state.compassMode = mode;
    });
    await sensorService.saveCompassMode(mode);
  }

  Future<void> setAutoSwitchSpeed(double speedKmh) async {
    setState(() {
      state.autoSwitchSpeedKmh = speedKmh;
    });
    await sensorService.saveAutoSwitchSpeed(speedKmh);
  }

  // ----------------------------------------------------------------------
  // Сенсоры
  // ----------------------------------------------------------------------

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

        final speedKmh = (gpsData.speed ?? 0) * 3.6;
        if (speedKmh > 0.5 && gpsData.gpsBearing != null) {
          state.gpsBearingNotifier.value = gpsData.gpsBearing;
          state.gpsBearingSamples.add((
            gpsData.gpsBearing!,
            DateTime.now().millisecondsSinceEpoch,
          ));
          if (state.gpsBearingSamples.length > HomeState.maxSamples) {
            state.gpsBearingSamples.removeAt(0);
          }
        }

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

        state.headingSamples.add((
          heading,
          DateTime.now().millisecondsSinceEpoch,
        ));

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

  // ----------------------------------------------------------------------
  // Таймер и обновление heading
  // ----------------------------------------------------------------------

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

  double _calculateCircularMedian(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    if (samples.length == 1) return samples[0];

    samples.sort();

    double maxGap = 0;
    int maxGapIndex = -1;

    for (int i = 0; i < samples.length - 1; i++) {
      final gap = samples[i + 1] - samples[i];
      if (gap > maxGap) {
        maxGap = gap;
        maxGapIndex = i;
      }
    }

    final wrapAroundGap = (samples.first + 360) - samples.last;
    if (wrapAroundGap > maxGap) {
      maxGap = wrapAroundGap;
      maxGapIndex = samples.length - 1;
    }

    List<double> shiftedSamples;
    if (maxGapIndex == samples.length - 1) {
      shiftedSamples = List.from(samples);
    } else {
      shiftedSamples = [];
      final shiftPoint = samples[maxGapIndex];
      for (final s in samples) {
        if (s > shiftPoint) {
          shiftedSamples.add(s);
        } else {
          shiftedSamples.add(s + 360);
        }
      }
    }

    double median;
    int mid = shiftedSamples.length ~/ 2;
    if (shiftedSamples.length % 2 == 1) {
      median = shiftedSamples[mid];
    } else {
      median = (shiftedSamples[mid - 1] + shiftedSamples[mid]) / 2.0;
    }

    return median % 360;
  }

  void _updateHeading() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final speedKmh = (state.gpsDataNotifier.value.speed ?? 0) * 3.6;
    final gpsBearing = state.gpsBearingNotifier.value;

    bool useGps = false;

    switch (state.compassMode) {
      case CompassMode.magnetic:
        useGps = false;
        break;
      case CompassMode.gps:
        useGps = gpsBearing != null;
        break;
      case CompassMode.auto:
        useGps = gpsBearing != null && speedKmh >= state.autoSwitchSpeedKmh;
        break;
    }

    state.isGpsCompassActiveNotifier.value = useGps;

    double newHeading;

    if (useGps) {
      // GPS-компас
      state.gpsBearingSamples.removeWhere(
        (s) => now - s.$2 > state.averagingPeriod,
      );
      if (state.gpsBearingSamples.isEmpty) return;
      final bearings = state.gpsBearingSamples.map((s) => s.$1).toList();
      final medianTrueBearing = _calculateCircularMedian(bearings);
      // Преобразуем истинный курс в магнитный
      newHeading = (medianTrueBearing - state.magneticDeclination + 360) % 360;
    } else {
      // Магнитный компас
      state.headingSamples.removeWhere(
        (s) => now - s.$2 > state.averagingPeriod,
      );
      if (state.headingSamples.isEmpty) return;
      final headings = state.headingSamples.map((s) => s.$1).toList();
      // Данные с сенсора уже магнитные
      newHeading = _calculateCircularMedian(headings);
    }

    // Сглаживание
    double diff = newHeading - state.filteredHeading;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;

    state.filteredHeading += state.smoothingFactor * diff;
    state.filteredHeading = (state.filteredHeading + 360) % 360;

    state.headingNotifier.value = state.filteredHeading;
  }

  // ----------------------------------------------------------------------
  // Расчёты навигации
  // ----------------------------------------------------------------------

  void _calculateWaypointData() {
    if (state.waypoint == null ||
        state.gpsDataNotifier.value.latitude == null) {
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
  // Логи и КП
  // ----------------------------------------------------------------------

  Future<void> loadLogEntries() async {
    final items = await logService.loadLogEntries();
    if (!mounted) return;
    setState(() => state.logItems = items);
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
    setState(() => state.logItems = items);
  }

  void setTarget(Map<String, double>? target) {
    setState(() => state.target = target);
  }

  void setTargetCalculationStartPoint(GpsData gpsData) {
    state.targetCalculationStartPoint = gpsData;
  }

  // ----------------------------------------------------------------------
  // Вспомогательные методы для UI
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

  String getCompassModeLabel() {
    switch (state.compassMode) {
      case CompassMode.magnetic:
        return 'Маг';
      case CompassMode.gps:
        return 'GPS';
      case CompassMode.auto:
        return 'Авто';
    }
  }
}
