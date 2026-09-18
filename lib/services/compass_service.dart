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

  int _lastDebugPrint = 0;
  int _accEventCount = 0;

  final _controller = StreamController<CompassData>.broadcast();
  Stream<CompassData> get dataStream => _controller.stream;

  StreamSubscription? _magSub;
  StreamSubscription? _accSub;

  List<double> _mag = [0, 0, 0];
  List<double> _acc = [0, 0, 0];
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
      _acc = [e.x, e.y, e.z];
      _hasAcc = true;
      _accEventCount++;
      if (_accEventCount % 50 == 0) {
        print('ACC_RAW: x=${e.x} y=${e.y} z=${e.z} count=$_accEventCount');
      }
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
    final ax = _acc[0], ay = _acc[1], az = _acc[2];

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

    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastDebugPrint >= 1000) {
      _lastDebugPrint = now;
      final simple = math.atan2(-mx, my) * 180 / math.pi;
      final simpleNorm = simple < 0 ? simple + 360 : simple;
      print(
        'COMPASS: mag=(${mx.toStringAsFixed(1)},${my.toStringAsFixed(1)},${mz.toStringAsFixed(1)}) acc=(${ax.toStringAsFixed(1)},${ay.toStringAsFixed(1)},${az.toStringAsFixed(1)}) heading=${heading.toStringAsFixed(1)} simple=${simpleNorm.toStringAsFixed(1)}',
      );
    }

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
    final median = _circularMedian(_headingBuffer);
    double maxDev = 0;
    for (final h in _headingBuffer) {
      double d = (h - median).abs();
      if (d > 180) d = 360 - d;
      if (d > maxDev) maxDev = d;
    }
    if (maxDev <= 2) return 3.0;
    if (maxDev <= 5) return 2.0;
    if (maxDev <= 10) return 1.0;
    return 0.0;
  }

  double _circularMedian(List<double> angles) {
    final sorted = List<double>.from(angles)..sort();
    final n = sorted.length;
    if (n % 2 == 1) return sorted[n ~/ 2];
    final m1 = sorted[n ~/ 2 - 1];
    final m2 = sorted[n ~/ 2];
    if ((m2 - m1).abs() > 180) {
      double med = (m1 + m2 + 360) / 2;
      if (med >= 360) med -= 360;
      return med;
    }
    return (m1 + m2) / 2;
  }
}
