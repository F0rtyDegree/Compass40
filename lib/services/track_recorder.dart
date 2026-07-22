// ignore_for_file: avoid_print

import '../controllers/home_state.dart';
import 'dart:async';
import 'dart:io';
import 'package:gps_info/gps_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/gps_manager.dart';
import '../services/sensor_service.dart'; // <-- добавить

class TrackRecorder {
  static final TrackRecorder _instance = TrackRecorder._();
  factory TrackRecorder() => _instance;
  TrackRecorder._();

  final GpsManager _gpsManager = GpsManager();
  StreamSubscription<GpsData>? _subscription;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String? _csvPath;
  int _pointCount = 0;
  static const int _saveThreshold = 20;

  Future<void> start() async {
    if (_isRecording) return;

    final prefs = await SharedPreferences.getInstance();
    final dir = Directory('/storage/emulated/0/Download/Compass40');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final existingCsv = File('${dir.path}/track_points.csv');
    if (await existingCsv.exists()) {
      _csvPath = existingCsv.path;
      final lines = await existingCsv.readAsLines();
      _pointCount = lines.length;
    } else {
      _csvPath = '${dir.path}/track_points.csv';
      await existingCsv.create(recursive: true);
      await existingCsv.writeAsString('');
      _pointCount = 0;
    }

    _isRecording = true;
    await prefs.setBool('isRecordingTrack', true);

    final settings = await _loadSettings();
    _subscription = _gpsManager.subscribe(
      intervalSeconds: settings.gpsInterval,
      onData: _onGpsData,
    );
  }

  Future<SensorSettings> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return SensorSettings(
      useManualDeclination: prefs.getBool('useManualDeclination') ?? false,
      magneticDeclination: prefs.getDouble('manualDeclination') ?? 0.0,
      averagingPeriod: prefs.getInt('averagingPeriod') ?? 500,
      smoothingFactor: prefs.getDouble('smoothingFactor') ?? 0.5,
      uiUpdatePeriod: prefs.getInt('uiUpdatePeriod') ?? 250,
      gpsInterval: prefs.getInt('gpsUpdateInterval') ?? 1,
      compassMode: CompassMode.values[prefs.getInt('compassMode') ?? 0],
      autoSwitchSpeedKmh: prefs.getDouble('autoSwitchSpeedKmh') ?? 3.0,
      gpsAveragingSamples: prefs.getInt('gpsAveragingSamples') ?? 3,
    );
  }

  void _onGpsData(GpsData data) {
    if (!_isRecording) return;
    if (data.latitude == null || data.longitude == null) return;

    final lat = data.latitude!;
    final lon = data.longitude!;
    final time = DateTime.now().toUtc().toIso8601String();

    final line = '$time,$lat,$lon\n';
    final file = File(_csvPath!);
    file.writeAsStringSync(line, mode: FileMode.append);
    print('[TrackRecorder] wrote point: $line');

    _pointCount++;
    if (_pointCount >= _saveThreshold) {
      _pointCount = 0;
    }
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _subscription?.cancel();
    _subscription = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isRecordingTrack', false);
  }

  static Future<bool> recoverIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final wasRecording = prefs.getBool('isRecordingTrack') ?? false;

    final dir = Directory('/storage/emulated/0/Download/Compass40');
    if (!await dir.exists()) return false;

    final csvFile = File('${dir.path}/track_points.csv');
    if (await csvFile.exists()) {
      return wasRecording;
    }
    return false;
  }

  Future<List<(String time, double lat, double lon)>> getTrackPoints() async {
    if (_csvPath == null) return [];
    final file = File(_csvPath!);
    if (!await file.exists()) return [];

    final lines = await file.readAsLines();
    final points = <(String, double, double)>[];
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final parts = line.split(',');
      if (parts.length != 3) continue;
      final time = parts[0];
      final lat = double.tryParse(parts[1]);
      final lon = double.tryParse(parts[2]);
      if (lat != null && lon != null) {
        points.add((time, lat, lon));
      }
    }
    return points;
  }
  Future<void> clear() async {
    if (_csvPath == null) return;
    final file = File(_csvPath!);
    if (await file.exists()) {
      await file.delete();
    }
    _csvPath = null;
    _pointCount = 0;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isRecordingTrack', false);
  }

  /// Инициализирует состояние для восстановления записи после сбоя.
  /// Устанавливает путь к существующему CSV-файлу, чтобы последующий экспорт работал.
  Future<void> initializeForRecovery() async {
    final dir = Directory('/storage/emulated/0/Download/Compass40');
    if (!await dir.exists()) return;

    final csvFile = File('${dir.path}/track_points.csv');
    if (await csvFile.exists()) {
      _csvPath = csvFile.path;
      final lines = await csvFile.readAsLines();
      _pointCount = lines.length;
    }
  }

  Future<void> dispose() async {
    await stop();
    await clear();
  }
}