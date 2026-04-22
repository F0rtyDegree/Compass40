import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import '../models/map_transform_state.dart';
import '../services/map_storage_service.dart';
import '../controllers/map_screen_state.dart';
import '../controllers/map_screen_logic.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/map_image_painter.dart';
import '../widgets/map_overlay_painter.dart';
import '../widgets/map_toolbar.dart';

class MapScreen extends StatefulWidget {
  final void Function(Map<String, double> targetGeo)? onTargetActivated;
  final double magneticDeclination;

  const MapScreen({
    super.key,
    this.onTargetActivated,
    this.magneticDeclination = 0.0,
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
  Offset _gestureStartFocalPoint = Offset.zero;

  @override
  void initState() {
    super.initState();
    _logic = MapScreenLogic(
      state: _state,
      hostState: this,
      storageService: _storageService,
      gpsInfo: GpsInfo(),
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
              IconButton(
                icon: Icon(
                  _state.followMode
                      ? Icons.gps_fixed
                      : Icons.gps_not_fixed,
                  color: _state.followMode ? Colors.blue : null,
                ),
                onPressed: () {
                  if (_state.followMode) {
                    setState(() => _state.followMode = false);
                  } else {
                    _logic.enableFollowMode();
                  }
                },
                tooltip: 'Следовать',
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Закрыть карту?'),
                      content: const Text('Привязки и цели будут сброшены.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Отмена'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Закрыть',
                              style: TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) await _logic.closeMap();
                },
                tooltip: 'Закрыть карту',
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
      onDoubleTap: _logic.toggleCrosshairPosition,
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
                  currentUserImagePoint: _state.currentUserImagePoint,
                  activeTargetImagePoint: _state.activeTarget != null
                      ? Offset(
                          _state.activeTarget!.imageX,
                          _state.activeTarget!.imageY,
                        )
                      : null,
                  previewDistanceMeters: _state.previewDistanceMeters,
                  previewBearingDegrees: _state.previewBearingDegrees,
                ),
              ),

              // Слой 3: прицел
              MapCrosshair(inCenter: _state.crosshairInCenter),

              // Слой 4: бейдж привязок
              if (_state.project != null &&
                  _state.project!.anchors.isNotEmpty)
                Positioned(
                  top: 12,
                  right: 12,
                  child: _buildAnchorBadge(),
                ),

              // Слой 5: тулбар
              MapToolbar(
                onHereNowPressed: _logic.addAnchorFromCurrentGps,
                onHereFromClipboard: _logic.addAnchorFromClipboard,
                onTargetPressed: _state.canPlaceTarget
                    ? (_state.plannedTarget == null
                        ? _logic.placePlannedTargetAtCrosshair
                        : () => _logic.activatePlannedTarget(
                              magneticDeclination: widget.magneticDeclination,
                              onActivate: (geo) {
                                widget.onTargetActivated?.call(geo);
                              },
                            ))
                    : null,
                targetEnabled: _state.canPlaceTarget,
                targetText: _state.plannedTarget == null ? 'ЦЕЛЬ' : 'ГОУ',
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------
  // Жесты: pan + zoom относительно прицела
  // ---------------------------------------------------------

  void _onScaleStart(ScaleStartDetails details) {
    _gestureStartTranslation = _state.transformState.translation;
    _gestureStartScale = _state.transformState.scale;
    _gestureStartFocalPoint = details.focalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_state.viewportSize == null) return;
    final newScale =
        (_gestureStartScale * details.scale).clamp(0.05, 20.0);

    // Точка масштабирования — прицел
    final crosshairScreen = _logic.getCrosshairScreenPoint();

    // Вектор от прицела до начальной фокальной точки
    final focalFromCrosshair =
        _gestureStartFocalPoint - crosshairScreen;

    // Pan: смещение фокальной точки
    final focalDelta = details.focalPoint - _gestureStartFocalPoint;

    // Масштабирование относительно прицела:
    // точка под прицелом не двигается
    final scaleRatio = newScale / _gestureStartScale;

    final newTranslation = Offset(
      _gestureStartTranslation.dx +
          focalDelta.dx +
          focalFromCrosshair.dx * (1 - scaleRatio),
      _gestureStartTranslation.dy +
          focalDelta.dy +
          focalFromCrosshair.dy * (1 - scaleRatio),
    );

    _logic.updateTransform(
      MapTransformState(
        scale: newScale,
        rotationRadians: _state.transformState.rotationRadians,
        translation: newTranslation,
      ),
    );
  }

  Widget _buildAnchorBadge() {
    final count = _state.project!.anchors.length;
    final hasWorkingPair = _state.workingPair != null;

    return Container(
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
    );
  }
}
