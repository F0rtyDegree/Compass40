import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_info/gps_info.dart';
import 'package:image_picker/image_picker.dart';
import '../models/map_anchor.dart';
import '../models/map_project.dart';
import '../models/map_target.dart';
import '../models/map_transform_state.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';
import '../services/sensor_service.dart';

class MapScreenLogic {
  final MapScreenState state;
  final State hostState;
  final MapStorageService storageService;
  final double magneticDeclination;
  final MapCalibrationService calibration = MapCalibrationService();
  final SensorService sensorService = SensorService();
  final Function(double lat, double lon, double? distance, String timeStr)? onAnchorAdded;
  bool _isAutoRotating = false;

  StreamSubscription<GpsData>? _gpsSub;
  GpsData? _previousGpsData;
  GpsData? _lastGpsData;
  late SensorSettings _sensorSettings;

  MapScreenLogic({
    required this.state,
    required this.hostState,
    required this.storageService,
    required this.magneticDeclination,
    this.onAnchorAdded,
  });

  bool get mounted => hostState.mounted;

  void setState(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      hostState.setState(fn);
    }
  }

  // ---------------------------------------------------------
  // Инициализация
  // ---------------------------------------------------------

  Future<void> init() async {
    _sensorSettings = await sensorService.loadSettings();
    await _loadLastProject();
    _startGpsSubscription();
  }

  void dispose() {
    state.followRestoreTimer?.cancel();
    _gpsSub?.cancel();
    state.crosshairFeedback.dispose();
    state.isDisposed = true;
  }

  // ---------------------------------------------------------
  // Загрузка проекта
  // ---------------------------------------------------------

  Future<void> _loadLastProject() async {
    final projectId = await storageService.getCurrentProjectId();
    if (projectId == null) return;

    final project = await storageService.loadProject(projectId);
    if (project == null || !mounted) return;

    final savedTransform = await storageService.loadTransform(projectId);

    setState(() {
      state.project = project;
      state.imagePath = project.imagePath;
      if (savedTransform != null) {
        state.transformState = savedTransform;
      }
      try {
        state.activeTarget = project.targets.firstWhere((t) => t.status == MapTargetStatus.active);
      } catch(e) {
        state.activeTarget = null;
      }
    });

    await _loadImageSize();
    _recalculateWorkingPairAndRotation();
    _recalculateCanPlaceTarget();
  }

  Future<void> _loadImageSize() async {
    if (state.imagePath == null) return;
    final file = File(state.imagePath!);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final decoded = await decodeImageFromList(bytes);

    if (!mounted) return;

    final imgW = decoded.width.toDouble();
    final imgH = decoded.height.toDouble();

    setState(() {
      state.imageSize = Size(imgW, imgH);
    });

    if (state.transformState.scale == 1.0 &&
        state.transformState.translation == Offset.zero) {
      _waitForViewportAndFit(imgW, imgH);
    }
  }

  void _waitForViewportAndFit(double imgW, double imgH) {
    if (state.viewportSize != null) {
      _fitImageToViewport(imgW, imgH);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!state.isDisposed) {
        _waitForViewportAndFit(imgW, imgH);
      }
    });
  }

  void _fitImageToViewport(double imgW, double imgH) {
    final vp = state.viewportSize;
    if (vp == null || imgW == 0 || imgH == 0) return;

    final fitScale = math.min(vp.width / imgW, vp.height / imgH) * 0.92;

    if (!mounted) return;

    setState(() {
      state.transformState = MapTransformState(
        scale: fitScale,
        rotationRadians: 0,
        translation: Offset.zero,
      );
    });

    _recalculateCrosshairImagePoint();
  }

  // ---------------------------------------------------------
  // Выбор фото
  // ---------------------------------------------------------

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null || !mounted) return;

      final savedPath = await storageService.saveImageToAppStorage(image.path);
      final projectId = DateTime.now().millisecondsSinceEpoch.toString();
      final project = MapProject(
        id: projectId,
        imagePath: savedPath,
        anchors: [],
        targets: [],
      );

      await storageService.saveProject(project);
      await storageService.setCurrentProjectId(projectId);

      setState(() {
        state.project = project;
        state.imagePath = savedPath;
        state.imageSize = null;
        state.workingPair = null;
        state.canPlaceTarget = false;
        state.transformState = const MapTransformState();
        state.plannedTarget = null;
        state.activeTarget = null;
      });

      await _loadImageSize();
    } catch (e) {
      debugPrint('MapScreenLogic.pickImage error: $e');
    }
  }

  // ---------------------------------------------------------
  // Закрытие карты
  // ---------------------------------------------------------

  Future<void> closeMap() async {
    await storageService.setCurrentProjectId(null);
    if (!mounted) return;

    setState(() {
      state.project = null;
      state.imagePath = null;
      state.imageSize = null;
      state.workingPair = null;
      state.canPlaceTarget = false;
      state.transformState = const MapTransformState();
      state.plannedTarget = null;
      state.activeTarget = null;
      state.currentUserImagePoint = null;
      state.currentUserScreenPoint = null;
    });
  }

  // ---------------------------------------------------------
  // Трансформация карты
  // ---------------------------------------------------------

  void updateTransform(MapTransformState newTransform) {
    setState(() {
      state.transformState = newTransform;
    });

    if (state.followMode && !_isAutoRotating) {
      disableFollowMode();
    }

    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();

    if (state.project != null) {
      storageService.saveTransform(state.project!.id, newTransform);
    }
  }

  void updateViewportSize(Size size) {
    if (state.viewportSize == size) return;
    setState(() {
      state.viewportSize = size;
    });
    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();
  }

  // ---------------------------------------------------------
  // Прицел
  // ---------------------------------------------------------

  Offset getCrosshairScreenPoint() => _getCrosshairScreenPoint();

  void toggleCrosshairPosition() {
    setState(() {
      state.crosshairInCenter = !state.crosshairInCenter;
    });
    _recalculateCrosshairImagePoint();
  }

  Future<void> copyCrosshairCoordinatesToClipboard() async {
    if (state.workingPair == null || state.crosshairImagePoint == null) return;

    final geo = calibration.imagePointToGeo(
      imagePoint: state.crosshairImagePoint!,
      pair: state.workingPair!,
    );

    if (geo != null) {
      final lat = geo.latitude.toStringAsFixed(6);
      final lon = geo.longitude.toStringAsFixed(6);
      await Clipboard.setData(ClipboardData(text: '$lat, $lon'));

      state.crosshairFeedback.value = true;
      Future.delayed(const Duration(milliseconds: 200), () {
        if (!state.isDisposed) {
          state.crosshairFeedback.value = false;
        }
      });
    }
  }

  Offset _getCrosshairScreenPoint() {
    if (state.viewportSize == null) return Offset.zero;
    final vp = state.viewportSize!;
    if (state.crosshairInCenter) {
      return Offset(vp.width / 2, vp.height / 2);
    } else {
      return Offset(vp.width / 2, vp.height * 3 / 4);
    }
  }

  void _recalculateCrosshairImagePoint() {
    if (state.imageSize == null || state.viewportSize == null) return;

    final screenPoint = _getCrosshairScreenPoint();
    final imagePoint = screenToImage(screenPoint);

    setState(() {
      state.crosshairScreenPoint = screenPoint;
      state.crosshairImagePoint = imagePoint;
    });
  }

  // ---------------------------------------------------------
  // Преобразования screen ↔ image
  // ---------------------------------------------------------

  Offset screenToImage(Offset screenPoint) {
    if (state.imageSize == null || state.viewportSize == null) {
      return screenPoint;
    }

    final vp = state.viewportSize!;
    final t = state.transformState;
    final imageSize = state.imageSize!;

    final center = Offset(vp.width / 2, vp.height / 2);
    final relative = screenPoint - center - t.translation;

    final angle = -t.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final derotated = Offset(
      relative.dx * cos - relative.dy * sin,
      relative.dx * sin + relative.dy * cos,
    );

    final unscaled = derotated / t.scale;
    return unscaled + Offset(imageSize.width / 2, imageSize.height / 2);
  }

  Offset imageToScreen(Offset imagePoint) {
    if (state.imageSize == null || state.viewportSize == null) {
      return imagePoint;
    }

    final vp = state.viewportSize!;
    final t = state.transformState;
    final imageSize = state.imageSize!;

    final center = Offset(vp.width / 2, vp.height / 2);
    final local =
        imagePoint - Offset(imageSize.width / 2, imageSize.height / 2);
    final scaled = local * t.scale;

    final angle = t.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );

    return center + t.translation + rotated;
  }

  // ---------------------------------------------------------
  // Якоря
  // ---------------------------------------------------------

  Future<void> addAnchorFromCurrentGps() async {
    final gpsData = _lastGpsData;
    if (gpsData?.latitude == null || gpsData?.longitude == null) {
      _showSnackBar('Нет сигнала GPS');
      return;
    }
    if (state.crosshairImagePoint == null) {
      _showSnackBar('Прицел не определён');
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
      _showSnackBar('Ошибка чтения буфера обмена');
      return;
    }

    if (clipboardData?.text == null) {
      _showSnackBar('Буфер обмена пуст');
      return;
    }

    final parts = clipboardData!.text!.split(',');
    if (parts.length != 2) {
      _showSnackBar('Неверный формат. Ожидается: широта,долгота');
      return;
    }

    final lat = double.tryParse(parts[0].trim());
    final lon = double.tryParse(parts[1].trim());

    if (lat == null || lon == null) {
      _showSnackBar('Не удалось распознать координаты');
      return;
    }

    if (state.crosshairImagePoint == null) {
      _showSnackBar('Прицел не определён');
      return;
    }

    await _addAnchor(
      imagePoint: state.crosshairImagePoint!,
      latitude: lat,
      longitude: lon,
    );
  }

  Future<void> _addAnchor({
  required Offset imagePoint,
  required double latitude,
  required double longitude,
}) async {
  final project = state.project;
  if (project == null) return;

  double? distanceFromPrevious;
  if (project.anchors.isNotEmpty) {
    final lastAnchor = project.anchors.last;
    distanceFromPrevious = calibration.distanceBetweenAnchorsMeters(lastAnchor, MapAnchor(
      id: '',
      imageX: imagePoint.dx,
      imageY: imagePoint.dy,
      latitude: latitude,
      longitude: longitude,
      createdAt: DateTime.now(),
    ));
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
  final updatedProject = project.copyWith(anchors: updatedAnchors);

  await storageService.saveProject(updatedProject);

  setState(() {
    state.project = updatedProject;
  });

  _recalculateWorkingPairAndRotation();
  _recalculateCanPlaceTarget();
  _recalculateUserImagePoint();
  recalculateTargetsAfterNewAnchor();

  if (onAnchorAdded != null) {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    await onAnchorAdded!(latitude, longitude, distanceFromPrevious, timeStr);
  }

  final anchorNum = updatedAnchors.length;
  _showSnackBar('Привязка #$anchorNum добавлена. Всего: $anchorNum');
}
  // ---------------------------------------------------------
  // Цели
  // ---------------------------------------------------------

  void placePlannedTargetAtCrosshair() {
    if (!state.canPlaceTarget) return;
    if (state.crosshairImagePoint == null) return;

    final geo = calibration.imagePointToGeo(
      imagePoint: state.crosshairImagePoint!,
      pair: state.workingPair!,
    );

    final target = MapTarget(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: state.crosshairImagePoint!.dx,
      imageY: state.crosshairImagePoint!.dy,
      latitude: geo?.latitude,
      longitude: geo?.longitude,
      status: MapTargetStatus.planned,
      createdAt: DateTime.now(),
    );

    setState(() {
      state.plannedTarget = target;
    });
  }

  void cancelPlannedTarget() {
    setState(() {
      state.plannedTarget = null;
    });
  }

  Future<void> activatePlannedTarget() async {
    final planned = state.plannedTarget;
    if (planned == null) return;

    final project = state.project;
    if (project == null) return;

    if (planned.latitude == null || planned.longitude == null) {
      _showSnackBar('Координаты цели не определены — добавьте привязку');
      return;
    }

    final updatedTargets = project.targets.map((t) {
      if (t.status == MapTargetStatus.active) {
        return t.copyWith(status: MapTargetStatus.passed);
      }
      return t;
    }).toList();

    final activeTarget = planned.copyWith(status: MapTargetStatus.active);

    updatedTargets.add(activeTarget);

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
      state.activeTarget = activeTarget;
      state.plannedTarget = null;
    });

    _recalculatePreview();
  }

  void markActiveTargetAsPassed() async {
    final active = state.activeTarget;
    if (active == null) return;

    final project = state.project;
    if (project == null) return;

    final updatedTargets = project.targets.map((t) {
      if (t.id == active.id) {
        return t.copyWith(status: MapTargetStatus.passed);
      }
      return t;
    }).toList();

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
      state.activeTarget = null;
    });
  }

  // ---------------------------------------------------------
  // Пересчёты
  // ---------------------------------------------------------

  void _recalculateWorkingPairAndRotation() {
    final anchors = state.project?.anchors ?? [];
    final newPair = calibration.selectWorkingPair(anchors);

    setState(() {
      state.workingPair = newPair;
      if (newPair != null) {
        state.mapRotation = calibration.getMapRotation(newPair) ?? 0.0;
      } else {
        state.mapRotation = 0.0;
      }
    });
  }

  void _recalculateCanPlaceTarget() {
    setState(() {
      state.canPlaceTarget = state.workingPair != null;
    });
  }

  void _recalculateUserImagePoint() {
    final gps = _lastGpsData;
    if (gps?.latitude == null || state.workingPair == null) return;

    final imagePoint = calibration.geoToImagePoint(
      latitude: gps!.latitude!,
      longitude: gps.longitude!,
      pair: state.workingPair!,
    );
    if (imagePoint == null) return;

    setState(() {
      state.currentUserImagePoint = imagePoint;
    });
    _recalculateUserScreenPoint();
    _recalculatePreview();
  }

  void _recalculateUserScreenPoint() {
    final imagePoint = state.currentUserImagePoint;
    if (imagePoint == null) return;

    setState(() {
      state.currentUserScreenPoint = imageToScreen(imagePoint);
    });
  }

  void _recalculatePreview() {
    final gps = _lastGpsData;
    final active = state.activeTarget;

    if (gps?.latitude == null || active?.latitude == null) {
      setState(() {
        state.previewDistanceMeters = null;
        state.previewBearingDegrees = null;
      });
      return;
    }

    final bd = calibration.bearingAndDistance(
      fromLat: gps!.latitude!,
      fromLon: gps.longitude!,
      toLat: active!.latitude!,
      toLon: active.longitude!,
      magneticDeclination: magneticDeclination,
    );

    setState(() {
      state.previewDistanceMeters = bd.distanceMeters;
      state.previewBearingDegrees = bd.magneticBearing;
    });
  }

  void recalculateTargetsAfterNewAnchor() {
    final project = state.project;
    final pair = state.workingPair;
    if (project == null || pair == null) return;

    final updatedTargets = project.targets.map((t) {
      final geo = calibration.imagePointToGeo(
        imagePoint: Offset(t.imageX, t.imageY),
        pair: pair,
      );
      if (geo == null) return t;
      return t.copyWith(latitude: geo.latitude, longitude: geo.longitude);
    }).toList();

    final updatedProject = project.copyWith(targets: updatedTargets);
    storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
       try {
        state.activeTarget = updatedTargets.firstWhere((t) => t.status == MapTargetStatus.active);
      } catch(e) {
        state.activeTarget = null;
      }
    });
  }

  // ---------------------------------------------------------
  // Follow mode
  // ---------------------------------------------------------

  void enableFollowMode() {
    state.followRestoreTimer?.cancel();
    setState(() => state.followMode = true);
    _applyHeadingRotation();
  }

  void disableFollowMode() {
    state.followRestoreTimer?.cancel();
    setState(() => state.followMode = false);

    // state.followRestoreTimer = Timer(const Duration(seconds: 60), () {
    //   if (!state.isDisposed && mounted) {
    //     setState(() => state.followMode = true);
    //     _centerMapOnUser();
    //   }
    // });
  }

  void toggleFollowMode() {
    if (state.followMode) {
      disableFollowMode();
    } else {
      enableFollowMode();
    }
  }

  void _centerMapOnUser() {
    final imagePoint = state.currentUserImagePoint;
    if (imagePoint == null || state.viewportSize == null) return;

    final crosshairScreen = _getCrosshairScreenPoint();
    final vp = state.viewportSize!;
    final vpCenter = Offset(vp.width / 2, vp.height / 2);
    final targetTranslation = crosshairScreen - vpCenter;

    final t = state.transformState;
    final imageSize = state.imageSize;
    if (imageSize == null) return;

    final local =
        imagePoint - Offset(imageSize.width / 2, imageSize.height / 2);
    final scaled = local * t.scale;

    final angle = t.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );

    final newTranslation = targetTranslation - rotated;

    setState(() {
      state.transformState = t.copyWith(translation: newTranslation);
    });

    _recalculateUserScreenPoint();
  }

  // ---------------------------------------------------------
  // GPS подписка
  // ---------------------------------------------------------

  void _startGpsSubscription() {
    _gpsSub = sensorService.subscribeToGps(
      intervalSeconds: 1,
      onData: (gpsData) {
        _lastGpsData = gpsData;
        if (!mounted) return;

        if (_previousGpsData?.latitude != null && (gpsData.speed ?? 0) * 3.6 > _sensorSettings.autoSwitchSpeedKmh) {
          final bd = calibration.bearingAndDistance(
            fromLat: _previousGpsData!.latitude!,
            fromLon: _previousGpsData!.longitude!,
            toLat: gpsData.latitude!,
            toLon: gpsData.longitude!,
            magneticDeclination: magneticDeclination,
          );
          setState(() {
            state.heading = bd.magneticBearing;
          });

          if (state.followMode) {
            _applyHeadingRotation();
          }
        }
        _previousGpsData = gpsData;

        if (state.followMode) {
          _recalculateUserImagePoint();
          _centerMapOnUser();
        } else {
          _recalculateUserImagePoint();
        }
      },
    );
  }

  // ---------------------------------------------------------
  // Вспомогательные
  // ---------------------------------------------------------

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(hostState.context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _applyHeadingRotation() {
    if (!state.followMode || state.heading == null) return;

    _isAutoRotating = true;

    // True North = Magnetic North + Declination
    final magneticHeadingRad = (state.heading!) * (math.pi / 180);
    final declinationRad = magneticDeclination * (math.pi / 180);
    final trueHeadingRad = magneticHeadingRad + declinationRad;

    final targetRotation = -trueHeadingRad + state.mapRotation;

    final current = state.transformState;
    final pivotImage = screenToImage(_getCrosshairScreenPoint());

    final tempTransform = current.copyWith(rotationRadians: targetRotation);
    final oldTransform = state.transformState;
    state.transformState = tempTransform;
    final pivotScreenAfterRotate = imageToScreen(pivotImage);
    state.transformState = oldTransform;

    final delta = _getCrosshairScreenPoint() - pivotScreenAfterRotate;
    final newTranslation = current.translation + delta;

    updateTransform(
      current.copyWith(
        rotationRadians: targetRotation,
        translation: newTranslation,
      ),
    );

    _isAutoRotating = false;
  }
}
