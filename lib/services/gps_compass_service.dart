import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gps_info/gps_info.dart';
import 'sensor_service.dart';
import '../utils/geo_utils.dart';

class GpsCompassService {
  static final GpsCompassService instance = GpsCompassService._();
  GpsCompassService._();

  final ValueNotifier<double?> bearingNotifier = ValueNotifier(null);
  final ValueNotifier<bool> isActiveNotifier = ValueNotifier(false);

  final SensorService _sensorService = SensorService();
  StreamSubscription<GpsData>? _gpsSub;

  final List<double> _samples = []; // хранит последние maxSamples измерений
  double _filteredBearing = 0.0;
  bool _started = false;
  static const int _maxSamples = 50; // достаточно для окна любой разумной длины

  SensorSettings? _settings;

  void start(SensorSettings settings) {
    if (_started) return;
    _started = true;
    _settings = settings;
    _gpsSub = _sensorService.subscribeToGps(
      intervalSeconds: settings.gpsInterval,
      onData: _onGpsData,
    );
  }

  void stop() {
    _gpsSub?.cancel();
    _samples.clear();
    _started = false;
    bearingNotifier.value = null;
    isActiveNotifier.value = false;
  }

  void updateSettings(SensorSettings settings) {
    _settings = settings;
    if (_started) {
      _gpsSub?.cancel();
      _gpsSub = _sensorService.subscribeToGps(
        intervalSeconds: settings.gpsInterval,
        onData: _onGpsData,
      );
    }
  }

  void _onGpsData(GpsData data) {
    final speedKmh = (data.speed ?? 0) * 3.6;
    final bearing = data.gpsBearing;
    if (bearing != null && speedKmh >= (_settings?.autoSwitchSpeedKmh ?? 3.0)) {
      _samples.add(bearing);
      if (_samples.length > _maxSamples) _samples.removeAt(0);
      _processSamples();
    }
  }

  void _processSamples() {
    final windowSize = _settings?.gpsAveragingSamples ?? 3;
    if (_samples.length < windowSize) {
      isActiveNotifier.value = false;
      return;
    }
    isActiveNotifier.value = true;

    // Берём последние windowSize сэмплов
    final recent = _samples.sublist(_samples.length - windowSize);
    final median = calculateCircularMedian(List.from(recent));
    final smoothing = _settings?.smoothingFactor ?? 0.5;
    double diff = median - _filteredBearing;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;
    _filteredBearing = (_filteredBearing + smoothing * diff) % 360;
    bearingNotifier.value = _filteredBearing;
  }

  void dispose() {
    stop();
    bearingNotifier.dispose();
    isActiveNotifier.dispose();
  }
}
