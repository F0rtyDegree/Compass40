// ignore_for_file: avoid_print

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
import '../screens/map_screen.dart';
import '../services/log_service.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import '../services/gps_compass_service.dart';
import 'map_screen_state.dart';
import '../services/sensor_service.dart';
import 'map_anchor_manager.dart';
import 'map_target_manager.dart';
import 'map_follow_controller.dart';
import 'photo_sever_controller.dart';
import '../utils/app_constants.dart';
import '../widgets/map_image_painter.dart';

class MapScreenLogic {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final double magneticDeclination;
  final ValueNotifier<double> headingNotifier;
  final MapCalibrationService _calibrationService = MapCalibrationService();
  final SensorService sensorService = SensorService();
  final LogService logService = LogService();
  final Function(double lat, double lon, double? distance, String timeStr)?
  onAnchorAdded;
  final StartNavigationCallback? onStartNavigation;
  final VoidCallback? onCancelNavigation;
  late final PhotoSeverController photoSeverController;

  StreamSubscription<GpsData>? _gpsSub;
  GpsData? _lastGpsData;
  late SensorSettings _sensorSettings;
  late final MapAnchorManager anchorManager;
  final Future<double?> Function() askDistanceDialog;
  late final MapTargetManager targetManager;
  late final MapFollowController followController;

  MapScreenLogic({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.magneticDeclination,
    required this.headingNotifier,
    this.onAnchorAdded,
    this.onStartNavigation,
    this.onCancelNavigation,
    required this.askDistanceDialog,
  });

  bool get canPlaceTarget => state.canPlaceTarget;
  bool get followMode => state.followMode;

  double? get distanceToCrosshairMeters {
    final gps = _lastGpsData;
    final lat = gps?.latitude;
    final lon = gps?.longitude;
    if (lat == null || lon == null) return null;
    final crosshair = state.crosshairImagePoint;
    if (crosshair == null) return null;
    final geo = _calibrationService.imagePointToGeoFromCurrent(crosshair);
    if (geo == null) return null;
    return _calibrationService.distanceBetweenAnchorsMeters(
      MapAnchor(
        id: '',
        imageX: 0,
        imageY: 0,
        latitude: lat,
        longitude: lon,
        createdAt: DateTime.now(),
      ),
      MapAnchor(
        id: '',
        imageX: crosshair.dx,
        imageY: crosshair.dy,
        latitude: geo.latitude,
        longitude: geo.longitude,
        createdAt: DateTime.now(),
      ),
    );
  }

  int get usedAnchorCount => _calibrationService.usedAnchorCount;
  int get totalAnchorCount => _calibrationService.totalAnchorCount;
  double? get rmseMeters => _calibrationService.rmseMeters;
  double? get selfPointErrorMeters => _calibrationService.selfPointErrorMeters;
  Set<String>? get activeAnchorIds => _calibrationService.activeAnchorIds;
  String get calibrationModeLetter => _calibrationService.calibrationModeLetter;

  double? get metersPerScreenPixel {
    final imageScale = _calibrationService.metersPerImagePixel;
    if (imageScale == null || state.transformState.scale == 0) return null;
    return imageScale / state.transformState.scale;
  }

  Future<void> init() async {
    anchorManager = MapAnchorManager(
      calibrationService: _calibrationService,
      storageService: storageService,
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      onAnchorsChanged: _recalculateWorkingPairAndRotation,
      onRecalculateTargets: recalculateTargetsAfterNewAnchor,
      screenToImage: screenToImage,
      onAnchorAdded: onAnchorAdded,
      onStartPhotoSever: () => photoSeverController.start(),
    );
    anchorManager.cachedGpxPoints = state.project?.cachedGpxPoints;
    targetManager = MapTargetManager(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      storageService: storageService,
      calibrationService: _calibrationService,
      onStartNavigation: onStartNavigation,
      onRecalculatePreview: _recalculatePreview,
    );
    followController = MapFollowController(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      magneticDeclination: magneticDeclination,
      screenToImage: screenToImage,
      imageToScreen: imageToScreen,
      updateTransform: updateTransform,
    );
    photoSeverController = PhotoSeverController(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      askDistanceDialog: askDistanceDialog,
      updateTransform: updateTransform,
      storageService: storageService,
      imageToScreen: imageToScreen,
      magneticDeclination: magneticDeclination,
    );
    await followController.loadRotateModeTimeout();
    _sensorSettings = await sensorService.loadSettings();
    _calibrationService.setMagneticDeclination(magneticDeclination);
    await _loadLastProject();
    _startGpsCompassService();
    anchorManager.cachedGpxPoints = state.project?.cachedGpxPoints;
    _startGpsSubscription();
    headingNotifier.addListener(_onHeadingChanged);
    _onHeadingChanged();
    GpsCompassService.instance.isActiveNotifier.addListener(
      _onGpsActiveChanged,
    );
    _onGpsActiveChanged(); // Инициализируем начальное состояние
  }

  void dispose() {
    headingNotifier.removeListener(_onHeadingChanged);
    GpsCompassService.instance.isActiveNotifier.removeListener(
      _onGpsActiveChanged,
    );
    if (state.project != null) {
      storageService.saveProject(state.project!);
    }
    state.rotateModeTimer?.cancel();
    state.followRestoreTimer?.cancel();
    _gpsSub?.cancel();
    state.crosshairFeedback.dispose();
    state.isDisposed = true;
  }

  // --------------------------------------------------------
  // Загрузка проекта
  // --------------------------------------------------------

  Future<void> _loadLastProject() async {
    final projectId = await storageService.getCurrentProjectId();
    if (projectId == null) return;

    final project = await storageService.loadProject(projectId);
    if (project == null) return;

    final savedTransform = await storageService.loadTransform(projectId);

    setState(() {
      state.project = project;
      state.imagePath = project.imagePath;
      if (savedTransform != null) {
        state.transformState = savedTransform;
      }
      try {
        state.activeTarget = project.targets.firstWhere(
          (t) => t.status == MapTargetStatus.active,
        );
      } catch (e) {
        state.activeTarget = null;
      }
    });

    _calibrationService.updateAnchors(project.anchors);
    _calibrationService.setPinnedAnchorIds(project.pinnedAnchorIds);
    _calibrationService.restoreState(
      mode: CalibrationMode.values.firstWhere(
        (m) => m.name == project.calibrationMode,
        orElse: () => CalibrationMode.affine,
      ),
      manual: project.manualMode,
      pinnedIds: project.pinnedAnchorIds,
    );
    // Восстанавливаем данные ФотоСевера, если они есть
    if (project.photoSeverLinePixels > 0) {
      _calibrationService.updatePhotoSeverData(
        lineMeters: project.photoSeverLineMeters,
        linePixels: project.photoSeverLinePixels,
        northAngle: project.photoSeverNorthAngle,
      );
      _calibrationService.setCalibrationMode(CalibrationMode.photoSever);
    }
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

    final fitScale = math.min(vp.width / imgW, vp.height / imgH) * AppConstants.imageFitPaddingFactor;

    setState(() {
      state.transformState = MapTransformState(
        scale: fitScale,
        rotationRadians: 0,
        translation: Offset.zero,
      );
    });

    _recalculateCrosshairImagePoint();
  }

  // --------------------------------------------------------
  // Выбор фото
  // --------------------------------------------------------

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      final savedPath = await storageService.saveImageToAppStorage(image.path);

      try {
        final tempFile = File(image.path);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (e) {
        print('pickImage(): Failed to delete temp file: $e');
      }

      final projectId = DateTime.now().millisecondsSinceEpoch.toString();
      final project = MapProject(
        id: projectId,
        imagePath: savedPath,
        anchors: [],
        targets: [],
        userPath: [],
        pathJumpIndices: [],
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

      _calibrationService.updateAnchors([]);
      await _loadImageSize();
    } catch (e) {
      showSnackBar('Не удалось загрузить изображение');
    }
  }

  // --------------------------------------------------------
  // Закрытие карты
  // --------------------------------------------------------

  Future<void> closeMap() async {
    if (state.imagePath != null) {
      removeImageFromCache(state.imagePath!); // очищаем кэш изображения
      final file = File(state.imagePath!);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (state.project != null) {
      await storageService.deleteProject(state.project!.id);
    } else {
      await storageService.setCurrentProjectId(null);
    }

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
    _calibrationService.updateAnchors([]);
    _calibrationService.setPinnedAnchorIds([]);
    anchorManager.cachedGpxPoints = null;
  }

  Future<void> clearAllAnchors() async {
    final project = state.project;
    if (project == null) return;
    final updatedProject = project.copyWith(anchors: []);
    await storageService.saveProject(updatedProject);
    setState(() {
      state.project = updatedProject;
      state.workingPair = null;
      state.canPlaceTarget = false;
    });
    _calibrationService.updateAnchors([]);
    showSnackBar('Все якоря удалены');
  }

  Future<void> clearUserPath() async {
    final project = state.project;
    if (project == null) return;
    final updatedProject = project.copyWith(userPath: [], pathJumpIndices: []);
    await storageService.saveProject(updatedProject);
    setState(() {
      state.project = updatedProject;
    });
    showSnackBar('Путь пользователя удалён');
  }

  // --------------------------------------------------------
  // Трансформация карты
  // --------------------------------------------------------

  void updateTransform(MapTransformState newTransform) {
    setState(() {
      state.transformState = newTransform;
    });

    if (state.followMode &&
        !followController.isAutoRotating &&
        !followController.keepFollowDuringScale) {
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

  void zoomIn() {
    followController.keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale * 1.5).clamp(AppConstants.minMapScale, AppConstants.maxMapScale);
    _scaleAroundCrosshair(current, newScale);
    followController.keepFollowDuringScale = false;
  }

  void zoomOut() {
    followController.keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale / 1.5).clamp(AppConstants.minMapScale, AppConstants.maxMapScale);
    _scaleAroundCrosshair(current, newScale);
    followController.keepFollowDuringScale = false;
  }

  void _scaleAroundCrosshair(MapTransformState current, double newScale) {
    if (state.viewportSize == null || state.imageSize == null) return;
    final pivotScreen = getCrosshairScreenPoint();
    final pivotImage = screenToImage(pivotScreen);
    final tempTransform = MapTransformState(
      scale: newScale,
      rotationRadians: current.rotationRadians,
      translation: current.translation,
    );
    _applyTransformWithPivot(current, tempTransform, pivotImage);
  }

  void _applyTransformWithPivot(
    MapTransformState oldTransform,
    MapTransformState tempTransform,
    Offset pivotImage,
  ) {
    final pivotScreen = getCrosshairScreenPoint();
    final saved = state.transformState;
    state.transformState = tempTransform;
    final pivotScreenAfter = imageToScreen(pivotImage);
    state.transformState = saved;
    final delta = pivotScreen - pivotScreenAfter;
    updateTransform(
      tempTransform.copyWith(translation: tempTransform.translation + delta),
    );
  }

  // --------------------------------------------------------
  // Прицел
  // --------------------------------------------------------

  Offset getCrosshairScreenPoint() => state.crosshairScreenPoint;

  Future<void> copyCrosshairCoordinatesToClipboard() async {
    if (state.crosshairImagePoint == null) return;

    final geo = _calibrationService.imagePointToGeoFromCurrent(
      state.crosshairImagePoint!,
    );

    if (geo != null) {
      final lat = geo.latitude.toStringAsFixed(6);
      final lon = geo.longitude.toStringAsFixed(6);
      await Clipboard.setData(ClipboardData(text: '$lat, $lon'));

      state.crosshairFeedback.value = true;
      Future.delayed(const Duration(milliseconds: AppConstants.feedbackDurationMs), () {
        if (!state.isDisposed) {
          state.crosshairFeedback.value = false;
        }
      });
    }
  }

  void _recalculateCrosshairImagePoint() {
    if (state.imageSize == null || state.viewportSize == null) return;

    final screenPoint = state.crosshairScreenPoint;
    final imagePoint = screenToImage(screenPoint);

    setState(() {
      state.crosshairImagePoint = imagePoint;
    });
  }

  // --------------------------------------------------------
  // Преобразования screen ↔ image
  // --------------------------------------------------------

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

  // --------------------------------------------------------
  // Якоря
  // --------------------------------------------------------

  Future<void> addAnchorFromCurrentGps() async {
    await anchorManager.addAnchorFromCurrentGps();
  }

  Future<void> addAnchorFromClipboard() async {
    await anchorManager.addAnchorFromClipboard();
  }

  void showHereOptions(BuildContext context) {
    anchorManager.showHereOptions(context);
  }

  Future<void> pickGpxFile(BuildContext context) async {
    await anchorManager.pickGpxFile(context);
  }

  // --------------------------------------------------------
  // Ручной выбор и удаление якорей
  // --------------------------------------------------------

  void handleTapOnMap(Offset screenPosition) {
    anchorManager.handleTapOnMap(screenPosition);
  }

  void handleLongPressOnMap(BuildContext context, Offset screenPosition) {
    anchorManager.handleLongPressOnMap(context, screenPosition);
  }

  void deleteAnchorAndUpdate(String anchorId) async {
    anchorManager.deleteAnchorAndUpdate(anchorId);
  }

  // --------------------------------------------------------
  // Смена режима (меню)
  // --------------------------------------------------------

  void showModePicker(BuildContext context) {
    anchorManager.showModePicker(context);
  }

  // --------------------------------------------------------
  // Цели
  // --------------------------------------------------------

  void placePlannedTargetAtCrosshair() {
    targetManager.placePlannedTargetAtCrosshair();
  }

  void cancelPlannedTarget() {
    targetManager.cancelPlannedTarget();
  }

  Future<void> placeTargetFromClipboard() async {
    await targetManager.placeTargetFromClipboard();
  }

  Future<void> setTargetAndStartNavigation() async {
    await targetManager.setTargetAndStartNavigation();
  }

  void markActiveTargetAsPassed() async {
    await targetManager.markActiveTargetAsPassed();
  }

  // --------------------------------------------------------
  // Пересчёты
  // --------------------------------------------------------

  void _recalculateWorkingPairAndRotation() {
    final anchors = state.project?.anchors ?? [];
    final newPair = _calibrationService.selectWorkingPair(anchors);
    final declinationRad = magneticDeclination * math.pi / 180;

    setState(() {
      state.workingPair = newPair;
      if (newPair != null) {
        // Обычные режимы: истинный угол минус склонение
        final trueRotation = _calibrationService.getMapRotation(newPair) ?? 0.0;
        state.mapRotation = trueRotation - declinationRad;
      } else {
        // Режим P или отсутствие калибровки
        final project = state.project;
        if (project != null && project.photoSeverLinePixels > 0) {
          state.mapRotation = -math.pi / 2 - project.photoSeverNorthAngle;
        } else {
          state.mapRotation = 0.0;
        }
      }
    });
  }

 
  void _recalculateCanPlaceTarget() {
  setState(() {
    state.canPlaceTarget = true;
  });
}

  void _recalculateUserImagePoint() {
    // Если привязка отсутствует, скрываем маркер
    if (_calibrationService.usedAnchorCount == 0) {
      if (state.currentUserImagePoint != null) {
        setState(() {
          state.currentUserImagePoint = null;
        });
      }
      return;
    }

    final gps = _lastGpsData;
    if (gps == null) return;
    final lat = gps.latitude;
    final lon = gps.longitude;
    if (lat == null || lon == null || state.project == null) return;

    final imagePoint = _calibrationService.geoToImagePointFromCurrent(lat, lon);

    if (imagePoint == null || (imagePoint.dx == 0.0 && imagePoint.dy == 0.0)) {
      return;
    }

    final updatedPath = [...state.project!.userPath, imagePoint];

    setState(() {
      state.currentUserImagePoint = imagePoint;
      state.project = state.project!.copyWith(userPath: updatedPath);
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

    final bd = _calibrationService.bearingAndDistance(
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

  Future<void> recalculateTargetsAfterNewAnchor({
    bool restartNavigation = false,
  }) async {
    final project = state.project;
    if (project == null) return;

    final updatedTargets = project.targets.map((t) {
      final geo = _calibrationService.imagePointToGeoFromCurrent(
        Offset(t.imageX, t.imageY),
      );
      if (geo == null) return t;
      return t.copyWith(latitude: geo.latitude, longitude: geo.longitude);
    }).toList();

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    MapTarget? newActiveTarget;
    try {
      newActiveTarget = updatedTargets.firstWhere(
        (t) => t.status == MapTargetStatus.active,
      );
    } catch (e) {
      newActiveTarget = null;
    }

    setState(() {
      state.project = updatedProject;
      state.activeTarget = newActiveTarget;
    });

    if (restartNavigation &&
        onStartNavigation != null &&
        newActiveTarget?.latitude != null) {
      await onStartNavigation!(
        newActiveTarget!.latitude!,
        newActiveTarget.longitude!,
      );
      showSnackBar('Навигация перезапущена с новыми координатами цели');
    }
  }

  // --------------------------------------------------------
  // Follow mode
  // --------------------------------------------------------

  void enableFollowMode() {
    followController.enableFollowMode();
  }

  void disableFollowMode() {
    followController.disableFollowMode();
  }

  void toggleFollowMode() {
    followController.toggleFollowMode();
  }

  void enableRotateMode() {
    followController.enableRotateMode();
  }

  void disableRotateMode() {
    followController.disableRotateMode();
  }

  void resetRotateModeTimer() {
    followController.resetRotateModeTimer();
  }

  // --------------------------------------------------------
  // GPS подписка
  // --------------------------------------------------------

  void _startGpsCompassService() {
    GpsCompassService.instance.start(_sensorSettings);
  }

  void _startGpsSubscription() {
    _gpsSub = sensorService.subscribeToGps(
      intervalSeconds: _sensorSettings.gpsInterval,
      onData: (gpsData) {
        _lastGpsData = gpsData;
        anchorManager.lastGpsData = gpsData;

        if (state.followMode) {
          _recalculateUserImagePoint();
          followController.centerMapOnUser();
        } else {
          _recalculateUserImagePoint();
        }
      },
    );
  }

void _onHeadingChanged() {
  // headingNotifier.value уже содержит магнитный курс
  final magneticHeading = headingNotifier.value;
  setState(() {
    state.heading = magneticHeading;         // теперь это магнитный курс
    state.magneticHeading = magneticHeading; // без изменений
  });
  if (state.followMode) {
    followController.applyHeadingRotation();
  }
}

  // --------------------------------------------------------
  // Вспомогательные
  // --------------------------------------------------------

  void _onGpsActiveChanged() {
    setState(() {
      state.isGpsActive = GpsCompassService.instance.isActiveNotifier.value;
    });
  }

  static double computeResetRotation({
    required double mapRotation,
    required double photoSeverNorthAngle,
    required double photoSeverLinePixels,
    required double declinationRad,
  }) {
    if (photoSeverLinePixels > 0) {
      // Режим P: угол уже магнитный, так как photoSeverNorthAngle магнитный
      return -math.pi / 2 - photoSeverNorthAngle;
    } else if (mapRotation != 0.0) {
      // mapRotation уже магнитный, дополнительное склонение не вычитаем
      return mapRotation;
    } else {
      return 0.0;
    }
  }
}
