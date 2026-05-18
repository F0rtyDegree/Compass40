import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

// Статический кеш загруженных изображений
final Map<String, ui.Image> _imageCache = {};

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
  bool _isLoading = false;

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
    if (_imageCache.containsKey(widget.imagePath)) {
      if (mounted) {
        setState(() {
          _image = _imageCache[widget.imagePath];
        });
      }
      return;
    }

    if (_isLoading) return;
    
    if(mounted){
      setState(() {
        _isLoading = true;
        _image = null; // Reset image on new load
      });
    }

    try {
      final bytes = await File(widget.imagePath).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final loadedImage = frame.image;
      _imageCache[widget.imagePath] = loadedImage;
      if (mounted) {
        setState(() {
          _image = loadedImage;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
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

    canvas.drawImage(
      image!,
      Offset(-imageSize.width / 2, -imageSize.height / 2),
      Paint()..filterQuality = FilterQuality.high,
    );

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
