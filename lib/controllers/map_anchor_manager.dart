import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_info/gps_info.dart';
import '../models/map_anchor.dart';
import '../models/map_project.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';

class MapAnchorManager {
  final MapCalibrationService calibrationService;
  final MapStorageService storageService;
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final Function(double lat, double lon, double? distance, String timeStr)?
  onAnchorAdded;
  final VoidCallback? onStartPhotoSever;

  GpsData? lastGpsData;
  List<Map<String, String>>? cachedGpxPoints;

  final VoidCallback onAnchorsChanged;
  final Future<void> Function({bool restartNavigation}) onRecalculateTargets;
  final Offset Function(Offset screenPoint) screenToImage;
  final double magneticDeclination;

  MapAnchorManager({
    required this.calibrationService,
    required this.storageService,
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.onAnchorsChanged,
    required this.onRecalculateTargets,
    required this.screenToImage,
    required this.magneticDeclination,
    this.onAnchorAdded,
    this.lastGpsData,
    this.onStartPhotoSever,
  });
  Future<void> _saveGpxCacheToProject(List<Map<String, String>> points) async {
    final project = state.project;
    if (project == null) return;
    final updated = project.copyWith(cachedGpxPoints: points);
    await storageService.saveProject(updated);
    setState(() {
      state.project = updated;
    });
  }

  Future<void> addAnchorFromCurrentGps() async {
    final gpsData = lastGpsData;
    if (gpsData?.latitude == null || gpsData?.longitude == null) {
      showSnackBar('Нет сигнала GPS');
      return;
    }
    if (state.crosshairImagePoint == null) {
      showSnackBar('Прицел не определён');
      return;
    }
    await _addAnchor(
      imagePoint: state.crosshairImagePoint!,
      latitude: gpsData!.latitude!,
      longitude: gpsData.longitude!,
    );
  }

  Future<void> addAnchorFromClipboard() async {
    ClipboardData? clipboardData;
    try {
      clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      showSnackBar('Ошибка чтения буфера обмена');
      return;
    }

    if (clipboardData?.text == null) {
      showSnackBar('Буфер обмена пуст');
      return;
    }

    final parts = clipboardData!.text!.split(',');
    if (parts.length != 2) {
      showSnackBar('Неверный формат. Ожидается: широта,долгота');
      return;
    }

    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());

    if (lat == null || lon == null) {
      showSnackBar('Не удалось распознать координаты');
      return;
    }

    if (state.crosshairImagePoint == null) {
      showSnackBar('Прицел не определён');
      return;
    }

    await _addAnchor(
      imagePoint: state.crosshairImagePoint!,
      latitude: lat,
      longitude: lon,
    );
  }

  void showHereOptions(BuildContext context) {
    final hasCache = cachedGpxPoints != null;
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Добавить точку'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              addAnchorFromClipboard();
            },
            child: const Text('Вставить из буфера'),
          ),
          if (hasCache)
            ...cachedGpxPoints!.map((p) {
              return SimpleDialogOption(
                onPressed: () {
                  Navigator.pop(ctx);
                  final lat = double.tryParse(p['lat']!);
                  final lon = double.tryParse(p['lon']!);
                  if (lat != null && lon != null) {
                    _addAnchor(
                      imagePoint: state.crosshairImagePoint ?? Offset.zero,
                      latitude: lat,
                      longitude: lon,
                    );
                  } else {
                    showSnackBar('Неверные координаты');
                  }
                },
                child: Text(p['name']!),
              );
            }),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              pickGpxFile(context);
            },
            child: Text(hasCache ? 'Загрузить другой GPX' : 'Выбрать из GPX'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              onStartPhotoSever?.call();
            },
            child: const Text('ФотоСевер'),
          ),
        ],
      ),
    );
  }

  Future<void> pickGpxFile(BuildContext context) async {
    try {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['gpx', 'xml'],
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      final content = await file.readAsString();
      final points = _parseGpxPoints(content);

      if (points.isEmpty) {
        showSnackBar('Файл не содержит точек');
        return;
      }

      if (!context.mounted) return;
      _saveGpxCacheToProject(points);
      _showGpxPointsList(context, points);
      cachedGpxPoints = points;
    } catch (e) {
      showSnackBar('Ошибка чтения GPX: $e');
    }
  }

  List<Map<String, String>> _parseGpxPoints(String xmlString) {
    final points = <Map<String, String>>[];
    try {
      final document = XmlDocument.parse(xmlString);
      final wpts = document.findAllElements('wpt');
      for (final wpt in wpts) {
        final lat = wpt.getAttribute('lat');
        final lon = wpt.getAttribute('lon');
        final name =
            wpt.findElements('name').firstOrNull?.innerText ?? 'Без имени';
        if (lat != null && lon != null) {
          points.add({'name': name, 'lat': lat, 'lon': lon});
        }
      }
    } catch (_) {}
    return points;
  }

  void _showGpxPointsList(
    BuildContext context,
    List<Map<String, String>> points,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Точки из GPX'),
        children: points.map((p) {
          return SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              final lat = double.tryParse(p['lat']!);
              final lon = double.tryParse(p['lon']!);
              if (lat != null && lon != null) {
                _addAnchor(
                  imagePoint: state.crosshairImagePoint ?? Offset.zero,
                  latitude: lat,
                  longitude: lon,
                );
              } else {
                showSnackBar('Неверные координаты');
              }
            },
            child: Text(p['name']!),
          );
        }).toList(),
      ),
    );
  }

  Future<void> _addAnchor({
    required Offset imagePoint,
    required double latitude,
    required double longitude,
  }) async {
    final project = state.project;
    if (project == null) return;

    final newPathJumpIndices = [...project.pathJumpIndices];
    if (project.userPath.isNotEmpty) {
      newPathJumpIndices.add(project.userPath.length);
    }

    double? distanceFromPrevious;
    if (project.anchors.isNotEmpty) {
      final lastAnchor = project.anchors.last;
      distanceFromPrevious = calibrationService.distanceBetweenAnchorsMeters(
        lastAnchor,
        MapAnchor(
          id: '',
          imageX: imagePoint.dx,
          imageY: imagePoint.dy,
          latitude: latitude,
          longitude: longitude,
          createdAt: DateTime.now(),
        ),
      );
    }

    final anchor = MapAnchor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: imagePoint.dx,
      imageY: imagePoint.dy,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
    );

    final updatedAnchors = [...project.anchors, anchor];
    MapProject updatedProject = project.copyWith(
      anchors: updatedAnchors,
      pathJumpIndices: newPathJumpIndices,
      manualMode: calibrationService.isManualMode,
      calibrationMode: calibrationService.currentMode.name,
      pinnedAnchorIds: calibrationService.pinnedAnchorIdsList,
    );

    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
    });
    // else: проект уже обновлён внутри блока ФотоСевера, ничего не делаем

    calibrationService.updateAnchors(state.project!.anchors);
    onAnchorsChanged();
    await onRecalculateTargets(restartNavigation: true);

    if (onAnchorAdded != null) {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final anchorIndices = calibrationService.activeAnchorIndices;
      final timeWithIndices = anchorIndices != null
          ? '$timeStr ($anchorIndices)'
          : timeStr;
      await onAnchorAdded!(
        latitude,
        longitude,
        distanceFromPrevious,
        timeWithIndices,
      );
    }

    final anchorNum = updatedAnchors.length;
    showSnackBar('Привязка #$anchorNum добавлена. Всего: $anchorNum');
  }

  void handleTapOnMap(Offset screenPosition) {
    final anchor = _findClosestAnchor(screenPosition);
    if (anchor != null) {
      calibrationService.toggleAnchorPinned(anchor.id);
      _saveCalibrationState();
    }
  }

  void handleLongPressOnMap(BuildContext context, Offset screenPosition) {
    final anchor = _findClosestAnchor(screenPosition);
    if (anchor != null) {
      _confirmDeleteAnchor(context, anchor);
    }
  }

  void _confirmDeleteAnchor(BuildContext context, MapAnchor anchor) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить якорь?'),
        content: Text('Точка привязки будет безвозвратно удалена.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              deleteAnchorAndUpdate(anchor.id);
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void deleteAnchorAndUpdate(String anchorId) async {
    final project = state.project;
    if (project == null) return;

    final updatedAnchors = project.anchors
        .where((a) => a.id != anchorId)
        .toList();
    final updatedProject = project.copyWith(
      anchors: updatedAnchors,
      manualMode: calibrationService.isManualMode,
      calibrationMode: calibrationService.currentMode.name,
      pinnedAnchorIds: calibrationService.pinnedAnchorIdsList,
    );
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
    });

    calibrationService.removeAnchor(anchorId);
    onAnchorsChanged();
  }

  void showModePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Режим привязки'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              calibrationService.enableManualMode();
              Navigator.pop(ctx);
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Ручной (M)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              calibrationService.setCalibrationMode(CalibrationMode.affine);
              Navigator.pop(ctx);
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Affine (A)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              calibrationService.setCalibrationMode(
                CalibrationMode.pairFarthest,
              );
              Navigator.pop(ctx);
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Farthest (F)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              calibrationService.setCalibrationMode(
                CalibrationMode.pairNearest,
              );
              Navigator.pop(ctx);
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Nearest (N)'),
          ),
        ],
      ),
    );
  }

  void _saveCalibrationState() {
    final project = state.project;
    if (project != null) {
      final updated = project.copyWith(
        manualMode: calibrationService.isManualMode,
        calibrationMode: calibrationService.currentMode.name,
        pinnedAnchorIds: calibrationService.pinnedAnchorIdsList,
      );
      storageService.saveProject(updated);
      setState(() {
        state.project = updated;
      });
    }
  }

  MapAnchor? _findClosestAnchor(Offset screenPosition) {
    final project = state.project;
    final imageSize = state.imageSize;
    final scale = state.transformState.scale;
    if (project == null || imageSize == null || scale <= 0) return null;

    const double tapRadiusScreen = 24.0;
    final double tapRadiusImage = tapRadiusScreen / scale;
    final Offset imagePoint = screenToImage(screenPosition);

    MapAnchor? closest;
    double closestDist = double.infinity;
    for (final anchor in project.anchors) {
      final double dx = anchor.imageX - imagePoint.dx;
      final double dy = anchor.imageY - imagePoint.dy;
      final double dist = math.sqrt(dx * dx + dy * dy);
      if (dist < tapRadiusImage && dist < closestDist) {
        closestDist = dist;
        closest = anchor;
      }
    }
    return closest;
  }
}
