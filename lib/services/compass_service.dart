// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CompassData {
  final double heading;
  final double accuracy;
  CompassData({required this.heading, required this.accuracy});
}

class CompassService {
  static final CompassService _instance = CompassService._internal();
  factory CompassService() => _instance;
  CompassService._internal();

  final List<double> _accFiltered = [0, 0, 9.81];
  static const double _accAlpha = 0.3;
  final _controller = StreamController<CompassData>.broadcast();
  Stream<CompassData> get dataStream => _controller.stream;

  StreamSubscription? _magSub;
  StreamSubscription? _accSub;

  List<double> _mag = [0, 0, 0];
  bool _hasMag = false;
  bool _hasAcc = false;

  static const _prefKeyX = 'compass_calib_x';
  static const _prefKeyY = 'compass_calib_y';
  static const _prefKeyZ = 'compass_calib_z';
  double _cx = 0, _cy = 0, _cz = 0;

  bool _isCalibrating = false;
  double _minX = double.infinity, _maxX = -double.infinity;
  double _minY = double.infinity, _maxY = -double.infinity;
  double _minZ = double.infinity, _maxZ = -double.infinity;

  final List<double> _headingBuffer = [];
  static const int _bufferSize = 20;

  void start() {
    if (_magSub != null) stop();

    _loadCalibration();

    _accSub = accelerometerEventStream().listen((e) {
      _accFiltered[0] = _accFiltered[0] * (1 - _accAlpha) + e.x * _accAlpha;
      _accFiltered[1] = _accFiltered[1] * (1 - _accAlpha) + e.y * _accAlpha;
      _accFiltered[2] = _accFiltered[2] * (1 - _accAlpha) + e.z * _accAlpha;
      _hasAcc = true;
    });

    _magSub = magnetometerEventStream().listen((e) {
      _mag = [e.x, e.y, e.z];
      _hasMag = true;
      if (_isCalibrating) _updateCalibrationBounds(e.x, e.y, e.z);
      _tryEmit();
    });
  }

  void stop() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
    _hasMag = false;
    _hasAcc = false;
  }

  Future<void> _loadCalibration() async {
    final p = await SharedPreferences.getInstance();
    _cx = p.getDouble(_prefKeyX) ?? 0;
    _cy = p.getDouble(_prefKeyY) ?? 0;
    _cz = p.getDouble(_prefKeyZ) ?? 0;
  }

  void startCalibration() {
    _isCalibrating = true;
    _minX = _minY = _minZ = double.infinity;
    _maxX = _maxY = _maxZ = -double.infinity;
  }

  Future<void> finishCalibration() async {
    if (!_isCalibrating) return;
    _isCalibrating = false;
    _cx = (_minX + _maxX) / 2;
    _cy = (_minY + _maxY) / 2;
    _cz = (_minZ + _maxZ) / 2;
    final p = await SharedPreferences.getInstance();
    await p.setDouble(_prefKeyX, _cx);
    await p.setDouble(_prefKeyY, _cy);
    await p.setDouble(_prefKeyZ, _cz);
  }

  void cancelCalibration() {
    _isCalibrating = false;
  }

  bool get isCalibrating => _isCalibrating;

  void _updateCalibrationBounds(double x, double y, double z) {
    if (x < _minX) _minX = x;
    if (x > _maxX) _maxX = x;
    if (y < _minY) _minY = y;
    if (y > _maxY) _maxY = y;
    if (z < _minZ) _minZ = z;
    if (z > _maxZ) _maxZ = z;
  }

  void _tryEmit() {
    if (!_hasMag || !_hasAcc) return;

    final mx = _mag[0] - _cx;
    final my = _mag[1] - _cy;
    final mz = _mag[2] - _cz;
    final ax = _accFiltered[0];
    final ay = _accFiltered[1];
    final az = _accFiltered[2];
    final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if (aNorm < 1e-6) return;
    final gx = ax / aNorm, gy = ay / aNorm, gz = az / aNorm;

    var ex = my * gz - mz * gy;
    var ey = mz * gx - mx * gz;
    var ez = mx * gy - my * gx;
    final eNorm = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (eNorm < 1e-6) return;
    ex /= eNorm;
    ey /= eNorm;
    ez /= eNorm;

    final ny = gz * ex - gx * ez;

    double heading = math.atan2(ey, ny) * 180 / math.pi;
    if (heading < 0) heading += 360;

    _headingBuffer.add(heading);
    if (_headingBuffer.length > _bufferSize) {
      _headingBuffer.removeAt(0);
    }

    _controller.add(
      CompassData(heading: heading, accuracy: _computeAccuracy()),
    );
  }

  double _computeAccuracy() {
    if (_headingBuffer.length < 5) return 0.0;
    final deviations = <double>[];
    for (int i = 1; i < _headingBuffer.length; i++) {
      double d = (_headingBuffer[i] - _headingBuffer[i - 1]).abs();
      if (d > 180) d = 360 - d;
      if (d <= 30) deviations.add(d);
    }
    if (deviations.length < 3) return 2.0;
    deviations.sort();
    final median = deviations[deviations.length ~/ 2];
    if (median <= 0.3) return 3.0;
    if (median <= 1.0) return 2.0;
    if (median <= 2.5) return 1.0;
    return 0.0;
  }
}
