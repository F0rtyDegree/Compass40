import 'dart:async';
import 'dart:developer' as developer;

import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../controllers/home_state.dart';

/// Обертка над реальной подпиской для корректного управления жизненным циклом.
/// Гарантирует вызов callback'а onCancel при отмене и предотвращает двойную отмену.
class _WrappedSubscription<T> implements StreamSubscription<T> {
  final StreamSubscription<T> _inner;
  final void Function()? onCancel;
  bool _isCanceled = false;

  _WrappedSubscription(this._inner, {this.onCancel});

  @override
  Future<void> cancel() async {
    if (_isCanceled) return;
    _isCanceled = true;
    await _inner.cancel();
    onCancel?.call();
  }

  @override
  void onData(void Function(T data)? handleData) => _inner.onData(handleData);

  @override
  void onError(Function? handleError) => _inner.onError(handleError);

  @override
  void onDone(void Function()? onDone) => _inner.onDone(onDone);

  @override
  void pause([Future<void>? resumeSignal]) => _inner.pause(resumeSignal);

  @override
  void resume() => _inner.resume();

  @override
  Future<E> asFuture<E>([E? defaultValue]) => _inner.asFuture(defaultValue);

  @override
  bool get isPaused => _inner.isPaused;
}

class SensorService {
  static final SensorService _instance = SensorService._internal();
  factory SensorService() => _instance;
  SensorService._internal();

  // GPS
  Stream<GpsData>? _sharedGpsStream;
  StreamSubscription<GpsData>? _sharedGpsSubscription;
  int? _sharedGpsIntervalMs;
  
  // Храним пары (подписка, коллбек) для очистки, но основная логика теперь в обертке
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
      gpsAveragingSamples: prefs.getInt('gpsAveragingSamples') ?? 3,
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

    // Закрываем старый поток
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

    // Создаем реальную подписку на поток
    final innerSubscription = _sharedGpsStream!.listen((data) {
      try {
        onData(data);
      } catch (e) {
        developer.log(
          'Error in GPS listener callback',
          name: 'by.fortydegree.compass40',
          error: e,
        );
      }
    });

    // Возвращаем обертку, которая удалит слушателя из списка при отмене
    return _WrappedSubscription(innerSubscription, onCancel: () {
      _gpsListeners.remove(onData);
      
      if (_gpsListeners.isEmpty) {
        _sharedGpsSubscription?.cancel();
        _sharedGpsSubscription = null;
        _sharedGpsStream = null;
        _sharedGpsIntervalMs = null;
        developer.log('Shared GPS stream stopped.', name: 'by.fortydegree.compass40');
      }
    });
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
  final int gpsAveragingSamples; // количество сэмплов для GPS-усреднения (по умолчанию 3)

  SensorSettings({
    required this.useManualDeclination,
    required this.magneticDeclination,
    required this.averagingPeriod,
    required this.smoothingFactor,
    required this.uiUpdatePeriod,
    required this.gpsInterval,
    required this.compassMode,
    required this.autoSwitchSpeedKmh,
    this.gpsAveragingSamples = 3,
  });
}