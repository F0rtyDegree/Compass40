// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:math' as math;
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'computation_service.dart';
import 'sensor_service.dart';
import '../utils/calibration_utils.dart';

class CompassData {
  final double heading;
  /// Статус калибровки: 3.0 (ок), 2.0 (идёт), 1.0 (нет), 0.0 (нет данных).
  final double accuracy;
  /// Количество посещённых секторов калибровки (0..8).
  final int calibrationProgress;
  /// Признак устаревшей калибровки: поле вокруг изменилось.
  final bool calibrationStale;
  CompassData({
    required this.heading,
    required this.accuracy,
    this.calibrationProgress = 0,
    this.calibrationStale = false,
  });
}
class CompassService {
  static final CompassService _instance = CompassService._internal();
  factory CompassService() => _instance;
  CompassService._internal();

  final List<double> _accFiltered = [0, 0, 9.81];
  static const double _accAlpha = 0.25;

  final _controller = StreamController<CompassData>.broadcast();
  Stream<CompassData> get dataStream => _controller.stream;

  StreamSubscription? _magSub;
  StreamSubscription? _accSub;

  List<double> _mag = [0.0, 0.0, 0.0];

  bool _hasMag = false;
  bool _hasAcc = false;

  static const _prefKeyX = 'compass_calib_x';
  static const _prefKeyY = 'compass_calib_y';
  static const _prefKeyZ = 'compass_calib_z';
  static const _prefKeyRangeX = 'compass_calib_range_x';
  static const _prefKeyRangeY = 'compass_calib_range_y';
  static const _prefKeyRangeZ = 'compass_calib_range_z';
  static const _prefKeyCalibrated = 'compass_calibrated';
  static const _prefKeyMagnitude = 'compass_calib_magnitude';

  double _cx = 0, _cy = 0, _cz = 0;
  bool _isCalibrated = false;

  /// Магнитуда поля (μT) на момент последней успешной калибровки.
  double _calibMagnitude = 0.0;

  /// Ожидаем накопления буфера после калибровки, чтобы зафиксировать эталон.
  bool _awaitingCalibMagnitude = false;

  /// Скользящий буфер магнитуды для вычисления устойчивого среднего.
  static const int _magnitudeBufferSize = 60;
  final List<double> _magnitudeBuffer = [];

  /// Флаг устаревшей калибровки (поле вокруг сильно изменилось).
  bool _calibrationStale = false;

  static const double _rangeThreshold = 30.0;
  static const double _recalibrationDelta = 30.0;
  static const int _sectorCount = 8;
  static const int _samplesPerSector = 5;
  static const double _minMagnitude = 5.0;

  double _minX = double.infinity, _maxX = -double.infinity;
  double _minY = double.infinity, _maxY = -double.infinity;
  double _minZ = double.infinity, _maxZ = -double.infinity;

  double _calibratedRangeX = 0;
  double _calibratedRangeY = 0;
  double _calibratedRangeZ = 0;

  final List<int> _sectorSamples = List.filled(_sectorCount, 0);

  // Сглаживание курса через cos/sin. Убирает скачок на стыке 359° -> 0°.
  double _smoothCos = 0.0;
  double _smoothSin = 0.0;
  double _headingAlpha = 0.5;
  int _medianWindowMs = 250;
  final List<(int, double)> _rawHeadingBuffer = [];

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
      _updateCalibrationBounds(e.x, e.y, e.z);
      _tryEmit();
    });
  }

  void updateSettings(SensorSettings settings) {
    final s = settings.compassSmoothness.clamp(0, 100) / 100.0;
    _headingAlpha = 0.05 + 0.85 * s;
    _medianWindowMs = (500 * (1.0 - s)).round();
  }

  void stop() {
    _magSub?.cancel();
    _accSub?.cancel();
    _magSub = null;
    _accSub = null;
    _hasMag = false;
    _hasAcc = false;
    _smoothCos = 0.0;
    _smoothSin = 0.0;
    _rawHeadingBuffer.clear();
    _mag = [0.0, 0.0, 0.0];
  }
  
  Future<void> _loadCalibration() async {
    final p = await SharedPreferences.getInstance();
    _cx = p.getDouble(_prefKeyX) ?? 0;
    _cy = p.getDouble(_prefKeyY) ?? 0;
    _cz = p.getDouble(_prefKeyZ) ?? 0;
    _calibratedRangeX = p.getDouble(_prefKeyRangeX) ?? 0;
    _calibratedRangeY = p.getDouble(_prefKeyRangeY) ?? 0;
    _calibratedRangeZ = p.getDouble(_prefKeyRangeZ) ?? 0;
    _isCalibrated = p.getBool(_prefKeyCalibrated) ?? false;
    _calibMagnitude = p.getDouble(_prefKeyMagnitude) ?? 0.0;
  }

  void _updateCalibrationBounds(double x, double y, double z) {
    if (x < _minX) _minX = x;
    if (x > _maxX) _maxX = x;
    if (y < _minY) _minY = y;
    if (y > _maxY) _maxY = y;
    if (z < _minZ) _minZ = z;
    if (z > _maxZ) _maxZ = z;

    final magnitude = math.sqrt(x * x + y * y + z * z);
    if (magnitude >= _minMagnitude) {
      final angle = math.atan2(y, x);
      final normalized = angle < 0 ? angle + 2 * math.pi : angle;
      final sector = (normalized / (2 * math.pi / _sectorCount)).floor() %
          _sectorCount;
      if (_sectorSamples[sector] < _samplesPerSector) {
        _sectorSamples[sector]++;
      }
    }

    final rangeX = _maxX - _minX;
    final rangeY = _maxY - _minY;
    final rangeZ = _maxZ - _minZ;

    if (!_isCalibrated) {
      final allSectorsVisited =
          _sectorSamples.every((c) => c >= _samplesPerSector);
      if (rangeX >= _rangeThreshold &&
          rangeY >= _rangeThreshold &&
          rangeZ >= _rangeThreshold &&
          allSectorsVisited) {
        _applyCalibration(rangeX, rangeY, rangeZ);
      }
      return;
    }

    final driftX = rangeX > _calibratedRangeX + _recalibrationDelta;
    final driftY = rangeY > _calibratedRangeY + _recalibrationDelta;
    final driftZ = rangeZ > _calibratedRangeZ + _recalibrationDelta;
    if (driftX || driftY || driftZ) {
      _resetCalibration();
    }
  }

  Future<void> _applyCalibration(
    double rangeX,
    double rangeY,
    double rangeZ,
  ) async {
    _cx = (_minX + _maxX) / 2;
    _cy = (_minY + _maxY) / 2;
    _cz = (_minZ + _maxZ) / 2;
    _calibratedRangeX = rangeX;
    _calibratedRangeY = rangeY;
    _calibratedRangeZ = rangeZ;
    _isCalibrated = true;
    _calibrationStale = false;

    // Эталон магнитуды ещё не зафиксирован: он будет вычислен
    // после накопления буфера уже с новыми офсетами.
    _calibMagnitude = 0.0;
    _awaitingCalibMagnitude = true;
    _magnitudeBuffer.clear();

    final p = await SharedPreferences.getInstance();
    await p.setDouble(_prefKeyX, _cx);
    await p.setDouble(_prefKeyY, _cy);
    await p.setDouble(_prefKeyZ, _cz);
    await p.setDouble(_prefKeyRangeX, _calibratedRangeX);
    await p.setDouble(_prefKeyRangeY, _calibratedRangeY);
    await p.setDouble(_prefKeyRangeZ, _calibratedRangeZ);
    await p.setBool(_prefKeyCalibrated, true);
    await p.remove(_prefKeyMagnitude);
  }

  Future<void> _resetCalibration() async {
    _isCalibrated = false;
    _calibratedRangeX = 0;
    _calibratedRangeY = 0;
    _calibratedRangeZ = 0;
    _minX = _minY = _minZ = double.infinity;
    _maxX = _maxY = _maxZ = -double.infinity;
    for (int i = 0; i < _sectorCount; i++) {
      _sectorSamples[i] = 0;
    }

    final p = await SharedPreferences.getInstance();
    await p.setBool(_prefKeyCalibrated, false);
  }

  /// Полный сброс калибровки: обнуляет офсеты, размахи, счётчики секторов,
  /// Полный сброс калибровки: обнуляет офсеты, размахи, счётчики секторов,
  /// сглаживание и удаляет сохранённые значения из SharedPreferences.
  Future<void> resetCalibration() async {
    _cx = 0;
    _cy = 0;
    _cz = 0;
    _calibratedRangeX = 0;
    _calibratedRangeY = 0;
    _calibratedRangeZ = 0;
    _isCalibrated = false;
    _calibMagnitude = 0.0;
    _awaitingCalibMagnitude = false;
    _calibrationStale = false;
    _magnitudeBuffer.clear();
    _minX = _minY = _minZ = double.infinity;
    _maxX = _maxY = _maxZ = -double.infinity;
    for (int i = 0; i < _sectorCount; i++) {
      _sectorSamples[i] = 0;
    }
    _smoothCos = 0.0;
    _smoothSin = 0.0;
    _rawHeadingBuffer.clear();

    final p = await SharedPreferences.getInstance();
    await p.remove(_prefKeyX);
    await p.remove(_prefKeyY);
    await p.remove(_prefKeyZ);
    await p.remove(_prefKeyRangeX);
    await p.remove(_prefKeyRangeY);
    await p.remove(_prefKeyRangeZ);
    await p.remove(_prefKeyCalibrated);
    await p.remove(_prefKeyMagnitude);
  }
  void _tryEmit() {
    if (!_hasMag || !_hasAcc) return;

    // 1. Офсеты hard iron
    final mx = _mag[0] - _cx;
    final my = _mag[1] - _cy;
    final mz = _mag[2] - _cz;

    // Магнитуда поля после вычитания офсетов.
    final magnitude = math.sqrt(mx * mx + my * my + mz * mz);
    _magnitudeBuffer.add(magnitude);
    if (_magnitudeBuffer.length > _magnitudeBufferSize) {
      _magnitudeBuffer.removeAt(0);
    }
    // Если ждём фиксации эталона после калибровки и буфер заполнен —
    // сохраняем эталон и записываем его в SharedPreferences.
    if (_isCalibrated &&
        _awaitingCalibMagnitude &&
        _magnitudeBuffer.length >= _magnitudeBufferSize) {
      _calibMagnitude =
          _magnitudeBuffer.reduce((a, b) => a + b) / _magnitudeBuffer.length;
      _awaitingCalibMagnitude = false;
      SharedPreferences.getInstance().then((p) {
        if (_calibMagnitude > 0) {
          p.setDouble(_prefKeyMagnitude, _calibMagnitude);
        }
      });
    }

    final avgMagnitude = _magnitudeBuffer.isEmpty
        ? 0.0
        : _magnitudeBuffer.reduce((a, b) => a + b) / _magnitudeBuffer.length;
    _calibrationStale = isCalibrationStale(
      isCalibrated: _isCalibrated,
      calibMagnitude: _calibMagnitude,
      avgMagnitude: avgMagnitude,
      bufferLength: _magnitudeBuffer.length,
      bufferSize: _magnitudeBufferSize,
    );

    final ax = _accFiltered[0];
    final ay = _accFiltered[1];
    final az = _accFiltered[2];

    final aNorm = math.sqrt(ax * ax + ay * ay + az * az);
    if (aNorm < 1e-6) return;

    final gx = ax / aNorm;
    final gy = ay / aNorm;
    final gz = az / aNorm;

    // 2. East = Magnetometer x Gravity
    var ex = my * gz - mz * gy;
    var ey = mz * gx - mx * gz;
    var ez = mx * gy - my * gx;
    final eNorm = math.sqrt(ex * ex + ey * ey + ez * ez);
    if (eNorm < 1e-6) return;
    ex /= eNorm;
    ey /= eNorm;
    ez /= eNorm;

    // 3. North = Gravity x East (нужна только Y-компонента)
    final ny = gz * ex - gx * ez;

    // 4. Курс
    double rawHeading = math.atan2(ey, ny) * 180 / math.pi;
    if (rawHeading < 0) rawHeading += 360;

    // 5. Медианная фильтрация по времени
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _rawHeadingBuffer.add((nowMs, rawHeading));
    if (_medianWindowMs > 0) {
      final cutoff = nowMs - _medianWindowMs;
      _rawHeadingBuffer.removeWhere((e) => e.$1 < cutoff);
    } else {
      _rawHeadingBuffer.removeRange(0, _rawHeadingBuffer.length - 1);
    }
    final medianHeading = _rawHeadingBuffer.length == 1
        ? _rawHeadingBuffer.first.$2
        : calculateCircularMedian(
            _rawHeadingBuffer.map((e) => e.$2).toList(),
          );

    // 6. Сглаживание через cos/sin
    final rad = medianHeading * math.pi / 180;
    _smoothCos =
        _smoothCos * (1 - _headingAlpha) + math.cos(rad) * _headingAlpha;
    _smoothSin =
        _smoothSin * (1 - _headingAlpha) + math.sin(rad) * _headingAlpha;

    double filteredHeading = math.atan2(_smoothSin, _smoothCos) * 180 / math.pi;
    if (filteredHeading < 0) filteredHeading += 360;

    final progress =
        _sectorSamples.where((c) => c >= _samplesPerSector).length;
    _controller.add(
      CompassData(
        heading: filteredHeading,
        accuracy: _computeAccuracy(mx, my, mz),
        calibrationProgress: progress,
        calibrationStale: _calibrationStale,
      ),
    );
  }

  /// Статус калибровки компаса.
  /// 3.0 — откалиброван (зелёный).
  /// 2.0 — идёт накопление размаха (оранжевый).
  /// 1.0 — калибровка отсутствует (красный).
  /// 0.0 — нет данных от магнитометра.
  double _computeAccuracy(double mx, double my, double mz) {
    final magnitude = math.sqrt(mx * mx + my * my + mz * mz);
    if (magnitude < 5.0) return 0.0;

    if (_isCalibrated) return 3.0;

    final rangeX = _maxX - _minX;
    final rangeY = _maxY - _minY;
    final rangeZ = _maxZ - _minZ;
    if (rangeX.isFinite &&
        rangeY.isFinite &&
        rangeZ.isFinite &&
        rangeX > 0 &&
        rangeY > 0 &&
        rangeZ > 0) {
      return 2.0;
    }
    return 1.0;
  }
}