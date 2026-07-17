import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gps_info/gps_info.dart';
import 'sensor_service.dart';
import 'gps_manager.dart';        // <-- добавить импорт
import '../utils/angle_utils.dart';

class GpsCompassService {
  static final GpsCompassService instance = GpsCompassService._();
  GpsCompassService._();

  final GpsManager _gpsManager = GpsManager();
  StreamSubscription<GpsData>? _subscription;
  SensorSettings? _settings;       // добавить поле
  final List<double> _samples = [];
  double _filteredBearing = 0.0;
  static const int _maxSamples = 50;

  final ValueNotifier<double?> bearingNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isActiveNotifier = ValueNotifier(false);

  void start(SensorSettings settings) {
    if (_subscription != null) return;
    _settings = settings;
    _subscription = _gpsManager.subscribe(
      intervalSeconds: settings.gpsInterval,
      onData: _onGpsData,
    );
  }

  void updateSettings(SensorSettings settings) {
    _settings = settings;
    // Если подписка уже есть, можно пересоздать, но интервал не меняется динамически
    // Поэтому просто обновляем настройки.
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
    _samples.clear();
    bearingNotifier.value = null;
    isActiveNotifier.value = false;
  }

  void _onGpsData(GpsData data) {
    final speedKmh = (data.speed ?? 0) * 3.6;
    final bearing = data.gpsBearing;
    final threshold = _settings?.autoSwitchSpeedKmh ?? 3.0;

    if (bearing != null && speedKmh >= threshold) {
      _samples.add(bearing);
      if (_samples.length > _maxSamples) _samples.removeAt(0);
      _processSamples();
    } else {
      isActiveNotifier.value = false;
    }
  }

  Future<void> _processSamples() async {
    final windowSize = _settings?.gpsAveragingSamples ?? 3;
    if (_samples.length < windowSize) {
      isActiveNotifier.value = false;
      return;
    }
    isActiveNotifier.value = true;

    final recent = _samples.sublist(_samples.length - windowSize);
    final median = await calculateCircularMedian(List.from(recent));
    final smoothing = _settings?.smoothingFactor ?? 0.5;
    
    double diff = median - _filteredBearing;
    if (diff.abs() > 180) {
      diff += (diff > 0) ? -360 : 360;
    }
    
    _filteredBearing = normalizeBearing(_filteredBearing + smoothing * diff);
    bearingNotifier.value = _filteredBearing;
  }

  void dispose() {
    stop();
    bearingNotifier.dispose();
    isActiveNotifier.dispose();
  }
}