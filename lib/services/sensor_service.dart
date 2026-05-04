import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/home_state.dart';

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // GPS
  Stream<GpsData>? _sharedGpsStream;
  StreamSubscription<GpsData>? _sharedGpsSubscription;
  int? _sharedGpsIntervalMs;
  final List<void Function(GpsData)> _gpsListeners = [];

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
  void _ensureSharedGpsStream(int intervalSeconds) {
    final intervalMs = intervalSeconds * 1000;
    if (_sharedGpsStream != null && _sharedGpsIntervalMs == intervalMs) return;

    // Закрываем старый
    _sharedGpsSubscription?.cancel();
    _sharedGpsStream = null;

    _sharedGpsIntervalMs = intervalMs;
    _sharedGpsStream = _gpsInfo
        .getGpsDataStream(intervalMs)
        .handleError((error, stack) {
      developer.log(
        'Error in shared GPS stream',
        name: 'by.fortydegree.compass40',
        error: error,
        stackTrace: stack,
      );
    }).asBroadcastStream();

    _sharedGpsSubscription = _sharedGpsStream!.listen((data) {
      // Create a copy of the list to iterate over, to avoid concurrent modification issues
      final listeners = List<void Function(GpsData)>.from(_gpsListeners);
      for (final listener in listeners) {
        try {
          listener(data);
        } catch (e) {
          developer.log(
            'Error in GPS listener',
            name: 'by.fortydegree.compass40',
            error: e,
          );
        }
      }
    });
  }

  StreamSubscription<GpsData> subscribeToGps({
    required int intervalSeconds,
    required void Function(GpsData gpsData) onData,
  }) {
    _ensureSharedGpsStream(intervalSeconds);

    _gpsListeners.add(onData);

    return _GpsListenerSubscription(
      onCancel: () {
        _gpsListeners.remove(onData);
        // Optional: Stop stream if no listeners are left
        if (_gpsListeners.isEmpty) {
          _sharedGpsSubscription?.cancel();
          _sharedGpsSubscription = null;
          _sharedGpsStream = null;
          _sharedGpsIntervalMs = null;
          developer.log('Shared GPS stream stopped.', name: 'by.fortydegree.compass40');
        }
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

// Вспомогательный класс подписки
class _GpsListenerSubscription implements StreamSubscription<GpsData> {
  final VoidCallback _onCancel;
  bool _isCanceled = false;

  _GpsListenerSubscription({required VoidCallback onCancel}) : _onCancel = onCancel;

  @override
  Future<void> cancel() async {
    if (!_isCanceled) {
      _isCanceled = true;
      _onCancel();
    }
  }

  @override
  void onData(void Function(GpsData)? handleData) {}

  @override
  void onError(Function? handleError) {}

  @override
  void onDone(void Function()? handleDone) {}

  @override
  bool get isPaused => false;

  @override
  void pause([Future<void>? resumeSignal]) {}

  @override
  void resume() {}

  @override
  Future<E> asFuture<E>([E? futureValue]) async {
    // This is a simplified version. A real implementation might need a Completer.
    if (futureValue != null) {
      return futureValue;
    }
    return Completer<E>().future;
  }
}


// Класс настроек (должен быть после SensorService или до – не важно, главное чтобы был)
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