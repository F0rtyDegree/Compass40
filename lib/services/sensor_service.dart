// ignore_for_file: avoid_print

import 'dart:async';
import 'package:gps_info/gps_info.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../controllers/home_state.dart';
import '../utils/app_constants.dart';

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  final GpsInfo _gpsInfo = GpsInfo();

  Future<SensorSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final useManualDeclination =
        prefs.getBool(AppConstants.prefUseManualDeclination) ?? false;
    final magneticDeclination = useManualDeclination
        ? (prefs.getDouble(AppConstants.prefManualDeclination) ?? 0.0)
        : 0.0;

    final compassModeIndex =
        prefs.getInt(AppConstants.prefCompassMode) ?? 0;
    final compassMode = CompassMode.values[compassModeIndex];
    final autoSwitchSpeedKmh =
        prefs.getDouble(AppConstants.prefAutoSwitchSpeedKmh) ??
        AppConstants.autoSwitchSpeedDefaultKmh;

    return SensorSettings(
      useManualDeclination: useManualDeclination,
      magneticDeclination: magneticDeclination,
      compassSmoothness:
          prefs.getInt(AppConstants.prefCompassSmoothness) ??
          AppConstants.compassSmoothnessDefault,
      uiUpdatePeriod:
          prefs.getInt(AppConstants.prefUiUpdatePeriod) ??
          AppConstants.uiUpdatePeriodDefaultMs,
      gpsInterval:
          prefs.getInt(AppConstants.prefGpsUpdateInterval) ??
          AppConstants.gpsUpdateIntervalDefaultSec,
      compassMode: compassMode,
      autoSwitchSpeedKmh: autoSwitchSpeedKmh,
      gpsAveragingSamples:
          prefs.getInt(AppConstants.prefGpsAveragingSamples) ??
          AppConstants.gpsAveragingSamplesDefault,
    );
  }

  Future<void> saveCompassMode(CompassMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(AppConstants.prefCompassMode, mode.index);
  }

  Future<void> saveAutoSwitchSpeed(double speedKmh) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(AppConstants.prefAutoSwitchSpeedKmh, speedKmh);
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
