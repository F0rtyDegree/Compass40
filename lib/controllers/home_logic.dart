// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../services/log_service.dart';
import '../services/sensor_service.dart';
import '../services/gps_manager.dart';
import '../services/gps_compass_service.dart';
import '../services/track_recorder.dart';
import '../services/gpx_export_service.dart';
import '../utils/geo_utils.dart';
import 'home_state.dart';
import '../services/file_logger.dart';
import '../services/background_tracker.dart';
import '../services/compass_service.dart';
import '../utils/app_constants.dart';

class HomeLogic {
  final HomeState state;
  final void Function(VoidCallback fn) setState;
  final LogService logService;
  final SensorService sensorService;
  final GpsManager _gpsManager = GpsManager();
  final CompassService _compassService = CompassService();

  StreamSubscription<GpsData>? _gpsSubscription;
  StreamSubscription? _headingSubscription;
  StreamSubscription? _gyroscopeSubscription;

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
    final status = await Permission.storage.request();
    if (!status.isGranted) {
      await Permission.manageExternalStorage.request();
    }

    await FileLogger.init();
    FileLogger.writeLog('Compass40 start');

    await _loadAllSettings();
    await loadLogEntries();
    await _checkAndRecoverTrack();
    await _initServicesAndPermissions();

    _compassService.start();
    _headingSubscription = _compassService.dataStream.listen((data) {
      final useGps = _useGpsCompass();
      print('MAG: heading=${data.heading.toStringAsFixed(1)} useGps=$useGps');
      if (!useGps) {
        state.headingNotifier.value = data.heading;
      }
      state.accuracyNotifier.value = data.accuracy;
      state.calibrationProgressNotifier.value = data.calibrationProgress;
    });
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;

    print('dispose: (5)');
    FileLogger.writeLog('Compass40 stop');
    print('dispose(): (4)');

    stopBackgroundService();

    _gpsSubscription?.cancel();
    _gpsSubscription = null;
    _headingSubscription?.cancel();
    _gyroscopeSubscription?.cancel();

    _gpsManager.dispose();
    _compassService.stop();
    print('dispose(): (3)');
    state.uiUpdateTimer?.cancel();
    print('dispose(): (1)');
    GpsCompassService.instance.bearingNotifier.removeListener(
      _onGpsBearingChanged,
    );
    GpsCompassService.instance.isActiveNotifier.removeListener(
      _onGpsActiveChanged,
    );
    state.disposeNotifiers();
    print('dispose(): exit');
  }

  Future<void> _loadAllSettings() async {
    final settings = await sensorService.loadSettings();
    setState(() {
      state.useManualDeclination = settings.useManualDeclination;
      state.magneticDeclination = settings.magneticDeclination;
      state.uiUpdatePeriod = settings.uiUpdatePeriod;
      state.compassMode = settings.compassMode;
      state.autoSwitchSpeedKmh = settings.autoSwitchSpeedKmh;
    });
    _compassService.updateSettings(settings);
    startUiUpdateTimer();
    _onGpsActiveChanged();
  }

  Future<void> reloadSettings() async {
    await _loadAllSettings();
    final settings = await sensorService.loadSettings();
    GpsCompassService.instance.updateSettings(settings);
    _compassService.updateSettings(settings);
  }

  Future<void> setCompassMode(CompassMode mode) async {
    setState(() {
      state.compassMode = mode;
    });
    await sensorService.saveCompassMode(mode);
    _onGpsActiveChanged();
  }

  Future<void> setAutoSwitchSpeed(double speedKmh) async {
    setState(() {
      state.autoSwitchSpeedKmh = speedKmh;
    });
    await sensorService.saveAutoSwitchSpeed(speedKmh);
  }

  Future<void> _initServicesAndPermissions() async {
    _subscribeToSensorStreams();

    if (await sensorService.requestLocationPermission()) {
      final settings = await sensorService.loadSettings();
      GpsCompassService.instance.start(settings);
      GpsCompassService.instance.bearingNotifier.addListener(
        _onGpsBearingChanged,
      );
      GpsCompassService.instance.isActiveNotifier.addListener(
        _onGpsActiveChanged,
      );
      _subscribeToGpsDataStream();
    }
  }

  void _subscribeToGpsDataStream() async {
    final settings = await sensorService.loadSettings();
    _gpsSubscription = _gpsManager.subscribe(
      intervalSeconds: settings.gpsInterval,
      onData: (gpsData) {
        state.gpsDataNotifier.value = gpsData;
        if (!state.useManualDeclination) {
          setState(() {
            state.magneticDeclination = gpsData.magneticDeclination ?? 0.0;
          });
        }
      },
      onError: (error) {
        print('GPS error in HomeLogic: $error');
      },
      onDone: () {
        print('GPS stream closed in HomeLogic');
      },
    );
  }

  void _subscribeToSensorStreams() {
    userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      print(
        'Raw Accelerometer: x=${event.x.toStringAsFixed(2)}, y=${event.y.toStringAsFixed(2)}, z=${event.z.toStringAsFixed(2)}',
      );
    });

    magnetometerEventStream().listen((MagnetometerEvent event) {
      print(
        'Raw Magnetometer: x=${event.x.toStringAsFixed(2)}, y=${event.y.toStringAsFixed(2)}, z=${event.z.toStringAsFixed(2)}',
      );
    });

    _gyroscopeSubscription = gyroscopeEventStream().listen((
      GyroscopeEvent event,
    ) {
      print(
        'Raw Gyroscope: x=${event.x.toStringAsFixed(2)}, y=${event.y.toStringAsFixed(2)}, z=${event.z.toStringAsFixed(2)}',
      );
    });
  }

  void startUiUpdateTimer() {
    state.uiUpdateTimer?.cancel();
    state.uiUpdateTimer = Timer.periodic(
      Duration(milliseconds: state.uiUpdatePeriod),
      (timer) {
        _calculateWaypointData();
        _calculateTargetData();
      },
    );
  }

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

  Future<void> _checkAndRecoverTrack() async {
    final wasRecording = await TrackRecorder.recoverIfNeeded();
    if (wasRecording) {
      await _trackRecorder.initializeForRecovery();
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
      print(
        '🔔 toggleTrackRecording: calling updateNotification with "stop Record"',
      );
      updateNotification(content: 'Запись трэка остановлена');
    } else {
      await _trackRecorder.start();
      setState(() {
        state.isRecordingTrack = true;
        state.isRecordingTrackNotifier.value = true;
      });
      print(
        '🔔 toggleTrackRecording: calling updateNotification with "start Record"',
      );
      updateNotification(content: 'Идёт запись трэка...');
    }
  }

  Future<void> finalizeTrackAndExport() async {
    await _trackRecorder.stop();
    final trackPoints = await _trackRecorder.getTrackPoints();
    if (trackPoints.isEmpty) {
      await _trackRecorder.clear();
      return;
    }

    final dir = Directory(
      '${AppConstants.externalDownloadDir}/${AppConstants.compassFolderName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final now = DateTime.now();
    final fileName =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}.gpx';
    final filePath = '${dir.path}/$fileName';

    await GpxExportService.exportGpx(
      logItems: state.logItems,
      trackPoints: trackPoints,
      outputPath: filePath,
    );

    await _trackRecorder.clear();
  }

String getAccuracyText(double accuracy) {
  switch (accuracy.toInt()) {
    case 0:
      return 'нет данных';
    case 1:
      return 'Калибровка: нет';
    case 2:
      return 'Калибровка: средняя';
    case 3:
      return 'Калибровка: ОК';
    default:
      return 'Инициализация...';
  }
}

Color getAccuracyStatusColor(double accuracy) {
  switch (accuracy.toInt()) {
    case 0:
    case 1: 
      return Colors.redAccent;    // Красный флаг для сбитого компаса [health]
    case 2: 
      return Colors.orangeAccent; // Оранжевый для средних помех
    case 3: 
      return Colors.green;        // Зеленый — всё идеально
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

  bool _useGpsCompass() {
    final result = switch (state.compassMode) {
      CompassMode.magnetic => false,
      CompassMode.gps => true,
      CompassMode.auto => GpsCompassService.instance.isActiveNotifier.value,
    };
    print('USE_GPS: mode=${state.compassMode} active=${GpsCompassService.instance.isActiveNotifier.value} → $result');
    return result;
  }

  void _onGpsBearingChanged() {
    _updateHeadingFromGps(source: 'BEARING');
  }

  void _onGpsActiveChanged() {
    _updateHeadingFromGps(source: 'ACTIVE');
  }

  void _updateHeadingFromGps({required String source}) {
    final useGps = _useGpsCompass();
    final bearing = GpsCompassService.instance.bearingNotifier.value;
    print('GPS_$source: bearing=$bearing useGps=$useGps');

    state.isGpsCompassActiveNotifier.value = useGps;

    if (!useGps) {
      state.headingValidNotifier.value = true;
      return;
    }

    if (bearing != null) {
      state.headingNotifier.value = bearing;
      state.headingValidNotifier.value = true;
    } else {
      state.headingValidNotifier.value = false;
    }
  }
}
