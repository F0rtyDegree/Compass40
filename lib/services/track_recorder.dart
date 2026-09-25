// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:gps_info/gps_info.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/gps_manager.dart';
import '../utils/app_constants.dart';

/// Запись точек трека в CSV-файл.
///
/// Юнит-тесты не покрываются осознанно: класс завязан на жёсткие пути
/// Android (`/storage/emulated/0/Download`), синглтон GpsManager и
/// SharedPreferences. Стоимость рефакторинга под тесты выше пользы —
/// функционал некритичный, проверяется вручную.
class TrackRecorder {
  static final TrackRecorder _instance = TrackRecorder._();
  factory TrackRecorder() => _instance;
  TrackRecorder._();

  final GpsManager _gpsManager = GpsManager();
  StreamSubscription<GpsData>? _subscription;

  bool _isRecording = false;
  bool get isRecording => _isRecording;

  String? _csvPath;
  final List<String> _pendingLines = [];
  static const int _saveThreshold = 20;

  Future<void> start() async {
    if (_isRecording) return;

    final prefs = await SharedPreferences.getInstance();
     final dir = Directory(
      '${AppConstants.externalDownloadDir}/${AppConstants.compassFolderName}',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    _pendingLines.clear();

    // Если CSV уже существует — дописываем к нему. Осознанно:
    // 1. При восстановлении после сбоя точки продолжают ту же сессию.
    // 2. При обычном старте CSV обычно пуст — previous сессия
    //    удаляется после экспорта в GPX (см. finalizeTrackAndExport).
    // 3. Если приложение упало до экспорта, старые точки остаются
    //    и попадут в новую сессию. Это лучше, чем потерять их.
    final existingCsv = File('${dir.path}/${AppConstants.trackFileName}');
    if (await existingCsv.exists()) {
      _csvPath = existingCsv.path;
    } else {
      _csvPath = '${dir.path}/${AppConstants.trackFileName}';
      await existingCsv.create(recursive: true);
      await existingCsv.writeAsString('');
    }

    _isRecording = true;
    await prefs.setBool(AppConstants.prefIsRecordingTrack, true);

    _subscription = _gpsManager.gpsStream.listen(_onGpsData);
  }
  
  void _onGpsData(GpsData data) {
      
    // ВАЖНО: 
    // Все временные метки  включая точки трека и вручную созданные точки (ТП),
    // должны быть в одной системе отсчета для корректной интерполяции и сопоставления.
    // Использование разных источников времени (системного и GPS) привело бы к рассинхронизации.
    // Потому используется системное время телефона (DateTime.now()), а не время из GPS-пакета (data.time).
    // Это сделано намеренно для обеспечения единой временной шкалы во всем приложении.
    
    final time = DateTime.now().toUtc().toIso8601String();

    if (!_isRecording) return;
    if (data.latitude == null || data.longitude == null) return;

    final lat = data.latitude!;
    final lon = data.longitude!;

    _pendingLines.add('$time,$lat,$lon\n');

    if (_pendingLines.length >= _saveThreshold) {
      unawaited(_flushBuffer());
    }
  }

  Future<void> _flushBuffer() async {
    if (_pendingLines.isEmpty || _csvPath == null) return;
    final lines = _pendingLines.join();
    _pendingLines.clear();
    await File(_csvPath!).writeAsString(lines, mode: FileMode.append);
  }

  /// Принудительно сбрасывает буфер в CSV, не дожидаясь заполнения.
  /// Нужен перед перечитыванием файла, чтобы последние точки не потерялись.
  Future<void> flushPending() async {
    await _flushBuffer();
  }

  Future<void> stop() async {
    if (!_isRecording) return;
    _isRecording = false;
    await _subscription?.cancel();
    _subscription = null;
    await _flushBuffer();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefIsRecordingTrack, false);
  }

  static Future<bool> recoverIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final wasRecording =
        prefs.getBool(AppConstants.prefIsRecordingTrack) ?? false;

    final dir = Directory(
      '${AppConstants.externalDownloadDir}/${AppConstants.compassFolderName}',
    );
    if (!await dir.exists()) return false;

    final csvFile = File('${dir.path}/${AppConstants.trackFileName}');
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
    _pendingLines.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.prefIsRecordingTrack, false);
  }

  /// Инициализирует состояние для восстановления записи после сбоя.
  /// Устанавливает путь к существующему CSV-файлу, возобновляет запись
  /// и подписку на GPS. Новые точки дописываются в тот же файл.
  Future<void> initializeForRecovery() async {
    final dir = Directory(
      '${AppConstants.externalDownloadDir}/${AppConstants.compassFolderName}',
    );
    if (!await dir.exists()) return;

    final csvFile = File('${dir.path}/${AppConstants.trackFileName}');
    if (await csvFile.exists()) {
      _csvPath = csvFile.path;
    }

    _isRecording = true;
    _subscription = _gpsManager.gpsStream.listen(_onGpsData);
  }

  Future<void> dispose() async {
    await stop();
    await clear();
  }
}