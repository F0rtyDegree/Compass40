// ignore_for_file: avoid_print

import 'dart:async';
import 'package:gps_info/gps_info.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/home_state.dart';
import '../utils/app_constants.dart';

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  final GpsInfo _gpsInfo = GpsInfo();

  // Expose sensor streams by calling the new recommended methods
  Stream<MagnetometerEvent> get magnetometerEvents => magnetometerEventStream();
  Stream<UserAccelerometerEvent> get userAccelerometerEvents =>
      userAccelerometerEventStream();
  Stream<GyroscopeEvent> get gyroscopeEvents => gyroscopeEventStream();

  Future<SensorSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final useManualDeclination = prefs.getBool('useManualDeclination') ?? false;
    final magneticDeclination = useManualDeclination
        ? (prefs.getDouble('manualDeclination') ?? 0.0)
        : 0.0;

    final compassModeIndex = prefs.getInt('compassMode') ?? 0;
    final compassMode = CompassMode.values[compassModeIndex];
    final autoSwitchSpeedKmh =
        prefs.getDouble('autoSwitchSpeedKmh') ??
        AppConstants.autoSwitchSpeedDefaultKmh;

    return SensorSettings(
      useManualDeclination: useManualDeclination,
      magneticDeclination: magneticDeclination,
      compassSmoothness:
          prefs.getInt('compassSmoothness') ??
          AppConstants.compassSmoothnessDefault,
      uiUpdatePeriod:
          prefs.getInt('uiUpdatePeriod') ??
          AppConstants.uiUpdatePeriodDefaultMs,
      gpsInterval: prefs.getInt('gpsUpdateInterval') ?? AppConstants.gpsUpdateIntervalDefaultSec,
      compassMode: compassMode,
      autoSwitchSpeedKmh: autoSwitchSpeedKmh,
      gpsAveragingSamples: prefs.getInt('gpsAveragingSamples') ?? AppConstants.gpsAveragingSamplesDefault,
    );
  }

  Future<void> saveCompassMode(CompassMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('compassMode', mode.index);
  }

  Future<void> saveAutoSwitchSpeed(double speedKmh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('autoSwitchSpeedKmh', speedKmh);
  }

  Future<bool> requestLocationPermission() async {
    return (await Permission.location.request()).isGranted;
  }

  StreamSubscription<GpsData> subscribeToGps({
    required int intervalSeconds,
    required void Function(GpsData gpsData) onData,
  }) {
    return _gpsInfo
        .getGpsDataStream(intervalSeconds)
        .listen(
          onData,
          onError: (error, stack) {
            print('GPS stream error: $error\n$stack');
          },
        );
  }
}

class SensorSettings {
  final bool useManualDeclination;
  final double magneticDeclination;
  final int compassSmoothness;
  final int uiUpdatePeriod;
  final int gpsInterval;
  final CompassMode compassMode;
  final double autoSwitchSpeedKmh;
  final int gpsAveragingSamples;

  SensorSettings({
    required this.useManualDeclination,
    required this.magneticDeclination,
    required this.compassSmoothness,
    required this.uiUpdatePeriod,
    required this.gpsInterval,
    required this.compassMode,
    required this.autoSwitchSpeedKmh,
    this.gpsAveragingSamples = AppConstants.gpsAveragingSamplesDefault,
  });
}
