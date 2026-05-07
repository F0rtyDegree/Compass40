import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gps_info/gps_info.dart';
import 'sensor_service.dart';

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
    final median = _calculateCircularMedian(List.from(recent));
    final smoothing = _settings?.smoothingFactor ?? 0.5;
    double diff = median - _filteredBearing;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;
    _filteredBearing = (_filteredBearing + smoothing * diff) % 360;
    bearingNotifier.value = _filteredBearing;
  }

  double _calculateCircularMedian(List<double> samples) {
    if (samples.isEmpty) return 0.0;
    if (samples.length == 1) return samples[0];
    samples.sort();
    double maxGap = 0;
    int maxGapIndex = -1;
    for (int i = 0; i < samples.length - 1; i++) {
      final gap = samples[i + 1] - samples[i];
      if (gap > maxGap) {
        maxGap = gap;
        maxGapIndex = i;
      }
    }
    final wrapAroundGap = (samples.first + 360) - samples.last;
    if (wrapAroundGap > maxGap) {
      maxGap = wrapAroundGap;
      maxGapIndex = samples.length - 1;
    }
    List<double> shiftedSamples;
    if (maxGapIndex == samples.length - 1) {
      shiftedSamples = List.from(samples);
    } else {
      shiftedSamples = [];
      final shiftPoint = samples[maxGapIndex];
      for (final s in samples) {
        shiftedSamples.add(s > shiftPoint ? s : s + 360);
      }
    }
    int mid = shiftedSamples.length ~/ 2;
    double median = shiftedSamples.length % 2 == 1
        ? shiftedSamples[mid]
        : (shiftedSamples[mid - 1] + shiftedSamples[mid]) / 2.0;
    return median % 360;
  }

  void dispose() {
    stop();
    bearingNotifier.dispose();
    isActiveNotifier.dispose();
  }
}
