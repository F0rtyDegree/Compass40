// ignore_for_file: avoid_print

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart';
import 'package:gps_info/gps_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import '../services/track_recorder.dart';
import '../utils/app_constants.dart';
import '../utils/gpx_parser.dart';
import '../utils/track_utils.dart';
import 'map_screen_state.dart';

/// Управляет активным треком (CSV) и загруженным GPX-треком.
class MapTrackManager {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final MapCalibrationService calibrationService;
  final ValueNotifier<GpsData> gpsDataNotifier;

  MapTrackManager({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.calibrationService,
    required this.gpsDataNotifier,
  });

  // ----------------------------------------------------------
  // Активный трек (CSV)
  // ----------------------------------------------------------

  /// Читает CSV-файл активного трека и заполняет trackImagePoints.
  Future<void> loadActiveTrackFromCsv() async {
    if (calibrationService.usedAnchorCount == 0) return;
    final points = await TrackRecorder().getTrackPoints();
    if (points.isEmpty) return;

    final imagePoints = <Offset>[];
    for (final (_, lat, lon) in points) {
      final imagePoint = calibrationService.geoToImagePointFromCurrent(lat, lon);
      if (imagePoint != null) {
        imagePoints.add(imagePoint);
      }
    }

    setState(() {
      state.trackImagePoints = pruneTrackPoints(points: imagePoints);
    });
  }

  /// Добавляет точку активного трека из GPS-потока, если идёт запись.
  void appendActiveTrackPointIfRecording(GpsData gps) {
    if (!TrackRecorder().isRecording) return;
    final lat = gps.latitude;
    final lon = gps.longitude;
    if (lat == null || lon == null) return;
    if (calibrationService.usedAnchorCount == 0) return;

    final imagePoint = calibrationService.geoToImagePointFromCurrent(lat, lon);
    if (imagePoint == null) return;

    setState(() {
      final updated = [...state.trackImagePoints, imagePoint];
      state.trackImagePoints = pruneTrackPoints(points: updated);
    });
  }

  /// Пересчитывает пиксели активного трека под текущую привязку.
  Future<void> reloadActiveTrackImagePoints() async {
    await TrackRecorder().flushPending();
    await loadActiveTrackFromCsv();
    // Возвращаем потерянную точку из GPS-потока, если она пришла
    // во время чтения CSV.
    final gps = gpsDataNotifier.value;
    appendActiveTrackPointIfRecording(gps);
  }

  /// Вызывается из HomeLogic при старте записи.
  Future<void> onRecordingStarted() async {
    await loadActiveTrackFromCsv();
  }

  /// Вызывается из HomeLogic при остановке записи.
  void onRecordingStopped() {
    setState(() {
      state.trackImagePoints = [];
    });
  }

  // ----------------------------------------------------------
  // Загруженный трек (GPX)
  // ----------------------------------------------------------

  /// Открывает файловый пикер, выбирает GPX, загружает трек.
  Future<void> pickLoadedTrack() async {
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null) return;

      final file = File(path);
      final content = await file.readAsString();
      final gpsPoints = parseTrackFromGpx(content);

      if (gpsPoints.isEmpty) {
        showSnackBar('В файле нет трека');
        return;
      }

      final project = state.project;
      if (project != null) {
        final updated = project.copyWith(loadedTrackPath: path);
        await storageService.saveProject(updated);
        setState(() {
          state.project = updated;
        });
      }

      setState(() {
        state.loadedTrackGpsPoints = gpsPoints;
      });
      _recalculateLoadedTrackImagePoints();

      showSnackBar('Трек загружен: ${gpsPoints.length} точек');
    } catch (e) {
      showSnackBar('Ошибка чтения GPX: $e');
    }
  }

  /// Удаляет загруженный трек с карты и из проекта.
  Future<void> clearLoadedTrack() async {
    final project = state.project;
    if (project != null) {
      final updated = project.copyWith(loadedTrackPath: null);
      await storageService.saveProject(updated);
      setState(() {
        state.project = updated;
      });
    }
    setState(() {
      state.loadedTrackGpsPoints = [];
      state.loadedTrackImagePoints = [];
    });
  }

  /// Загружает трек из GPX, если путь сохранён в проекте и файл существует.
  Future<void> loadLoadedTrackFromProject() async {
    final path = state.project?.loadedTrackPath;
    if (path == null) return;
    final file = File(path);
    if (!await file.exists()) {
      final project = state.project;
      if (project != null) {
        final updated = project.copyWith(loadedTrackPath: null);
        await storageService.saveProject(updated);
        setState(() {
          state.project = updated;
        });
      }
      return;
    }
    try {
      final content = await file.readAsString();
      final gpsPoints = parseTrackFromGpx(content);
      if (gpsPoints.isEmpty) return;
      setState(() {
        state.loadedTrackGpsPoints = gpsPoints;
      });
      _recalculateLoadedTrackImagePoints();
    } catch (_) {}
  }

  /// Читает цвет загруженного трека из SharedPreferences.
  Future<void> loadLoadedTrackColor() async {
    final prefs = await SharedPreferences.getInstance();
    final color = prefs.getInt(AppConstants.prefLoadedTrackColor);
    if (color == null) return;
    setState(() {
      state.loadedTrackColor = color;
    });
  }

  /// Пересчитывает пиксели загруженного трека под текущую привязку.
  void _recalculateLoadedTrackImagePoints() {
    if (state.loadedTrackGpsPoints.isEmpty) {
      setState(() {
        state.loadedTrackImagePoints = [];
      });
      return;
    }
    if (calibrationService.usedAnchorCount == 0) {
      setState(() {
        state.loadedTrackImagePoints = [];
      });
      return;
    }

    final imagePoints = <Offset>[];
    for (final gps in state.loadedTrackGpsPoints) {
      final imagePoint = calibrationService.geoToImagePointFromCurrent(
        gps.dy,
        gps.dx,
      );
      if (imagePoint != null) {
        imagePoints.add(imagePoint);
      }
    }
    setState(() {
      state.loadedTrackImagePoints = imagePoints;
    });
  }

  /// Публичный пересчёт — вызывается после смены привязки.
  void recalculateLoadedTrackImagePoints() {
    _recalculateLoadedTrackImagePoints();
  }
}