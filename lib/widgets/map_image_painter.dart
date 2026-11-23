import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

// Статический кеш загруженных изображений
final Map<String, ui.Image> _imageCache = {};
final Map<String, Future<ui.Image>> _pendingLoads = {};

/// Удаляет изображение из кэша и освобождает память.
void removeImageFromCache(String path) {
  _pendingLoads.remove(path);
  final image = _imageCache.remove(path);
  image?.dispose();
}

/// Возвращает изображение из кэша. Если нет — декодирует и кладёт в кэш.
/// Параллельные вызовы для одного пути ожидают единую задачу декодирования.
/// Владелец — кэш. Вызывающий не должен вызывать dispose.
Future<ui.Image> getOrCreateImage(String path) {
  final cached = _imageCache[path];
  if (cached != null) return Future.value(cached);

  final pending = _pendingLoads[path];
  if (pending != null) return pending;

  final loadFuture = _decodeImage(path);
  _pendingLoads[path] = loadFuture;
  return loadFuture;
}

Future<ui.Image> _decodeImage(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;

    if (!_pendingLoads.containsKey(path)) {
      image.dispose();
      return image;
    }

    _imageCache[path] = image;
    return image;
  } finally {
    _pendingLoads.remove(path);
  }
}

/// Отрисовывает изображение карты с трансформацией.
class MapImageLayer extends StatefulWidget {
  final String imagePath;
  final Size imageSize;
  final MapTransformState transformState;
  final Size viewportSize;

  const MapImageLayer({
    super.key,
    required this.imagePath,
    required this.imageSize,
    required this.transformState,
    required this.viewportSize,
  });

  @override
  State<MapImageLayer> createState() => _MapImageLayerState();
}

class _MapImageLayerState extends State<MapImageLayer> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(MapImageLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imagePath != oldWidget.imagePath) {
      _loadImage();
    }
  }

  Future<void> _loadImage() async {
    final targetPath = widget.imagePath;
    if (_imageCache.containsKey(targetPath)) {
      if (mounted) {
        setState(() {
          _image = _imageCache[targetPath];
        });
      }
      return;
    }

    if (mounted && _image != null) {
      setState(() {
        _image = null;
      });
    }

    try {
      final loadedImage = await getOrCreateImage(targetPath);
      if (mounted && widget.imagePath == targetPath) {
        setState(() {
          _image = loadedImage;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.transformState.scale;
    final r = widget.transformState.rotationRadians;
    final tx = widget.transformState.translation.dx;
    final ty = widget.transformState.translation.dy;

    final vpCx = widget.viewportSize.width / 2.0;
    final vpCy = widget.viewportSize.height / 2.0;

    final finalX = vpCx + tx;
    final finalY = vpCy + ty;

    return ClipRect(
      child: SizedBox(
        width: widget.viewportSize.width,
        height: widget.viewportSize.height,
        child: CustomPaint(
          painter: _ImagePainter(
            image: _image,
            imageSize: widget.imageSize,
            scale: s,
            rotation: r,
            centerX: finalX,
            centerY: finalY,
          ),
        ),
      ),
    );
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image? image;
  final Size imageSize;
  final double scale;
  final double rotation;
  final double centerX;
  final double centerY;

  _ImagePainter({
    required this.image,
    required this.imageSize,
    required this.scale,
    required this.rotation,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) {
      _drawPlaceholder(canvas);
      return;
    }

    canvas.save();
    canvas.translate(centerX, centerY);
    canvas.rotate(rotation);
    canvas.scale(scale);

    try {
      canvas.drawImage(
        image!,
        Offset(-imageSize.width / 2, -imageSize.height / 2),
        Paint()..filterQuality = FilterQuality.high,
      );
    } catch (_) {
      // Image is disposed, ignore
    }

    canvas.restore();
  }

  void _drawPlaceholder(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0xFFE0E0E0)
      ..style = PaintingStyle.fill;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(centerX, centerY),
        width: imageSize.width * scale,
        height: imageSize.height * scale,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) {
    return old.image != image ||
        old.scale != scale ||
        old.rotation != rotation ||
        old.centerX != centerX ||
        old.centerY != centerY;
  }
}
