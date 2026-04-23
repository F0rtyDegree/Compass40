import 'dart:async';
import 'dart:developer' as developer;

import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/home_state.dart';

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // Broadcast стримы
  Stream<GpsData>? _gpsBroadcastStream;
  Stream<List<double>>? _compassBroadcastStream;
  int? _gpsIntervalMs;

  final GpsInfo _gpsInfo = GpsInfo();

  Future<SensorSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final useManualDeclination = prefs.getBool('useManualDeclination') ?? false;
    final magneticDeclination = useManualDeclination
        ? (prefs.getDouble('manualDeclination') ?? 0.0)
        : 0.0;

    final compassModeIndex = prefs.getInt('compassMode') ?? 0;
    final compassMode = CompassMode.values[compassModeIndex];
    final autoSwitchSpeedKmh = prefs.getDouble('autoSwitchSpeedKmh') ?? 3.0;

    return SensorSettings(
      useManualDeclination: useManualDeclination,
      magneticDeclination: magneticDeclination,
      averagingPeriod: prefs.getInt('averagingPeriod') ?? 500,
      smoothingFactor: prefs.getDouble('smoothingFactor') ?? 0.5,
      uiUpdatePeriod: prefs.getInt('uiUpdatePeriod') ?? 250,
      gpsInterval: prefs.getInt('gpsUpdateInterval') ?? 1,
      compassMode: compassMode,
      autoSwitchSpeedKmh: autoSwitchSpeedKmh,
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

  // ------------------------------------------------------------
  // GPS
  // ------------------------------------------------------------
  Stream<GpsData> _getOrCreateGpsStream(int intervalSeconds) {
    final intervalMs = intervalSeconds * 1000;
    
    if (_gpsBroadcastStream == null || _gpsIntervalMs != intervalMs) {
      _gpsIntervalMs = intervalMs;
      _gpsBroadcastStream = _gpsInfo
          .getGpsDataStream(intervalMs)
          .handleError((error, stack) {
            developer.log(
              'Error in GPS stream',
              name: 'by.fortydegree.compass40',
              error: error,
              stackTrace: stack,
            );
          })
          .asBroadcastStream();
    }
    return _gpsBroadcastStream!;
  }

  StreamSubscription<GpsData> subscribeToGps({
    required int intervalSeconds,
    required void Function(GpsData gpsData) onData,
  }) {
    return _getOrCreateGpsStream(intervalSeconds).listen(onData);
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

  SensorSettings({
    required this.useManualDeclination,
    required this.magneticDeclination,
    required this.averagingPeriod,
    required this.smoothingFactor,
    required this.uiUpdatePeriod,
    required this.gpsInterval,
    required this.compassMode,
    required this.autoSwitchSpeedKmh,
  });
}