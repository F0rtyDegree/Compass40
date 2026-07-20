// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/log_service.dart';
import '../services/sensor_service.dart';
import '../services/gps_manager.dart';
import '../services/gps_compass_service.dart';
import '../services/track_recorder.dart';
import '../services/gpx_export_service.dart';
import '../utils/geo_utils.dart';
import '../utils/angle_utils.dart';
import '../utils/app_constants.dart';
import 'home_state.dart';
import '../services/file_logger.dart';

class HomeLogic {
  final HomeState state;
  final void Function(VoidCallback fn) setState;
  final LogService logService;
  final SensorService sensorService;
  final GpsManager _gpsManager = GpsManager();

  // Локальная подписка на GPS (через GpsManager)
  StreamSubscription<GpsData>? _gpsSubscription;

  // Запись трека
  final TrackRecorder _trackRecorder = TrackRecorder();
  bool _wasTrackRecovered = false;
  bool get wasTrackRecovered => _wasTrackRecovered;
  bool _disposed = false;

  HomeLogic({
    required this.state,
    required this.setState,
    required this.logService,
    required this.sensorService,
  });

  Future<void> init() async {
    // Сначала запрашиваем разрешения в основном потоке
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }

    // Инициализируем лог-файл (очищаем старый)
    await FileLogger.init();

    // Теперь можно писать логи
    FileLogger.writeLog('Compass40 start');
    
    // Продолжаем инициализацию
    await _loadAllSettings();
    await loadLogEntries();
    
    // Восстановление трека после падения
    await _checkAndRecoverTrack();

    await _initServicesAndPermissions();
  }

void dispose() {
  if (_disposed) return;
  _disposed = true;

  print('dispose(): (7)');
  print('dispose: (6)');
  FileLogger.writeLog('Compass40 stop');
  print('dispose(): (5)');

  _trackRecorder.stop();

  _gpsSubscription?.cancel();
  _gpsSubscription = null;
  _gpsManager.dispose();

  print('dispose(): (4)');
  state.uiUpdateTimer?.cancel();
  print('dispose(): (3)');
  print('dispose(): (2)');
  state.compassSubscription.cancel();
  print('dispose(): (1)');
  state.disposeNotifiers();
  print('dispose(): exit');
}

  // ----------------------------------------------------------------------
  // Настройки
  // ----------------------------------------------------------------------

  Future<void> _loadAllSettings() async {
    final settings = await sensorService.loadSettings();
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
    final settings = await sensorService.loadSettings();
    GpsCompassService.instance.updateSettings(settings);
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

  Future<void> _initServicesAndPermissions() async {
    _subscribeToCompassStream();

    if (await sensorService.requestLocationPermission()) {
      final settings = await sensorService.loadSettings();
      // GpsCompassService теперь сам подписывается на GpsManager
      GpsCompassService.instance.start(settings);
      _subscribeToGpsDataStream();
    }
  }

  void _subscribeToGpsDataStream() async {
    final settings = await sensorService.loadSettings();

    // Подписываемся через GpsManager
    _gpsSubscription = _gpsManager.subscribe(
      intervalSeconds: settings.gpsInterval,
      onData: (gpsData) {
        state.gpsDataNotifier.value = gpsData;

        if (!state.useManualDeclination) {
          setState(() {
            state.magneticDeclination = gpsData.magneticDeclination ?? 0.0;
          });
        }
        // Данные уже передаются в GpsCompassService через его собственную подписку,
        // поэтому здесь ничего не вызываем.
      },
      onError: (error) {
        print('GPS error in HomeLogic: $error');
      },
      onDone: () {
        print('GPS stream closed in HomeLogic');
      },
    );
  }

  void _subscribeToCompassStream() {
    state.compassSubscription = sensorService.subscribeToCompass(
      onData: (data) {
        if (data.isEmpty) return;

        final heading = data[0];
        final accuracy = data.length > 1 ? data[1] : 0.0;
        if (accuracy == 0) {
          state.accuracyNotifier.value = 0;
          return;
        }

        // Фильтр выбросов
        if (state.headingSamples.isNotEmpty) {
          double lastHeading = state.headingSamples.last.$1;
          double diff = (heading - lastHeading).abs();
          if (diff > 180) diff = 360 - diff;
          if (diff > AppConstants.spikeThresholdDegrees) {
            state.headingSamples.add((
              lastHeading,
              DateTime.now().millisecondsSinceEpoch,
            ));
            if (state.headingSamples.length > HomeState.maxSamples) {
              state.headingSamples.removeAt(0);
            }
            state.accuracyNotifier.value = accuracy;
            return;
          }
        }

        state.headingSamples.add((
          heading,
          DateTime.now().millisecondsSinceEpoch,
        ));

        if (state.headingSamples.length > HomeState.maxSamples) {
          state.headingSamples.removeAt(0);
        }

        state.accuracyNotifier.value = accuracy;

        if (state.headingSamples.length == 1) {
          final normalizedHeading = normalizeBearing(heading);
          state.filteredHeading = normalizedHeading;
          state.headingNotifier.value = normalizedHeading;
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
        _updateHeading();
        _calculateWaypointData();
        _calculateTargetData();
      },
    );
  }

  Future<void> _updateHeading() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    bool useGps = false;

    switch (state.compassMode) {
      case CompassMode.magnetic:
        useGps = false;
        break;
      case CompassMode.gps:
        useGps = GpsCompassService.instance.isActiveNotifier.value;
        break;
      case CompassMode.auto:
        useGps = GpsCompassService.instance.isActiveNotifier.value;
        break;
    }

    state.isGpsCompassActiveNotifier.value = useGps;

    double newHeading;

    if (useGps) {
      final gpsBearing = GpsCompassService.instance.bearingNotifier.value;
      if (gpsBearing == null) return;
      newHeading = normalizeBearing(gpsBearing - state.magneticDeclination);
    } else {
      state.headingSamples.removeWhere(
        (s) => now - s.$2 > state.averagingPeriod,
      );
      if (state.headingSamples.isEmpty) return;
      final headings = state.headingSamples.map((s) => s.$1).toList();
      newHeading = await calculateCircularMedian(headings);
    }

    double diff = newHeading - state.filteredHeading;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;

    state.filteredHeading += state.smoothingFactor * diff;
    state.filteredHeading = normalizeBearing(state.filteredHeading);

    state.headingNotifier.value = state.filteredHeading;
  }

  // ----------------------------------------------------------------------
  // Расчёты навигации
  // ----------------------------------------------------------------------

  void _calculateWaypointData() {
    if (state.waypoint == null ||
        state.waypoint!.latitude == null ||
        state.waypoint!.longitude == null) {
      return;
    }

    final nowData = state.gpsDataNotifier.value;
    if (nowData.latitude == null || nowData.longitude == null) {
      return;
    }

    final navData = calculateNavigationData(
      fromLat: state.waypoint!.latitude!,
      fromLon: state.waypoint!.longitude!,
      toLat: nowData.latitude!,
      toLon: nowData.longitude!,
      magneticDeclination: state.magneticDeclination,
    );
    state.distanceToWaypoint.value = navData.distanceMeters;
    state.bearingToWaypoint.value = navData.magneticBearing;
  }

  void _calculateTargetData() {
    if (state.target == null) return;

    final nowData = state.gpsDataNotifier.value;
    if (nowData.latitude == null || nowData.longitude == null) {
      return;
    }

    final navData = calculateNavigationData(
      fromLat: nowData.latitude!,
      fromLon: nowData.longitude!,
      toLat: state.target!['latitude']!,
      toLon: state.target!['longitude']!,
      magneticDeclination: state.magneticDeclination,
    );
    state.distanceToTarget.value = navData.distanceMeters;
    state.bearingToTarget.value = navData.magneticBearing;
  }

  // ----------------------------------------------------------------------
  // Логи и КП
  // ----------------------------------------------------------------------

  Future<void> loadLogEntries() async {
    final items = await logService.loadLogEntries();
    setState(() => state.logItems = items);
  }

  Future<void> setWaypoint() async {
    final result = await logService.setWaypoint(
      currentLogItems: state.logItems,
      currentGpsData: state.gpsDataNotifier.value,
      magneticDeclination: state.magneticDeclination,
    );
    if (result == null) return;
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
    setState(() => state.logItems = items);
  }

  void setTarget(Map<String, double>? target) {
    setState(() => state.target = target);
  }

  Future<void> startNavigationFromExternal(
    double latitude,
    double longitude,
  ) async {
    final currentGps = state.gpsDataNotifier.value;
    if (currentGps.latitude == null || currentGps.longitude == null) {
      return;
    }

    final distance = calculateDistance(
      currentGps.latitude!,
      currentGps.longitude!,
      latitude,
      longitude,
    );
    final azimuth = calculateTrueBearing(
      currentGps.latitude!,
      currentGps.longitude!,
      latitude,
      longitude,
    );

    setTarget({'latitude': latitude, 'longitude': longitude});

    await addTargetCreationLogEntry(
      baseLatitude: currentGps.latitude!,
      baseLongitude: currentGps.longitude!,
      azimuth: azimuth,
      distance: distance,
      targetLatitude: latitude,
      targetLongitude: longitude,
    );
  }

  void cancelExternalNavigation() {
    clearTarget();
  }

  // ----------------------------------------------------------------------
  // Управление записью трека
  // ----------------------------------------------------------------------

  Future<void> _checkAndRecoverTrack() async {
    final wasRecording = await TrackRecorder.recoverIfNeeded();
    if (wasRecording) {
      setState(() {
        state.isRecordingTrack = true;
        state.isRecordingTrackNotifier.value = true;
      });
      _wasTrackRecovered = true;
    }
  }

  Future<void> toggleTrackRecording() async {
    if (state.isRecordingTrack) {
      await _trackRecorder.stop();
      setState(() {
        state.isRecordingTrack = false;
        state.isRecordingTrackNotifier.value = false;
      });
    } else {
      await _trackRecorder.start();
      setState(() {
        state.isRecordingTrack = true;
        state.isRecordingTrackNotifier.value = true;
      });
    }
  }

  Future<void> finalizeTrackAndExport() async {
    final trackPoints = await _trackRecorder.getTrackPoints();
    if (trackPoints.isEmpty) {
      await _trackRecorder.clear();
      return;
    }

    final dir = Directory('/storage/emulated/0/Download/Compass40');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final now = DateTime.now();
    final fileName = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.gpx';
    final filePath = '${dir.path}/$fileName';

    await GpxExportService.exportGpx(
      logItems: state.logItems,
      trackPoints: trackPoints,
      outputPath: filePath,
    );

    await _trackRecorder.clear();
  }

  // ----------------------------------------------------------------------
  // Вспомогательные методы для UI
  // ----------------------------------------------------------------------

  String getAccuracyText(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return 'Инициализация...';
      case 1:
        return 'Средняя (калибруйте)';
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
        return Colors.grey;
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