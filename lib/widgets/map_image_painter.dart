import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

/// Отрисовывает изображение карты с трансформацией.
/// Центр координатной системы — центр viewport.
/// Изображение рисуется своим центром в центре экрана,
/// затем применяется масштаб, поворот и пользовательский сдвиг.
class MapImageLayer extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final s = transformState.scale;
    final r = transformState.rotationRadians;
    final tx = transformState.translation.dx;
    final ty = transformState.translation.dy;

    // Центр viewport
    final vpCx = viewportSize.width / 2.0;
    final vpCy = viewportSize.height / 2.0;

    // Итоговое смещение центра изображения на экране:
    // центр изображения → в начало координат → масштаб+поворот → в центр экрана + пользовательский сдвиг
    final finalX = vpCx + tx;
    final finalY = vpCy + ty;

    return ClipRect(
      child: SizedBox(
        width: viewportSize.width,
        height: viewportSize.height,
        child: CustomPaint(
          painter: _ImagePainter(
            imagePath: imagePath,
            imageSize: imageSize,
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
  final String imagePath;
  final Size imageSize;
  final double scale;
  final double rotation;
  final double centerX;
  final double centerY;

  // Статический кеш загруженных изображений
  static final Map<String, ui.Image?> _cache = {};
  static final Map<String, bool> _loading = {};

  _ImagePainter({
    required this.imagePath,
    required this.imageSize,
    required this.scale,
    required this.rotation,
    required this.centerX,
    required this.centerY,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final cachedImage = _cache[imagePath];

    if (cachedImage == null) {
      // Рисуем placeholder
      _drawPlaceholder(canvas);
      // Запускаем загрузку если ещё не загружается
      if (_loading[imagePath] != true) {
        _loading[imagePath] = true;
        _loadImage(imagePath);
      }
      return;
    }

    canvas.save();

    // Переходим в точку отображения центра карты
    canvas.translate(centerX, centerY);
    canvas.rotate(rotation);
    canvas.scale(scale);

    // Рисуем изображение со смещением так, чтобы его центр совпал с (0,0)
    canvas.drawImage(
      cachedImage,
      Offset(-imageSize.width / 2, -imageSize.height / 2),
      Paint()..filterQuality = FilterQuality.medium,
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

  Future<void> _loadImage(String path) async {
    try {
      final bytes = await File(path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      _cache[path] = frame.image;
      _loading[path] = false;
    } catch (e) {
      _loading[path] = false;
    }
  }

  @override
  bool shouldRepaint(covariant _ImagePainter old) {
    return old.scale != scale ||
        old.rotation != rotation ||
        old.centerX != centerX ||
        old.centerY != centerY ||
        old.imagePath != imagePath;
  }
}
