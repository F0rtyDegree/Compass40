// ignore_for_file: avoid_print

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';
import '../services/map_storage_service.dart';
import '../controllers/map_screen_state.dart';
import '../controllers/map_screen_logic.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/map_image_painter.dart';
import '../widgets/map_overlay_painter.dart';
import '../widgets/map_zoom_buttons.dart';
import 'help_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gps_info/gps_info.dart';
import '../controllers/map_screen_controller.dart';
import 'package:flutter/services.dart';
import '../services/background_tracker.dart';

typedef StartNavigationCallback = Future<void> Function(double lat, double lon);

class MapScreen extends StatefulWidget {
  final ValueNotifier<GpsData> gpsDataNotifier;
  final double magneticDeclination;
  final ValueNotifier<double> headingNotifier;
  final Function(double lat, double lon, double? distance, String timeStr)?
  onAnchorAdded;
  final StartNavigationCallback? onStartNavigation;
  final VoidCallback? onCancelNavigation;

  const MapScreen({
    super.key,
    required this.gpsDataNotifier,
    this.magneticDeclination = 0.0,
    required this.headingNotifier,
    this.onAnchorAdded,
    this.onStartNavigation,
    this.onCancelNavigation,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapStorageService _storageService = MapStorageService();
  final MapScreenState _state = MapScreenState();
  late final MapScreenLogic _logic;
  final MethodChannel _controlChannel = MethodChannel(
    'by.fortydegree.compass40/control',
  );

  Offset _gestureStartTranslation = Offset.zero;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  Offset _gestureStartFocalPoint = Offset.zero;
  Offset? _gestureStartPivotImage;
  double _accumulatedRotation = 0.0;
  double _lastAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _logic = MapScreenLogic(
      state: _state,
      setState: (fn) {
        if (mounted) setState(fn);
      },
      showSnackBar: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
          );
        }
      },
      storageService: _storageService,
      gpsDataNotifier: widget.gpsDataNotifier,
      magneticDeclination: widget.magneticDeclination,
      headingNotifier: widget.headingNotifier,
      onAnchorAdded: widget.onAnchorAdded,
      onStartNavigation: widget.onStartNavigation,
      onCancelNavigation: widget.onCancelNavigation,
      askDistanceDialog: _showPhotoSeverDistanceDialog,
      onAnchorsChangedForStatus: _updateStatusText, // <-- Наша новая связь
    );
    _logic.init().then(
      (_) => _updateStatusText(),
    ); // Обновляем статус после инициализации

    MapScreenController().register(_logic);
    _controlChannel.invokeMethod('setMapActive', true);
  }

  void _updateStatusText() {
    final used = _logic.usedAnchorCount;
    final total = _logic.totalAnchorCount;
    print('📊 _updateStatusText: used=$used, total=$total');
    updateNotification(title: 'Режим - Карта $used/$total');
  }

  @override
  void dispose() {
    _controlChannel.invokeMethod('setMapActive', false);
    MapScreenController().unregister();
    print(
      '🔔 MapScreen.dispose: calling updateNotification with "Compass activate"',
    );
    updateNotification(title: 'Режим - Компас');
    _logic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _state.plannedTarget == null,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _state.plannedTarget != null) {
          _logic.cancelPlannedTarget();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Карта'),
          centerTitle: true,
          actions: [
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HelpViewerScreen(
                      helpFilePath: 'assets/help/map_help.md',
                    ),
                  ),
                );
              },
            ),
            if (_state.imagePath != null)
              Tooltip(
                message: 'Действия с картой',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => _showMapActionsDialog(context),
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.delete_forever),
                  ),
                ),
              ),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_state.imagePath == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.map, size: 72, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('Карта не загружена', style: TextStyle(fontSize: 18)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () => _logic.pickImage(),
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Выбрать фото карты'),
            ),
          ],
        ),
      );
    }

    if (_state.imageSize == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return _buildMapView();
  }

  Widget _buildMapView() {
    final imageSize = _state.imageSize!;
    final imagePath = _state.imagePath!;

    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onTapUp: (details) {
        _logic.handleTapOnMap(details.localPosition);
      },
      onLongPressStart: (details) {
        _logic.handleLongPressOnMap(context, details.localPosition);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _logic.updateViewportSize(viewportSize);
          });
          return Stack(
            children: [
              MapImageLayer(
                imagePath: imagePath,
                imageSize: imageSize,
                transformState: _state.transformState,
                viewportSize: viewportSize,
              ),
              CustomPaint(
                size: viewportSize,
                painter: MapOverlayPainter(
                  imageSize: imageSize,
                  transformState: _state.transformState,
                  viewportSize: viewportSize,
                  anchors: _state.project?.anchors ?? [],
                  targets: [
                    ..._state.project?.targets ?? [],
                    if (_state.plannedTarget != null) _state.plannedTarget!,
                  ],
                  activeAnchorIds: _logic.activeAnchorIds ?? {},
                  userPath: _logic.usedAnchorCount > 0
                      ? (_state.project?.userPath ?? [])
                      : [],
                  pathJumpIndices: _state.project?.pathJumpIndices ?? [],
                  currentUserImagePoint: _state.currentUserImagePoint,
                  activeTargetImagePoint: _state.activeTarget != null
                      ? Offset(
                          _state.activeTarget!.imageX,
                          _state.activeTarget!.imageY,
                        )
                      : null,
                  previewDistanceMeters: _state.previewDistanceMeters,
                  previewBearingDegrees: _state.previewBearingDegrees,
                  heading: _state.heading,
                  isGpsActive: _state.isGpsActive,
                  mapRotation: _state.mapRotation,
                  magneticDeclination: widget.magneticDeclination,
                ),
              ),
              Builder(
                builder: (context) {
                  final vp = _state.viewportSize;
                  if (vp == null) return const SizedBox.shrink();
                  final crosshairPosition = _logic.getCrosshairScreenPoint();
                  return Stack(
                    children: [
                      Positioned(
                        left: crosshairPosition.dx - 40,
                        top: crosshairPosition.dy - 40,
                        width: 80,
                        height: 80,
                        child: GestureDetector(
                          onTap: () {
                            // ✅ ИСПРАВЛЕНО: обращаемся к флагу и методу контроллера
                            if (_logic.photoSeverController.isActive) {
                              _logic.photoSeverController.handleTap(
                                _state.crosshairImagePoint!,
                              );
                            }
                          },
                          onDoubleTap: _logic.toggleFollowMode,
                          onLongPress: () =>
                              _logic.copyCrosshairCoordinatesToClipboard(),
                          child: Container(color: Colors.transparent),
                        ),
                      ),
                      MapCrosshair(
                        inCenter: _state.crosshairInCenter,
                        feedback: _state.crosshairFeedback,
                      ),
                    ],
                  );
                },
              ),

              if (_state.project != null && _state.project!.anchors.isNotEmpty)
                Positioned(top: 12, right: 12, child: _buildAnchorBadge()),
              Positioned(top: 12, left: 12, child: _buildModeIndicator()),

              MapZoomButtons(
                visible: _state.imagePath != null && _state.imageSize != null,
                onHereNowPressed: _logic.addAnchorFromCurrentGps,
                onHereFromClipboard: () => _logic.showHereOptions(context),
                hereEnabled: !_state.followMode,
                onTargetPressed: _state.canPlaceTarget && !_state.followMode
                    ? (_state.plannedTarget == null
                          ? _logic.placePlannedTargetAtCrosshair
                          : _logic.setTargetAndStartNavigation)
                    : null,
                onTargetLongPressed: _state.canPlaceTarget && !_state.followMode
                    ? _logic.placeTargetFromClipboard
                    : null,
                targetText: _state.plannedTarget == null ? 'ЦЕЛЬ' : 'ГОУ',
                targetEnabled: _state.canPlaceTarget && !_state.followMode,
                onZoomIn: _logic.zoomIn,
                onZoomOut: _logic.zoomOut,
                rotateMode: _state.rotateMode,
                onToggleRotateMode: () {
                  if (_state.rotateMode) {
                    _logic.disableRotateMode();
                  } else {
                    _logic.enableRotateMode();
                  }
                },
                onResetRotation: _resetRotation,
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetRotation() {
    final current = _state.transformState;
    final declinationRad = widget.magneticDeclination * math.pi / 180;

    // Вычисляем целевой поворот через статический метод логики
    final newRotation = MapScreenLogic.computeResetRotation(
      mapRotation: _state.mapRotation,
      photoSeverNorthAngle: _state.project?.photoSeverNorthAngle ?? 0.0,
      photoSeverLinePixels: _state.project?.photoSeverLinePixels ?? 0.0,
      declinationRad: declinationRad,
    );

    // Нормализация в [-π, π]
    double normalized = newRotation % (2 * math.pi);
    if (normalized > math.pi) normalized -= 2 * math.pi;
    if (normalized <= -math.pi) normalized += 2 * math.pi;

    // Применяем с удержанием перекрестия на месте
    if (_state.viewportSize != null && _state.imageSize != null) {
      final pivotScreen = _logic.getCrosshairScreenPoint();
      final pivotImage = _logic.screenToImage(pivotScreen);
      final tempTransform = MapTransformState(
        scale: current.scale,
        rotationRadians: normalized,
        translation: current.translation,
      );
      final oldTransform = _state.transformState;
      _state.transformState = tempTransform;
      final pivotScreenAfterReset = _logic.imageToScreen(pivotImage);
      _state.transformState = oldTransform;
      final delta = pivotScreen - pivotScreenAfterReset;
      final newTranslation = current.translation + delta;
      _logic.updateTransform(
        MapTransformState(
          scale: current.scale,
          rotationRadians: normalized,
          translation: newTranslation,
        ),
      );
    } else {
      _logic.updateTransform(
        MapTransformState(
          scale: current.scale,
          rotationRadians: normalized,
          translation: current.translation,
        ),
      );
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartTranslation = _state.transformState.translation;
    _gestureStartScale = _state.transformState.scale;
    _gestureStartRotation = _state.transformState.rotationRadians;
    _gestureStartFocalPoint = details.focalPoint;
    if (_state.viewportSize != null && _state.imageSize != null) {
      final pivotScreen = _logic.getCrosshairScreenPoint();
      _gestureStartPivotImage = _logic.screenToImage(pivotScreen);
    } else {
      _gestureStartPivotImage = null;
    }
    _accumulatedRotation = 0.0;
    if (_state.viewportSize != null && _state.imageSize != null) {
      final pivotScreen = _logic.getCrosshairScreenPoint();
      final startVector = _gestureStartFocalPoint - pivotScreen;
      _lastAngle = math.atan2(startVector.dy, startVector.dx);
    } else {
      _lastAngle = 0.0;
    }
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_state.viewportSize == null || _state.imageSize == null) return;
    final pointerCount = details.pointerCount;
    if (pointerCount == 1) {
      if (_state.rotateMode) {
        final currentFocalPoint = details.focalPoint;
        final pivotScreen = _logic.getCrosshairScreenPoint();
        final currentVector = currentFocalPoint - pivotScreen;
        final currentAngle = math.atan2(currentVector.dy, currentVector.dx);
        double deltaAngle = currentAngle - _lastAngle;
        if (deltaAngle > math.pi) deltaAngle -= 2 * math.pi;
        if (deltaAngle < -math.pi) deltaAngle += 2 * math.pi;
        _accumulatedRotation += deltaAngle;
        _lastAngle = currentAngle;
        const sensitivity = 0.8;
        final newRotation =
            _gestureStartRotation + _accumulatedRotation * sensitivity;
        if (_gestureStartPivotImage != null) {
          final tempTransform = MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: newRotation,
            translation: _gestureStartTranslation,
          );
          final oldTransform = _state.transformState;
          _state.transformState = tempTransform;
          final pivotScreenAfterRotate = _logic.imageToScreen(
            _gestureStartPivotImage!,
          );
          _state.transformState = oldTransform;
          final delta = pivotScreen - pivotScreenAfterRotate;
          final newTranslation = _gestureStartTranslation + delta;
          _logic.updateTransform(
            MapTransformState(
              scale: _state.transformState.scale,
              rotationRadians: newRotation,
              translation: newTranslation,
            ),
          );
        } else {
          _logic.updateTransform(
            MapTransformState(
              scale: _state.transformState.scale,
              rotationRadians: newRotation,
              translation: _state.transformState.translation,
            ),
          );
        }
        _logic.resetRotateModeTimer();
      } else {
        final delta = details.focalPoint - _gestureStartFocalPoint;
        final newTranslation = _gestureStartTranslation + delta;
        _logic.updateTransform(
          MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: _state.transformState.rotationRadians,
            translation: newTranslation,
          ),
        );
      }
      return;
    }
    if (pointerCount == 2) {
      final scaleChange = (details.scale - 1.0).abs();
      final rotationChange = details.rotation.abs();
      if (scaleChange > rotationChange) {
        final newScale = (_gestureStartScale * details.scale).clamp(0.05, 20.0);
        if (_gestureStartPivotImage != null) {
          final pivotScreen = _logic.getCrosshairScreenPoint();
          final tempTransform = MapTransformState(
            scale: newScale,
            rotationRadians: _state.transformState.rotationRadians,
            translation: _gestureStartTranslation,
          );
          final oldTransform = _state.transformState;
          _state.transformState = tempTransform;
          final pivotScreenAfterScale = _logic.imageToScreen(
            _gestureStartPivotImage!,
          );
          _state.transformState = oldTransform;
          final delta = pivotScreen - pivotScreenAfterScale;
          final newTranslation = _gestureStartTranslation + delta;
          _logic.updateTransform(
            MapTransformState(
              scale: newScale,
              rotationRadians: _state.transformState.rotationRadians,
              translation: newTranslation,
            ),
          );
        } else {
          _logic.updateTransform(
            MapTransformState(
              scale: newScale,
              rotationRadians: _state.transformState.rotationRadians,
              translation: _gestureStartTranslation,
            ),
          );
        }
      } else {
        final pivotScreen = _logic.getCrosshairScreenPoint();
        final currentRotation = _gestureStartRotation + details.rotation;
        if (_gestureStartPivotImage != null) {
          final tempTransform = MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: currentRotation,
            translation: _gestureStartTranslation,
          );
          final oldTransform = _state.transformState;
          _state.transformState = tempTransform;
          final pivotScreenAfterRotate = _logic.imageToScreen(
            _gestureStartPivotImage!,
          );
          _state.transformState = oldTransform;
          final delta = pivotScreen - pivotScreenAfterRotate;
          final newTranslation = _gestureStartTranslation + delta;
          _logic.updateTransform(
            MapTransformState(
              scale: _state.transformState.scale,
              rotationRadians: currentRotation,
              translation: newTranslation,
            ),
          );
        } else {
          _logic.updateTransform(
            MapTransformState(
              scale: _state.transformState.scale,
              rotationRadians: currentRotation,
              translation: _state.transformState.translation,
            ),
          );
        }
      }
      return;
    }
    if (pointerCount >= 3) {
      final currentFocalPoint = details.focalPoint;
      final pivotScreen = _logic.getCrosshairScreenPoint();
      final startVector = _gestureStartFocalPoint - pivotScreen;
      final currentVector = currentFocalPoint - pivotScreen;
      final startAngle = math.atan2(startVector.dy, startVector.dx);
      final currentAngle = math.atan2(currentVector.dy, currentVector.dx);
      double deltaAngle = currentAngle - startAngle;
      if (deltaAngle > math.pi) deltaAngle -= 2 * math.pi;
      if (deltaAngle < -math.pi) deltaAngle += 2 * math.pi;
      const sensitivity = 0.8;
      final newRotation = _gestureStartRotation + deltaAngle * sensitivity;
      if (_gestureStartPivotImage != null) {
        final tempTransform = MapTransformState(
          scale: _state.transformState.scale,
          rotationRadians: newRotation,
          translation: _gestureStartTranslation,
        );
        final oldTransform = _state.transformState;
        _state.transformState = tempTransform;
        final pivotScreenAfterRotate = _logic.imageToScreen(
          _gestureStartPivotImage!,
        );
        _state.transformState = oldTransform;
        final delta = pivotScreen - pivotScreenAfterRotate;
        final newTranslation = _gestureStartTranslation + delta;
        _logic.updateTransform(
          MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: newRotation,
            translation: newTranslation,
          ),
        );
      } else {
        _logic.updateTransform(
          MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: newRotation,
            translation: _state.transformState.translation,
          ),
        );
      }
      return;
    }
  }

  Future<void> _showMapActionsDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Действия с картой'),
        children: [
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx); // закрываем меню действий
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Удалить карту?'),
                  content: const Text('Привязки, цели и путь будут удалены.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                // ignore: use_build_context_synchronously
                final navigator = Navigator.of(context);
                await _logic.closeMap();
                navigator.pop();
              }
            },
            child: const Text(
              'Удалить карту',
              style: TextStyle(color: Colors.red),
            ),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.pop(ctx);
              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Удалить все якоря?'),
                  content: const Text(
                    'Привязка карты будет потеряна, цели сохранятся.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Отмена'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text(
                        'Удалить',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) await _logic.clearAllAnchors();
            },
            child: const Text('Удалить все якоря'),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _logic.clearUserPath();
            },
            child: const Text('Удалить путь пользователя'),
          ),
        ],
      ),
    );
  }

  Future<double?> _showPhotoSeverDistanceDialog() async {
    const defaultDistance = 250.0;
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return null;
    final savedDistance =
        prefs.getDouble('photoSeverDistance') ?? defaultDistance;

    final controller = TextEditingController(
      text: savedDistance.toStringAsFixed(0),
    );
    final result = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Расстояние до линии'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'Метры',
            labelText: 'Расстояние от 3-й точки до линии север-юг',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final val = double.tryParse(controller.text);
              if (val != null && val > 0) {
                prefs.setDouble('photoSeverDistance', val);
              }
              Navigator.pop(ctx, val);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
    if (!mounted) return null;
    return result;
  }

  Widget _buildModeIndicator() {
    final letter = _logic.calibrationModeLetter;
    return GestureDetector(
      onTap: () async {
        await _logic.showModePicker(context);
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black54,
          boxShadow: [
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.8),
              blurRadius: 3,
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            shadows: [Shadow(color: Colors.black, blurRadius: 2)],
          ),
        ),
      ),
    );
  }

  Widget _buildAnchorBadge() {
    final totalCount = _logic.totalAnchorCount;
    if (totalCount == 0) return const SizedBox.shrink();
    final used = _logic.usedAnchorCount;
    final metersPerPx = _logic.metersPerScreenPixel;

    final Color textColor;
    if (totalCount >= 3) {
      textColor = Colors.green;
    } else if (totalCount == 2 && used == 2) {
      textColor = Colors.orange;
    } else {
      textColor = Colors.red;
    }

    double segmentWidth = 0;
    String scaleLabel = '';
    if (metersPerPx != null && metersPerPx > 0) {
      final screenWidth = MediaQuery.of(context).size.width;
      final maxWidth = screenWidth * 0.4;
      const niceNumbers = [
        1,
        2,
        5,
        10,
        20,
        50,
        100,
        150,
        200,
        250,
        500,
        1000,
        2000,
        5000,
      ];
      for (final num in niceNumbers) {
        final w = num / metersPerPx;
        if (w <= maxWidth) {
          segmentWidth = w;
          scaleLabel = '$num м';
        } else {
          break;
        }
      }
      if (segmentWidth == 0) {
        segmentWidth = niceNumbers.last / metersPerPx;
        scaleLabel = '${niceNumbers.last} м';
      }
    }

    final double? dist = _logic.distanceToCrosshairMeters;
    final String topLeftDisplay = '📏';
    final String topRightDisplay = dist != null
        ? (dist >= 1000
              ? '${(dist / 1000).toStringAsFixed(1)} км'
              : '${dist.round()} м')
        : '---';

    Widget topRowFullWidth = const SizedBox.shrink();
    if (metersPerPx != null && segmentWidth > 0) {
      if (topRightDisplay.isNotEmpty) {
        topRowFullWidth = SizedBox(
          width: segmentWidth,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                topLeftDisplay,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 2),
                    Shadow(color: Colors.white, blurRadius: 4),
                    Shadow(color: Colors.white, blurRadius: 6),
                  ],
                ),
              ),
              Text(
                topRightDisplay,
                style: TextStyle(
                  color: textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(color: Colors.white, blurRadius: 2),
                    Shadow(color: Colors.white, blurRadius: 4),
                    Shadow(color: Colors.white, blurRadius: 6),
                  ],
                ),
              ),
            ],
          ),
        );
      } else {
        topRowFullWidth = SizedBox(
          width: segmentWidth,
          child: Text(
            topLeftDisplay,
            style: TextStyle(
              color: textColor,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(color: Colors.white, blurRadius: 2),
                Shadow(color: Colors.white, blurRadius: 4),
                Shadow(color: Colors.white, blurRadius: 6),
              ],
            ),
          ),
        );
      }
    }

    Widget scaleWidget;
    if (metersPerPx != null && segmentWidth > 0) {
      scaleWidget = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: topRowFullWidth,
          ),
          Container(
            width: segmentWidth,
            height: 2,
            decoration: BoxDecoration(
              color: Colors.black,
              boxShadow: [
                BoxShadow(color: Colors.white, blurRadius: 4, spreadRadius: 0),
              ],
            ),
          ),
          SizedBox(
            width: segmentWidth,
            child: Text(
              scaleLabel,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 15,
                fontWeight: FontWeight.bold,
                shadows: [
                  Shadow(color: Colors.white, blurRadius: 2),
                  Shadow(color: Colors.white, blurRadius: 4),
                  Shadow(color: Colors.white, blurRadius: 6),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      );
    } else {
      scaleWidget = Text(
        topLeftDisplay,
        style: TextStyle(
          color: textColor,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          shadows: [
            Shadow(color: Colors.white, blurRadius: 2),
            Shadow(color: Colors.white, blurRadius: 4),
            Shadow(color: Colors.white, blurRadius: 6),
          ],
        ),
      );
    }

    return Tooltip(message: 'Масштабная линейка', child: scaleWidget);
  }
}
