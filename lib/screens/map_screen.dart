import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';
import '../services/map_storage_service.dart';
import '../controllers/map_screen_state.dart';
import '../controllers/map_screen_logic.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/map_image_painter.dart';
import '../widgets/map_overlay_painter.dart';
import '../widgets/map_toolbar.dart';
import '../widgets/map_zoom_buttons.dart';

typedef StartNavigationCallback = Future<void> Function(double lat, double lon);

class MapScreen extends StatefulWidget {
  final double magneticDeclination;
  final Function(double lat, double lon, double? distance, String timeStr)?
      onAnchorAdded;
  final StartNavigationCallback? onStartNavigation;
  final VoidCallback? onCancelNavigation;

  const MapScreen({
    super.key,
    this.magneticDeclination = 0.0,
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

  // Жесты
  Offset _gestureStartTranslation = Offset.zero;
  double _gestureStartScale = 1.0;
  double _gestureStartRotation = 0.0;
  Offset _gestureStartFocalPoint = Offset.zero;

  // Запоминаем пиксель под прицелом
  Offset? _gestureStartPivotImage;

  // Для накопления вращения
  double _accumulatedRotation = 0.0;
  double _lastAngle = 0.0;

  @override
  void initState() {
    super.initState();
    _logic = MapScreenLogic(
      state: _state,
      hostState: this,
      storageService: _storageService,
      magneticDeclination: widget.magneticDeclination, // Pass it here
      onAnchorAdded: widget.onAnchorAdded,
      onStartNavigation: widget.onStartNavigation,
      onCancelNavigation: widget.onCancelNavigation,
    );
    _logic.init();
  }

  @override
  void dispose() {
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
          title: const Text('Спорткарта'),
          centerTitle: true,
          actions: [
            if (_state.imagePath != null) ...[
              Tooltip(
                message: 'Удалить карту (долгое нажатие)',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onLongPress: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Удалить карту?'),
                        content: const Text('Привязки и цели будут удалены.'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Отмена'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text(
                              'Удалить',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) await _logic.closeMap();
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(12.0),
                    child: Icon(Icons.delete_forever),
                  ),
                ),
              ),
            ],
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
              // Слой 1: изображение
              MapImageLayer(
                imagePath: imagePath,
                imageSize: imageSize,
                transformState: _state.transformState,
                viewportSize: viewportSize,
              ),

              // Слой 2: оверлеи
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
                    userPath: _state.project?.userPath ?? [],
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
                    mapRotation: _state.mapRotation,
                    magneticDeclination:
                        widget.magneticDeclination, // Pass declination
                    ),
              ),

              // Слой 3: прицел с зоной двойного тапа
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
                          onTap: _logic.toggleFollowMode,
                          onDoubleTap: _logic.toggleCrosshairPosition,
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

              // Слой 4: бейдж привязок
              if (_state.project != null && _state.project!.anchors.isNotEmpty)
                Positioned(top: 12, right: 12, child: _buildAnchorBadge()),

              // Слой 5: тулбар
              MapToolbar(
                onHereNowPressed: _logic.addAnchorFromCurrentGps,
                onHereFromClipboard: _logic.addAnchorFromClipboard,
                onTargetPressed: _state.canPlaceTarget
                    ? (_state.plannedTarget == null
                        ? _logic.placePlannedTargetAtCrosshair
                        : _logic.activatePlannedTarget)
                    : null,
                onTargetLongPressed: _state.canPlaceTarget && _state.plannedTarget != null
                    ? _logic.setTargetAndStartNavigation
                    : null,
                targetEnabled: _state.canPlaceTarget && !_state.followMode,
                targetText: _state.plannedTarget == null ? 'ЦЕЛЬ' : 'ГОУ',
                followModeEnabled: _state.followMode,
              ),

              // Слой 6: кнопки масштаба и поворота
              MapZoomButtons(
                visible: _state.imagePath != null && _state.imageSize != null,
                onZoomIn: _zoomIn,
                onZoomOut: _zoomOut,
                rotateMode: _state.rotateMode,
                onToggleRotateMode: () {
                  setState(() {
                    _state.rotateMode = !_state.rotateMode;
                  });
                },
                onResetRotation: _resetRotation,
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------
  // Кнопки масштаба
  // ---------------------------------------------------------
  void _zoomIn() {
    final current = _state.transformState;
    final newScale = (current.scale * 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(current, newScale);
  }

  void _zoomOut() {
    final current = _state.transformState;
    final newScale = (current.scale / 1.5).clamp(0.05, 20.0);
    _scaleAroundCrosshair(current, newScale);
  }

  void _scaleAroundCrosshair(MapTransformState current, double newScale) {
    if (_state.viewportSize == null || _state.imageSize == null) return;

    final pivotScreen = _logic.getCrosshairScreenPoint();
    final pivotImage = _logic.screenToImage(pivotScreen);

    final tempTransform = MapTransformState(
      scale: newScale,
      rotationRadians: current.rotationRadians,
      translation: current.translation,
    );

    final oldTransform = _state.transformState;
    _state.transformState = tempTransform;

    final pivotScreenAfterScale = _logic.imageToScreen(pivotImage);

    _state.transformState = oldTransform;

    final delta = pivotScreen - pivotScreenAfterScale;
    final newTranslation = current.translation + delta;

    _logic.updateTransform(
      MapTransformState(
        scale: newScale,
        rotationRadians: current.rotationRadians,
        translation: newTranslation,
      ),
    );
  }

  // ---------------------------------------------------------
  // Сброс поворота
  // ---------------------------------------------------------
  void _resetRotation() {
    final current = _state.transformState;
    const newRotation = 0.0;

    if (_state.viewportSize != null && _state.imageSize != null) {
      final pivotScreen = _logic.getCrosshairScreenPoint();
      final pivotImage = _logic.screenToImage(pivotScreen);

      final tempTransform = MapTransformState(
        scale: current.scale,
        rotationRadians: newRotation,
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
          rotationRadians: newRotation,
          translation: newTranslation,
        ),
      );
    } else {
      _logic.updateTransform(
        MapTransformState(
          scale: current.scale,
          rotationRadians: newRotation,
          translation: current.translation,
        ),
      );
    }
  }

  // ---------------------------------------------------------
  // Жесты:
  // - 1 палец: панорамирование ИЛИ поворот (в зависимости от rotateMode)
  // - 2 пальца: масштабирование (вокруг прицела)
  // - 3+ пальца: вращение (вокруг прицела)
  // ---------------------------------------------------------
  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartTranslation = _state.transformState.translation;
    _gestureStartScale = _state.transformState.scale;
    _gestureStartRotation = _state.transformState.rotationRadians;
    _gestureStartFocalPoint = details.focalPoint;

    // Запоминаем пиксель под прицелом
    if (_state.viewportSize != null && _state.imageSize != null) {
      final pivotScreen = _logic.getCrosshairScreenPoint();
      _gestureStartPivotImage = _logic.screenToImage(pivotScreen);
    } else {
      _gestureStartPivotImage = null;
    }

    // Для вращения
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

    // --------------------------------------------------------
    // 1 палец
    // --------------------------------------------------------
    if (pointerCount == 1) {
      if (_state.rotateMode) {
        // Вращение одним пальцем вокруг прицела
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

          final pivotScreenAfterRotate =
              _logic.imageToScreen(_gestureStartPivotImage!);

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
      } else {
        // Панорамирование
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

    // --------------------------------------------------------
    // 2 пальца — умное масштабирование/вращение
    // --------------------------------------------------------
    if (pointerCount == 2) {
      final scaleChange = (details.scale - 1.0).abs();
      final rotationChange = details.rotation.abs();

      // Определяем, что преобладает
      if (scaleChange > rotationChange) {
        // ---------- МАСШТАБИРОВАНИЕ ----------
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

          final pivotScreenAfterScale =
              _logic.imageToScreen(_gestureStartPivotImage!);

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
        // ---------- ВРАЩЕНИЕ ----------
        final pivotScreen = _logic.getCrosshairScreenPoint();

        // Накопление угла для плавного вращения
        final currentRotation = _gestureStartRotation + details.rotation;

        if (_gestureStartPivotImage != null) {
          final tempTransform = MapTransformState(
            scale: _state.transformState.scale,
            rotationRadians: currentRotation,
            translation: _gestureStartTranslation,
          );

          final oldTransform = _state.transformState;
          _state.transformState = tempTransform;

          final pivotScreenAfterRotate =
              _logic.imageToScreen(_gestureStartPivotImage!);

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

    // --------------------------------------------------------
    // 3 и более пальцев — вращение вокруг прицела
    // --------------------------------------------------------
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

        final pivotScreenAfterRotate =
            _logic.imageToScreen(_gestureStartPivotImage!);

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

  Widget _buildAnchorBadge() {
    final count = _state.project!.anchors.length;
    if (count == 0) return const SizedBox.shrink();

    final hasWorkingPair = _state.workingPair != null;

    // Используем уникальный ключ, который меняется при изменении состояния, которое должно сбросить Dismissible
    // В данном случае, count - хороший кандидат.
    return Dismissible(
      key: ValueKey(count),
      direction: DismissDirection.endToStart, // Свайп справа налево
      confirmDismiss: (direction) async {
        if (_state.project!.anchors.length <= 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Нельзя удалить. Для привязки необходимо минимум 2 точки.'),
              backgroundColor: Colors.orangeAccent,
            ),
          );
          return false; // Запретить удаление
        }
        return true; // Разрешить удаление
      },
      onDismissed: (direction) {
        _logic.undoLastAnchor();
        // Этот SnackBar показывается после успешного удаления
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Последняя привязка удалена'),
            backgroundColor: Colors.redAccent,
          ),
        );
      },
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red,
          borderRadius: BorderRadius.circular(20),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Tooltip(
        message: 'Смахни влево чтобы удалить последнюю точку',
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: hasWorkingPair
                ? Colors.green.withAlpha(200)
                : Colors.orange.withAlpha(200),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            hasWorkingPair
                ? 'Карта привязана ($count)'
                : 'Привязок: $count (нужно ≥2, расстояние ≥50м)',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
