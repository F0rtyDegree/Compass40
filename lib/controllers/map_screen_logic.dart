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
import 'map_track_manager.dart';
import 'photo_sever_controller.dart';
import '../utils/app_constants.dart';
import '../utils/compensation_utils.dart';
import '../utils/geo_utils.dart';
import '../widgets/map_image_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

class MapScreenLogic {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final ValueNotifier<GpsData> gpsDataNotifier;
  final ValueNotifier<double> magneticDeclinationNotifier;
  final ValueNotifier<double> headingNotifier;

  double get magneticDeclination => magneticDeclinationNotifier.value;
  final MapCalibrationService _calibrationService = MapCalibrationService();
  final SensorService sensorService = SensorService();
  final LogService logService = LogService();
  final Function(double lat, double lon, double? distance, DateTime createdAt)?
  onAnchorAdded;
  final StartNavigationCallback? onStartNavigation;
  final VoidCallback? onCancelNavigation;
  final VoidCallback? onAnchorsChangedForStatus;
  late final PhotoSeverController photoSeverController;

  GpsData? _lastGpsData;
  late final MapAnchorManager anchorManager;
  final Future<double?> Function() askDistanceDialog;
  late final MapTargetManager targetManager;
  late final MapFollowController followController;
  late final MapTrackManager trackManager;

  MapScreenLogic({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.gpsDataNotifier,
    required this.magneticDeclinationNotifier,
    required this.headingNotifier,
    this.onAnchorAdded,
    this.onStartNavigation,
    this.onCancelNavigation,
    this.onAnchorsChangedForStatus,
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

  // Динамическая компенсация (мс)
  double _compensationMs = 1500.0;
  static const String _compensationPrefKey =
      AppConstants.prefAnchorCompensationMs;

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
    targetManager = MapTargetManager(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      storageService: storageService,
      calibrationService: _calibrationService,
      onStartNavigation: onStartNavigation,
      onCancelNavigation: onCancelNavigation,
      onRecalculatePreview: _recalculatePreview,
    );
    trackManager = MapTrackManager(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
      storageService: storageService,
      calibrationService: _calibrationService,
      gpsDataNotifier: gpsDataNotifier,
    );
    followController = MapFollowController(
      state: state,
      setState: setState,
      showSnackBar: showSnackBar,
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
      onEnableFollowMode: followController.enableFollowMode,
      onFinish: () {
        _calibrationService.setCalibrationMode(CalibrationMode.photoSever);
        _calibrationService.updatePhotoSeverData(
          lineMeters: state.project!.photoSeverLineMeters,
          linePixels: state.project!.photoSeverLinePixels,
          northAngle: state.project!.photoSeverNorthAngle,
        );
        setState(() {});
      },
    );
    _calibrationService.onManualSetApplied = () {
      _recalculateWorkingPairAndRotation();
      recalculateTargetsAfterNewAnchor();
    };
    await followController.loadRotateModeTimeout();
    await trackManager.loadLoadedTrackColor();
    _calibrationService.setMagneticDeclination(magneticDeclination);
    magneticDeclinationNotifier.addListener(_onMagneticDeclinationChanged);
    await _loadLastProject();
    await trackManager.loadActiveTrackFromCsv();
    anchorManager.cachedGpxPoints = state.project?.cachedGpxPoints;
    gpsDataNotifier.addListener(_onGpsDataChanged);
    _lastGpsData = gpsDataNotifier.value;
    headingNotifier.addListener(_onHeadingChanged);
    _onHeadingChanged();
    GpsCompassService.instance.isActiveNotifier.addListener(
      _onGpsActiveChanged,
    );
    _onGpsActiveChanged();
  }

  void dispose() {
    headingNotifier.removeListener(_onHeadingChanged);
    magneticDeclinationNotifier.removeListener(_onMagneticDeclinationChanged);
    GpsCompassService.instance.isActiveNotifier.removeListener(
      _onGpsActiveChanged,
    );
    gpsDataNotifier.removeListener(_onGpsDataChanged);
    if (state.project != null) {
      // saveProject асинхронный, но dispose синхронный — await здесь невозможен.
      // Осознанно оставлено без await. Все критичные изменения проекта уже
      // сохранены раньше (addAnchor, closeMap, pickImage и т.д.). Здесь —
      // вторичная страховка. Риск потери минимален. Возвращаться к вопросу
      // только при реальных проблемах.
      storageService.saveProject(state.project!);
    }
    state.rotateModeTimer?.cancel();
    // Флаг выставляем до dispose, чтобы таймеры и отложенные
    // вызовы видели корректное состояние.
    state.isDisposed = true;
    state.crosshairFeedback.dispose();
  }

  // --------------------------------------------------------
  // Загрузка проекта
  // --------------------------------------------------------

  Future<void> _loadLastProject() async {
    final projectId = await storageService.getCurrentProjectId();
    await _loadCompensation();
    if (projectId == null) return;

    final project = await storageService.loadProject(projectId);
    if (project == null) return;

    final savedTransform = await storageService.loadTransform(projectId);

    // Активная цель при старте переводится в planned: сессия прервана,
    // ведение не восстанавливается. Пользователь активирует цель
    // повторно кнопкой ГОУ.
    final hasActive = project.targets.any(
      (t) => t.status == MapTargetStatus.active,
    );
    MapProject projectToUse = project;
    if (hasActive) {
      final updatedTargets = project.targets.map((t) {
        if (t.status == MapTargetStatus.active) {
          return t.copyWith(status: MapTargetStatus.planned);
        }
        return t;
      }).toList();
      projectToUse = project.copyWith(targets: updatedTargets);
      await storageService.saveProject(projectToUse);
    }

    setState(() {
      state.project = projectToUse;
      state.imagePath = projectToUse.imagePath;
      if (savedTransform != null) {
        state.transformState = savedTransform;
      }
      state.activeTarget = null;
      // Если была active — она уже стала planned. Показываем как planned.
      state.plannedTarget = projectToUse.targets.firstWhereOrNull(
        (t) => t.status == MapTargetStatus.planned,
      );
    });

    _calibrationService.updateAnchors(projectToUse.anchors);
    _calibrationService.setPinnedAnchorIds(projectToUse.pinnedAnchorIds);

    final savedMode = CalibrationMode.values.firstWhere(
      (m) => m.name == projectToUse.calibrationMode,
      orElse: () => CalibrationMode.affine,
    );

    _calibrationService.restoreState(
      mode: savedMode,
      manual: projectToUse.manualMode,
      pinnedIds: projectToUse.pinnedAnchorIds,
    );

    if (projectToUse.photoSeverLinePixels > 0) {
      _calibrationService.updatePhotoSeverData(
        lineMeters: projectToUse.photoSeverLineMeters,
        linePixels: projectToUse.photoSeverLinePixels,
        northAngle: projectToUse.photoSeverNorthAngle,
      );
    }

    await _loadImageSize();
    _recalculateWorkingPairAndRotation(enableFollow: true);
    _recalculateCanPlaceTarget();
    await trackManager.loadLoadedTrackFromProject();
  }

  /// Открывает файловый пикер, выбирает GPX, загружает трек.
  /// Предыдущий загруженный трек заменяется.
  Future<void> pickLoadedTrack() async {
    await trackManager.pickLoadedTrack();
  }

  Future<void> clearLoadedTrack() async {
    await trackManager.clearLoadedTrack();
  }

  /// Пересчитывает пиксели загруженного трека под текущую привязку.

  /// Читает CSV-файл трека и заполняет trackImagePoints.
  /// Вызывается при открытии карты и при каждом изменении якорей
  /// (через _reloadTrackImagePoints), чтобы пересчитать пиксели под
  /// новую привязку.
  ///
  /// На большом треке (20k+ точек) цикл с geoToImagePointFromCurrent
  /// занимает сотни миллисекунд. Не оптимизировано осознанно: добавление
  /// якорей — редкая операция, задержка незаметна на фоне перерисовки.
  /// Возвращаться — только при реальных жалобах.

  /// Убирает трек с карты. Вызывается при остановке записи.
  void onRecordingStopped() {
    trackManager.onRecordingStopped();
  }

  /// Загружает трек на карту. Вызывается при старте записи.
  Future<void> onRecordingStarted() async {
    await trackManager.onRecordingStarted();
  }

  /// Добавляет точку трека из GPS-потока, если идёт запись.
  /// Обновляется при каждом GPS-пакете.
  ///
  /// setState на каждый пакет и копирование списка — O(n). При 1 Гц
  /// и 3600 точках это ~7000 операций в секунду, что незаметно.
  /// Оптимизация (буфер + пакетная запись) не делается осознанно:
  /// выигрыш неощутим, риск выше пользы. Возвращаться — если появятся
  /// просадки при малом интервале GPS.

  Future<void> _loadImageSize() async {
    if (state.imagePath == null) return;
    final file = File(state.imagePath!);
    if (!await file.exists()) return;

    final bytes = await file.readAsBytes();
    final decoded = await decodeImageFromList(bytes);

    final imgW = decoded.width.toDouble();
    final imgH = decoded.height.toDouble();

    // Освобождаем нативный ресурс — размеры уже извлечены.
    decoded.dispose();

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

    final fitScale =
        math.min(vp.width / imgW, vp.height / imgH) *
        AppConstants.imageFitPaddingFactor;

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
    // Снимаем режим ожидания координат, если был активен.
    state.pendingAnchorCoordId = null;

    // Синхронизируем с главным экраном: убираем строку цели, но только
    // если активная цель была на карте. Иначе цель, заданная через
    // TargetScreen, пропала бы при удалении карты.
    final hadActiveTargetOnMap = state.activeTarget != null;

    final imagePathToDelete = state.imagePath;
    final projectId = state.project?.id;

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
      state.pendingAnchor = null;
      state.trackImagePoints = [];
      state.loadedTrackGpsPoints = [];
      state.loadedTrackImagePoints = [];
    });

    if (imagePathToDelete != null) {
      removeImageFromCache(imagePathToDelete);
      final file = File(imagePathToDelete);
      if (await file.exists()) {
        await file.delete();
      }
    }

    if (projectId != null) {
      await storageService.deleteProject(projectId);
    } else {
      await storageService.setCurrentProjectId(null);
    }
    _calibrationService.updateAnchors([]);
    _calibrationService.setPinnedAnchorIds([]);
    anchorManager.cachedGpxPoints = null;

    // Очищаем внутренний журнал при удалении карты.
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefLogItems);

    if (hadActiveTargetOnMap) {
      onCancelNavigation?.call();
    }
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
    _calibrationService.setPinnedAnchorIds([]);
    await recalculateTargetsAfterNewAnchor();

    // Без привязки цель бесполезна, пусть уходит в историю.
    final active = state.activeTarget;
    if (active != null) {
      final currentProject = state.project;
      if (currentProject != null) {
        final updatedTargets = currentProject.targets.map((t) {
          if (t.id == active.id) {
            return t.copyWith(status: MapTargetStatus.passed);
          }
          return t;
        }).toList();
        final updated = currentProject.copyWith(targets: updatedTargets);
        await storageService.saveProject(updated);
        setState(() {
          state.project = updated;
          state.activeTarget = null;
        });
      }
    }
    //    showSnackBar('Все якоря удалены');
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

    if (state.project != null && !state.followMode) {
      storageService.saveTransform(state.project!.id, newTransform);
    }
  }

  void updateViewportSize(Size size) {
    if (state.viewportSize == size) return;
    setState(() {
      state.viewportSize = size;
    });
    _recalculateCrosshairImagePoint();
  }

  void zoomIn() {
    followController.keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale * 1.5).clamp(
      AppConstants.minMapScale,
      AppConstants.maxMapScale,
    );
    _scaleAroundCrosshair(current, newScale);
    followController.keepFollowDuringScale = false;
  }

  void zoomOut() {
    followController.keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale / 1.5).clamp(
      AppConstants.minMapScale,
      AppConstants.maxMapScale,
    );
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
      Future.delayed(
        const Duration(milliseconds: AppConstants.feedbackDurationMs),
        () {
          if (!state.isDisposed) {
            state.crosshairFeedback.value = false;
          }
        },
      );
    }
  }

  void _recalculateCrosshairImagePoint() {
    setState(() {
      state.recalculateCrosshairImagePoint(screenToImage);
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
  // Точка привязки (Якорь)
  // --------------------------------------------------------

  Future<void> addAnchorFromCurrentGps() async {
    final crosshair = state.crosshairImagePoint;
    if (crosshair == null) {
      showSnackBar('Прицел не определён');
      return;
    }
    await _addAnchorAtScreenPointInternal(
      getCrosshairScreenPoint(),
      isAutoCorrection: false,
    );
  }

  /// Вызывается из интента ACTION_FREEZE_ANCHOR.
  /// В пиксель, где сейчас находится маркер (курсор) ставим новый временный якорь,
  /// но сразу же делаем его постоянным. Старый временный якорь удаляем. Пересчитываем треки.
  Future<void> protectAutoAnchor() async {
    final gps = gpsDataNotifier.value;
    final userImagePoint = state.currentUserImagePoint;
    
    if (gps.latitude == null || gps.longitude == null || userImagePoint == null) {
      showSnackBar('Нет данных для фиксации');
      return;
    }

    final oldId = state.lastAutoAnchorId;
    
    // Удаляем старый авто-якорь и ставим новый в позиции курсора.
    await anchorManager.replaceAutoAnchor(oldId, gps, userImagePoint);
    
    // Пересчитываем пиксели треков.
    await trackManager.reloadActiveTrackImagePoints();
    trackManager.recalculateLoadedTrackImagePoints();

    setState(() {
      state.lastAutoAnchorId = null;
    });
    showSnackBar('Якорь зафиксирован');
  }

  /// Публичный метод: ставит якорь в позиции [screenPoint] с текущим GPS.
  /// [isAutoCorrection] = true — якорь создан через интент в follow mode.
  /// Перед постановкой удаляется предыдущий авто-якорь (если был).
  Future<void> addAnchorAtScreenPoint(
    Offset screenPoint, {
    bool isAutoCorrection = false,
  }) async {
    await _addAnchorAtScreenPointInternal(
      screenPoint,
      isAutoCorrection: isAutoCorrection,
    );
  }

  Future<void> _addAnchorAtScreenPointInternal(
    Offset screenPoint, {
    required bool isAutoCorrection,
  }) async {
    // Если это ACTION_PAN в follow mode — работаем мгновенно.
    // Никакого ожидания GPS и интерполяции. Берем текущий пакет.
    if (isAutoCorrection) {
      final crosshair = screenToImage(screenPoint);
      final gps = gpsDataNotifier.value;
      if (gps.latitude == null || gps.longitude == null) return;

      final oldId = state.lastAutoAnchorId;

      // Атомарная замена: один пересчет, без записи в журнал и пересчета целей.
      await anchorManager.replaceAutoAnchor(oldId, gps, crosshair);

      // Пересчитываем пиксели треков под новую привязку, чтобы линии не отставали.
      await trackManager.reloadActiveTrackImagePoints();
      trackManager.recalculateLoadedTrackImagePoints();

      final anchors = state.project?.anchors;
      final latest = (anchors != null && anchors.isNotEmpty) ? anchors.last : null;
      setState(() {
        state.lastAutoAnchorId = latest?.id;
      });
      return;
    }

    // Фиксируем СИСТЕМНОЕ время нажатия (БЕЗ компенсации)
    final DateTime rawRequestTime = DateTime.now();

    /// ============================================================
    /// КОМПЕНСАЦИЯ ЗАДЕРЖКИ GPS (важно!)
    /// ============================================================
    /// При нажатии кнопки «Я здесь» мы фиксируем системное время (rawRequestTime).
    /// Однако GPS-координаты, которые мы получим в ближайшие секунды, соответствуют
    /// не этому моменту, а моменту на 1–2 секунды позже. Это связано с тем, что:
    ///
    /// 1. GPS-чип и драйвер буферизируют и фильтруют данные, создавая задержку.
    /// 2. Обновления приходят дискретно (раз в секунду), и момент нажатия
    ///    почти никогда не совпадает с моментом получения пакета.
    ///
    /// Без компенсации точка привязки ложится ДО реального положения (например,
    /// до поворота), потому что интерполяция использует пакеты, которые были
    /// получены до и после нажатия, но эти пакеты соответствуют более раннему
    /// времени (из-за задержки обработки).
    ///
    /// Решение: мы сдвигаем время интерполяции на величину _compensationMs
    /// (по умолчанию 1500 мс, но динамически уточняется на основе измерений).
    /// Это позволяет «заглянуть» в будущее и получить координаты, которые
    /// соответствуют реальному положению в момент нажатия.
    ///
    /// Величина 1500 мс была подобрана эмпирически и подтверждена множеством
    /// тестов: в движении с компенсацией точки попадают точно в середину поворота,
    /// без компенсации — до поворота.
    ///
    /// Динамическая компенсация (см. _updateCompensation) автоматически
    /// подстраивается под текущие условия, используя измеренную задержку
    /// между нажатием и получением следующего GPS-пакета.
    /// ============================================================
    // Если уже идёт ожидание GPS — игнорируем повторное нажатие.
    if (state.pendingAnchor != null) return;

    final DateTime anchorRequestTime = rawRequestTime.add(
      Duration(milliseconds: _compensationMs.round()),
    );

    final crosshair = screenToImage(screenPoint);

    // Показываем серый якорь сразу, по текущему (грубому) GPS.
    final roughGps = gpsDataNotifier.value;
    if (roughGps.latitude == null || roughGps.longitude == null) {
      showSnackBar('Нет сигнала GPS');
      return;
    }
    setState(() {
      state.pendingAnchor = MapAnchor(
        id: 'pending',
        imageX: crosshair.dx,
        imageY: crosshair.dy,
        latitude: roughGps.latitude!,
        longitude: roughGps.longitude!,
        createdAt: rawRequestTime,
      );
    });

    GpsData gps1 = roughGps;

    // Берем текущий интервал GPS из настроек и даем 2 секунды запаса
    // на то, чтобы пакет дошел и обработался.
    final settings = await sensorService.loadSettings();
    final maxWaitMs = settings.gpsInterval * 3000;
    const Duration step = Duration(milliseconds: 50);
    final int maxIterations = maxWaitMs ~/ 50;

    GpsData? finalGps;
    GpsData? gps2; // сохраним второй пакет для расчёта дельты

    for (int i = 0; i < maxIterations; i++) {
      await Future.delayed(step);

      // Экран закрыт — прекращаем ожидание, сбрасываем pending.
      if (state.isDisposed) {
        setState(() {
          state.pendingAnchor = null;
        });
        return;
      }

      final GpsData gps2temp = gpsDataNotifier.value;

      final int? time1 = gps1.time;
      final int? time2 = gps2temp.time;

      if (time1 == null || time2 == null) {
        gps1 = gps2temp;
        continue;
      }

      final int anchorRequestTimeMs = anchorRequestTime.millisecondsSinceEpoch;

      if (time1 < anchorRequestTimeMs && anchorRequestTimeMs < time2) {
        final double t = (anchorRequestTimeMs - time1) / (time2 - time1);
        final double lat =
            gps1.latitude! + (gps2temp.latitude! - gps1.latitude!) * t;
        final double lon =
            gps1.longitude! + (gps2temp.longitude! - gps1.longitude!) * t;

        finalGps = GpsData(
          latitude: lat,
          longitude: lon,
          accuracy:
              (gps1.accuracy ?? 0) +
              ((gps2temp.accuracy ?? 0) - (gps1.accuracy ?? 0)) * t,
          speed:
              (gps1.speed ?? 0) +
              ((gps2temp.speed ?? 0) - (gps1.speed ?? 0)) * t,
          altitude:
              (gps1.altitude ?? 0) +
              ((gps2temp.altitude ?? 0) - (gps1.altitude ?? 0)) * t,
          mslAltitude:
              (gps1.mslAltitude ?? 0) +
              ((gps2temp.mslAltitude ?? 0) - (gps1.mslAltitude ?? 0)) * t,
          satellitesUsed: gps2temp.satellitesUsed ?? gps1.satellitesUsed,
          satellitesInView: gps2temp.satellitesInView ?? gps1.satellitesInView,
          magneticDeclination:
              gps2temp.magneticDeclination ?? gps1.magneticDeclination,
          gpsBearing: gps2temp.gpsBearing ?? gps1.gpsBearing,
          time: anchorRequestTimeMs,
        );
        gps2 = gps2temp; // запоминаем второй пакет
        break;
      } else if (time1 == anchorRequestTimeMs) {
        finalGps = gps1;
        gps2 =
            gps2temp; // в этом случае второй пакет может быть тем же или следующим
        break;
      } else if (time2 == anchorRequestTimeMs) {
        finalGps = gps2temp;
        gps2 = gps2temp;
        break;
      }

      gps1 = gps2temp;
    }

    if (finalGps == null) {
      setState(() {
        state.pendingAnchor = null;
      });
      showSnackBar(
        'Не удалось определить точное положение. Попробуйте еще раз.',
      );
      return;
    }

    // Вычисляем дельту для обновления компенсации
    if (gps2 != null && gps2.time != null) {
      final double delta = (gps2.time! - rawRequestTime.millisecondsSinceEpoch)
          .toDouble();
      _updateCompensation(delta);
    }
    setState(() {
      state.pendingAnchor = null;
    });

    await anchorManager.addAnchorFromGps(
      finalGps,
      crosshair,
      anchorRequestTime,
    );
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

  Future<void> deleteAnchorAndUpdate(String anchorId) async {
    await anchorManager.deleteAnchorAndUpdate(anchorId);
  }

  Future<void> applyAnchorCoordFromCrosshair() async {
    await anchorManager.applyAnchorCoordFromCrosshair();
  }

  void cancelAnchorCoordPick() {
    anchorManager.cancelAnchorCoordPick();
  }

  // --------------------------------------------------------
  // Смена режима (меню)
  // --------------------------------------------------------

  Future<void> showModePicker(BuildContext context) async {
    await anchorManager.showModePicker(context);
    _recalculateWorkingPairAndRotation();
    await recalculateTargetsAfterNewAnchor();
  }

  Future<void> nextCalibrationMode() async {
    const order = [
      CalibrationMode.affine,
      CalibrationMode.pairFarthest,
      CalibrationMode.pairNearest,
      CalibrationMode.photoSever,
    ];
    final current = _calibrationService.currentMode;
    int index = order.indexOf(current);
    if (index == -1) index = 0;

    for (int i = 1; i <= order.length; i++) {
      final nextIndex = (index + i) % order.length;
      final candidate = order[nextIndex];
      if (candidate == CalibrationMode.photoSever) {
        final project = state.project;
        if (project == null || project.photoSeverLinePixels == 0) {
          continue;
        }
      }
      _calibrationService.setCalibrationMode(candidate);

      // Сохраняем режим в проект, иначе после перезапуска
      // приложение восстановит прежний режим из SharedPreferences.
      final project = state.project;
      if (project != null) {
        final updated = project.copyWith(
          manualMode: _calibrationService.isManualMode,
          calibrationMode: _calibrationService.currentMode.name,
          pinnedAnchorIds: _calibrationService.pinnedAnchorIdsList,
        );
        storageService.saveProject(updated);
        setState(() {
          state.project = updated;
        });
      }

      _recalculateWorkingPairAndRotation();
      await recalculateTargetsAfterNewAnchor();
      return;
    }
  }
  // --------------------------------------------------------
  // Цели
  // --------------------------------------------------------

  void placePlannedTargetAtCrosshair() {
    unawaited(targetManager.placePlannedTargetAtCrosshair());
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

  Future<void> markActiveTargetAsPassed() async {
    await targetManager.markActiveTargetAsPassed();
  }

  /// Публичный метод для внешней отмены активной цели.
  /// Используется, когда строку цели смахивают на главном экране.
  Future<void> cancelActiveTarget() async {
    await targetManager.markActiveTargetAsPassed();
  }

  // --------------------------------------------------------
  // Пересчёты
  // --------------------------------------------------------

  void _recalculateWorkingPairAndRotation({bool enableFollow = false}) {
    final anchors = state.project?.anchors ?? [];
    _calibrationService.updateAnchors(anchors);
    final newPair = _calibrationService.selectWorkingPair(anchors);
    final declinationRad = magneticDeclination * math.pi / 180;

    setState(() {
      state.workingPair = newPair;
      if (newPair != null) {
        final trueRotation = _calibrationService.getMapRotation(newPair) ?? 0.0;
        state.mapRotation = trueRotation - declinationRad;
      } else {
        final project = state.project;
        if (project != null && project.photoSeverLinePixels > 0) {
          state.mapRotation = -math.pi / 2 - project.photoSeverNorthAngle;
        } else {
          state.mapRotation = 0.0;
        }
      }
    });

    // Follow включаем только по явному запросу. Иначе при каждом обновлении
    // склонения (раз в секунду) пользователю принудительно включался бы
    // режим сопровождения, даже если он его выключил.
    if (enableFollow && newPair != null) {
      enableFollowMode();
    }

    onAnchorsChangedForStatus?.call();
    _recalculateCanPlaceTarget();
    _recalculateUserImagePoint();
  }

  // Всегда ставит true. Проверка привязки отсутствует осознанно.
  // Сценарий: карта без привязки. Кнопка "ЦЕЛЬ" активна. Пользователь
  // ставит жёлтый флаг. Координаты не вычисляются (latitude = null).
  // Нажатие ГОУ молча ничего не делает. Флаг можно убрать кнопкой "назад".
  // Сообщения не показываем осознанно: обилие раздражает, причина видна
  // по отсутствию координат. Возвращаться — только при реальных жалобах.
  void _recalculateCanPlaceTarget() {
    setState(() {
      state.canPlaceTarget = true;
    });
  }

  void _recalculateUserImagePoint() {
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
    if (imagePoint == null) return;

    setState(() {
      state.currentUserImagePoint = imagePoint;
    });

    _recalculatePreview();
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

    final nav = calculateNavigationData(
      fromLat: gps!.latitude!,
      fromLon: gps.longitude!,
      toLat: active!.latitude!,
      toLon: active.longitude!,
      magneticDeclination: magneticDeclination,
    );

    setState(() {
      state.previewDistanceMeters = nav.distanceMeters;
      state.previewBearingDegrees = nav.magneticBearing;
    });
  }

  Future<void> recalculateTargetsAfterNewAnchor({
    bool restartNavigation = false,
  }) async {
    final project = state.project;
    if (project == null) return;

    // Пересчитываем только активную цель. Пройденные — история,
    // их координаты фиксированы на момент прохождения.
    final updatedTargets = project.targets.map((t) {
      if (t.status != MapTargetStatus.active) return t;
      final geo = _calibrationService.imagePointToGeoFromCurrent(
        Offset(t.imageX, t.imageY),
      );
      if (geo == null) return t;
      return t.copyWith(latitude: geo.latitude, longitude: geo.longitude);
    }).toList();

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    final newActiveTarget = updatedTargets.firstWhereOrNull(
      (t) => t.status == MapTargetStatus.active,
    );

    setState(() {
      state.project = updatedProject;
      state.activeTarget = newActiveTarget;
    });

    // Пересчитываем пиксели трека под новую привязку.
    await trackManager.reloadActiveTrackImagePoints();
    trackManager.recalculateLoadedTrackImagePoints();

    if (restartNavigation &&
        onStartNavigation != null &&
        newActiveTarget?.latitude != null) {
      await onStartNavigation!(
        newActiveTarget!.latitude!,
        newActiveTarget.longitude!,
      );
      //      showSnackBar('Навигация перезапущена с новыми координатами цели');
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

  /// В обычном режиме — сдвигает карту на [delta] пикселей экрана.
  /// В follow mode — ставит якорь в позиции прицела, смещённой на [delta],
  /// с текущими GPS-координатами. Карта не двигается.
  void panBy(Offset delta) {
    final userImagePoint = state.currentUserImagePoint;
    if (userImagePoint == null) return; // Нет текущей позиции, корректировать нечего

    final userScreenPoint = imageToScreen(userImagePoint);

    // Сдвиг применяется со знаком минус, чтобы визуально курсор
    // двигался в сторону нажатой кнопки.
    addAnchorAtScreenPoint(userScreenPoint - delta, isAutoCorrection: true);
  }

  void _onMagneticDeclinationChanged() {
    _calibrationService.setMagneticDeclination(magneticDeclination);
    _recalculateWorkingPairAndRotation();
    _recalculatePreview();
  }

  void _onHeadingChanged() {
    final magneticHeading = headingNotifier.value;
    setState(() {
      state.magneticHeading = magneticHeading;
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

  /// Обработка GPS-пакета. Три setState за один кадр (позиция, трек,
  /// центрирование карты). Flutter объединяет их в одну перерисовку,
  /// поэтому оптимизация не делается: реального выигрыша нет,
  /// а переработка методов в «возвращающие значение» усложнит код.
  void _onGpsDataChanged() {
    final gpsData = gpsDataNotifier.value;
    if (gpsData.latitude == null || gpsData.longitude == null) return;
    _lastGpsData = gpsData;
    _recalculateUserImagePoint();
    trackManager.appendActiveTrackPointIfRecording(gpsData);
    if (state.followMode) {
      followController.centerMapOnUser();
    }
  }

  static double computeResetRotation({
    required double mapRotation,
    required double photoSeverNorthAngle,
    required double photoSeverLinePixels,
  }) {
    if (photoSeverLinePixels > 0) {
      return -math.pi / 2 - photoSeverNorthAngle;
    } else if (mapRotation != 0.0) {
      return mapRotation;
    } else {
      return 0.0;
    }
  }

  Future<void> _loadCompensation() async {
    final prefs = await SharedPreferences.getInstance();
    _compensationMs = prefs.getDouble(_compensationPrefKey) ?? 1500.0;
  }

  Future<void> _saveCompensation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_compensationPrefKey, _compensationMs);
  }

  void _updateCompensation(double delta) {
    _compensationMs = updateCompensationEma(_compensationMs, delta);
    _saveCompensation();
  }
}
