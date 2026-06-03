import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:xml/xml.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gps_info/gps_info.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

class MapScreenLogic {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final double magneticDeclination;
  final MapCalibrationService _calibrationService = MapCalibrationService();
  final SensorService sensorService = SensorService();
  final LogService logService = LogService();
  final Function(double lat, double lon, double? distance, String timeStr)?
  onAnchorAdded;
  final StartNavigationCallback? onStartNavigation;
  final VoidCallback? onCancelNavigation;
  bool _isAutoRotating = false;
  bool _keepFollowDuringScale = false;
  int rotateModeTimeoutMs = 1000;

  StreamSubscription<GpsData>? _gpsSub;
  GpsData? _lastGpsData;
  late SensorSettings _sensorSettings;
  List<Map<String, String>>? _cachedGpxPoints;

  MapScreenLogic({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.magneticDeclination,
    this.onAnchorAdded,
    this.onStartNavigation,
    this.onCancelNavigation,
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
    _sensorSettings = await sensorService.loadSettings();
    await _loadRotateModeTimeout();
    await _loadLastProject();
    _startGpsCompassService();
    _startGpsSubscription();
  }

  void dispose() {
    GpsCompassService.instance.bearingNotifier.removeListener(
      _onGpsBearingChanged,
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

    final fitScale = math.min(vp.width / imgW, vp.height / imgH) * 0.92;

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
        debugPrint('Failed to delete temp file: $e');
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
      debugPrint('MapScreenLogic.pickImage error: $e');
    }
  }

  // --------------------------------------------------------
  // Закрытие карты
  // --------------------------------------------------------

  Future<void> closeMap() async {
    if (state.imagePath != null) {
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
    _cachedGpxPoints = null;
  }

  // --------------------------------------------------------
  // Трансформация карты
  // --------------------------------------------------------

  void updateTransform(MapTransformState newTransform) {
    setState(() {
      state.transformState = newTransform;
    });

    if (state.followMode && !_isAutoRotating && !_keepFollowDuringScale) {
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
    _keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale * 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(current, newScale);
    _keepFollowDuringScale = false;
  }

  void zoomOut() {
    _keepFollowDuringScale = true;
    final current = state.transformState;
    final newScale = (current.scale / 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(current, newScale);
    _keepFollowDuringScale = false;
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

  Offset getCrosshairScreenPoint() => _getCrosshairScreenPoint();

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
    final gpsData = _lastGpsData;
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
    final hasCache = _cachedGpxPoints != null;
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
            ..._cachedGpxPoints!.map((p) {
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
      _showGpxPointsList(context, points);
      _cachedGpxPoints = points;
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
      distanceFromPrevious = _calibrationService.distanceBetweenAnchorsMeters(
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
    final updatedProject = project.copyWith(
      anchors: updatedAnchors,
      pathJumpIndices: newPathJumpIndices,
      manualMode: _calibrationService.isManualMode,
      calibrationMode: _calibrationService.currentMode.name,
      pinnedAnchorIds: _calibrationService.pinnedAnchorIdsList,
    );

    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
    });

    _calibrationService.updateAnchors(updatedAnchors);
    _recalculateWorkingPairAndRotation();
    _recalculateCanPlaceTarget();
    _recalculateUserImagePoint();
    await recalculateTargetsAfterNewAnchor(restartNavigation: true);

    if (onAnchorAdded != null) {
      final now = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      final anchorIndices = _calibrationService.activeAnchorIndices;
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

  // --------------------------------------------------------
  // Ручной выбор и удаление якорей
  // --------------------------------------------------------

  void handleTapOnMap(Offset screenPosition) {
    final anchor = _findClosestAnchor(screenPosition);
    if (anchor != null) {
      _calibrationService.toggleAnchorPinned(anchor.id);
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
      manualMode: _calibrationService.isManualMode,
      calibrationMode: _calibrationService.currentMode.name,
      pinnedAnchorIds: _calibrationService.pinnedAnchorIdsList,
    );
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
    });

    _calibrationService.removeAnchor(anchorId);
    _recalculateWorkingPairAndRotation();
    _recalculateCanPlaceTarget();
    _recalculateUserImagePoint();
  }

  // --------------------------------------------------------
  // Смена режима (меню)
  // --------------------------------------------------------

  void showModePicker(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Режим привязки'),
        children: [
          SimpleDialogOption(
            onPressed: () {
              _calibrationService.enableManualMode();
              Navigator.pop(ctx);
              _recalculateUserImagePoint();
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Ручной (M)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              _calibrationService.setCalibrationMode(CalibrationMode.affine);
              Navigator.pop(ctx);
              _recalculateUserImagePoint();
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Affine (A)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              _calibrationService.setCalibrationMode(
                CalibrationMode.pairFarthest,
              );
              Navigator.pop(ctx);
              _recalculateUserImagePoint();
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Farthest (F)'),
          ),
          SimpleDialogOption(
            onPressed: () {
              _calibrationService.setCalibrationMode(
                CalibrationMode.pairNearest,
              );
              Navigator.pop(ctx);
              _recalculateUserImagePoint();
              _saveCalibrationState();
              setState(() {});
            },
            child: const Text('Nearest (N)'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------
  // Цели
  // --------------------------------------------------------

  void placePlannedTargetAtCrosshair() {
    if (!state.canPlaceTarget) return;
    if (state.crosshairImagePoint == null) return;

    final geo = _calibrationService.imagePointToGeoFromCurrent(
      state.crosshairImagePoint!,
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

  Future<void> setTargetAndStartNavigation() async {
    final planned = state.plannedTarget;
    if (planned == null ||
        planned.latitude == null ||
        planned.longitude == null) {
      return;
    }
    await _persistAndSetActiveTarget(copyCoords: false);

    if (onStartNavigation != null) {
      await onStartNavigation!(planned.latitude!, planned.longitude!);
      showSnackBar('Ведение на цель в компасе запущено');
    }
  }

  Future<void> _persistAndSetActiveTarget({required bool copyCoords}) async {
    final planned = state.plannedTarget;
    if (planned == null) return;

    final project = state.project;
    if (project == null) return;

    if (planned.latitude == null || planned.longitude == null) {
      showSnackBar('Координаты цели не определены — добавьте привязку');
      return;
    }

    if (copyCoords) {
      final lat = planned.latitude!.toStringAsFixed(6);
      final lon = planned.longitude!.toStringAsFixed(6);
      await Clipboard.setData(ClipboardData(text: '$lat, $lon'));
      showSnackBar('Координаты цели скопированы в буфер обмена');
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

  // --------------------------------------------------------
  // Пересчёты
  // --------------------------------------------------------

  void _recalculateWorkingPairAndRotation() {
    final anchors = state.project?.anchors ?? [];
    final newPair = _calibrationService.selectWorkingPair(anchors);

    setState(() {
      state.workingPair = newPair;
      if (newPair != null) {
        state.mapRotation = _calibrationService.getMapRotation(newPair) ?? 0.0;
      } else {
        state.mapRotation = 0.0;
      }
    });
  }

  void _recalculateCanPlaceTarget() {
    setState(() {
      state.canPlaceTarget = _calibrationService.totalAnchorCount >= 2;
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
    if (state.workingPair == null) {
      showSnackBar(
        'Режим сопровождения доступен только после привязки карты (добавьте минимум 2 точки привязки)',
      );
      return;
    }
    state.followRestoreTimer?.cancel();
    setState(() {
      state.followMode = true;
      state.crosshairInCenter = false;
    });
    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();
    _centerMapOnUser();
    _applyHeadingRotation();
  }

  void disableFollowMode() {
    state.followRestoreTimer?.cancel();
    setState(() {
      state.followMode = false;
      state.crosshairInCenter = true;
    });
    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();
  }

  void toggleFollowMode() {
    if (!state.followMode && state.workingPair == null) {
      showSnackBar('Режим сопровождения доступен только после привязки карты');
      return;
    }
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

  Future<void> _loadRotateModeTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    rotateModeTimeoutMs = prefs.getInt('rotateModeTimeoutMs') ?? 1000;
  }

  void enableRotateMode() {
    setState(() {
      state.rotateMode = true;
    });
    _resetRotateModeTimer();
  }

  void disableRotateMode() {
    state.rotateModeTimer?.cancel();
    setState(() {
      state.rotateMode = false;
    });
  }

  void resetRotateModeTimer() {
    _resetRotateModeTimer();
  }

  void _resetRotateModeTimer() {
    state.rotateModeTimer?.cancel();
    if (!state.rotateMode) return;
    if (rotateModeTimeoutMs <= 0) return;
    state.rotateModeTimer = Timer(
      Duration(milliseconds: rotateModeTimeoutMs),
      () {
        if (state.isDisposed) return;
        setState(() {
          state.rotateMode = false;
          state.rotateModeTimer = null;
        });
      },
    );
  }

  // --------------------------------------------------------
  // GPS подписка
  // --------------------------------------------------------

  void _startGpsCompassService() {
    GpsCompassService.instance.start(_sensorSettings);
  }

  void _startGpsSubscription() {
    GpsCompassService.instance.bearingNotifier.addListener(
      _onGpsBearingChanged,
    );
    _gpsSub = sensorService.subscribeToGps(
      intervalSeconds: _sensorSettings.gpsInterval,
      onData: (gpsData) {
        _lastGpsData = gpsData;

        if (state.followMode) {
          _recalculateUserImagePoint();
          _centerMapOnUser();
        } else {
          _recalculateUserImagePoint();
        }
      },
    );
  }

  void _onGpsBearingChanged() {
    final bearing = GpsCompassService.instance.bearingNotifier.value;
    final isActive = GpsCompassService.instance.isActiveNotifier.value;
    if (bearing != null && isActive) {
      setState(() {
        state.heading = (bearing - magneticDeclination + 360) % 360;
      });
      if (state.followMode) {
        _applyHeadingRotation();
      }
    }
  }

  // --------------------------------------------------------
  // Вспомогательные
  // --------------------------------------------------------

  void _saveCalibrationState() {
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
  }

  void _applyHeadingRotation() {
    if (!state.followMode ||
        state.heading == null ||
        state.workingPair == null) {
      return;
    }

    _isAutoRotating = true;

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

  static const double _tapRadiusScreen =
      24.0; // комфортный радиус в экранных пикселях

  MapAnchor? _findClosestAnchor(Offset screenPosition) {
    final project = state.project;
    final imageSize = state.imageSize;
    final scale = state.transformState.scale;
    if (project == null || imageSize == null || scale <= 0) return null;

    // Переводим радиус из экранных пикселей в пиксели изображения
    final double tapRadiusImage = _tapRadiusScreen / scale;
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
