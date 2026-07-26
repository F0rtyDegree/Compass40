import 'dart:async';
import 'dart:developer' as developer;

import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/home_state.dart';
import '../utils/app_constants.dart';

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  final GpsInfo _gpsInfo = GpsInfo();

  // Компас
  Stream<List<double>>? _compassBroadcastStream;

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
      averagingPeriod:
          prefs.getInt('averagingPeriod') ??
          AppConstants.sensorStabilizationDefaultMs,
      smoothingFactor: prefs.getDouble('smoothingFactor') ?? AppConstants.smoothingFactorDefault,
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
            developer.log(
              'GPS stream error',
              name: 'by.fortydegree.compass40',
              error: error,
              stackTrace: stack,
            );
          },
        );
  }

  // ------------------------------------------------------------
  // Компас
  // ------------------------------------------------------------
  Stream<List<double>> _getOrCreateCompassStream() {
    _compassBroadcastStream ??= MyCompass.events.asBroadcastStream();
    return _compassBroadcastStream!;
  }

  StreamSubscription<List<double>> subscribeToCompass({
    required void Function(List<double> data) onData,
  }) {
    return _getOrCreateCompassStream().listen(
      onData,
      onError: (error, stack) {
        developer.log(
          'Compass stream error',
          name: 'by.fortydegree.compass40',
          error: error,
          stackTrace: stack,
        );
      },
    );
  }
}

class SensorSettings {
  final bool useManualDeclination;
  final double magneticDeclination;
  final int averagingPeriod;
  final double smoothingFactor;
  final int uiUpdatePeriod;
  final int gpsInterval;
  final CompassMode compassMode;
  final double autoSwitchSpeedKmh;
  final int
  gpsAveragingSamples; // количество сэмплов для GPS-усреднения (по умолчанию 3)

  SensorSettings({
    required this.useManualDeclination,
    required this.magneticDeclination,
    required this.averagingPeriod,
    required this.smoothingFactor,
    required this.uiUpdatePeriod,
    required this.gpsInterval,
    required this.compassMode,
    required this.autoSwitchSpeedKmh,
    this.gpsAveragingSamples = AppConstants.gpsAveragingSamplesDefault,
  });
}
