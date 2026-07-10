import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../utils/app_constants.dart';
import 'similarity_transform.dart';

class PhotoSeverTransform implements MapTransformer {
  final MapAnchor baseAnchor;
  final double lineMeters;
  final double linePixels;
  final double northAngle;

  PhotoSeverTransform({
    required this.baseAnchor,
    required this.lineMeters,
    required this.linePixels,
    required this.northAngle,
  });

  /// Масштаб вычисляется через пропорцию (без деления заранее)
  double _metersForPixels(double pixels) {
    if (linePixels == 0) return 0;
    return (pixels * lineMeters) / linePixels;
  }

  double _pixelsForMeters(double meters) {
    if (lineMeters == 0) return 0;
    return (meters * linePixels) / lineMeters;
  }

  @override
  Offset imageToGeo(Offset imagePoint) {
    final dx = imagePoint.dx - baseAnchor.imageX;
    final dy = imagePoint.dy - baseAnchor.imageY;

    // Поворачиваем вектор из пиксельной системы в систему магнитного севера
    final cos = math.cos(-northAngle);
    final sin = math.sin(-northAngle);
    final rotDx = dx * cos - dy * sin;
    final rotDy = dx * sin + dy * cos;

    // После поворота на -northAngle:
    // rotDx = компонента вдоль магнитного севера (north)
    // rotDy = компонента перпендикулярно (east)
    final northMeters = _metersForPixels(rotDx);
    final eastMeters = _metersForPixels(rotDy);

    final originLatRad = baseAnchor.latitude * math.pi / 180;
    final dLat = northMeters / AppConstants.earthRadiusMeters;
    final dLon = eastMeters / (AppConstants.earthRadiusMeters * math.cos(originLatRad));

    final lat = baseAnchor.latitude + dLat * 180 / math.pi;
    final lon = baseAnchor.longitude + dLon * 180 / math.pi;
    return Offset(lon, lat);
  }

  @override
  Offset geoToImage(Offset geoPoint) {
    final originLatRad = baseAnchor.latitude * math.pi / 180;
    final dLat = (geoPoint.dy - baseAnchor.latitude) * math.pi / 180;
    final dLon = (geoPoint.dx - baseAnchor.longitude) * math.pi / 180;

    final northMeters = dLat * AppConstants.earthRadiusMeters;
    final eastMeters = dLon * AppConstants.earthRadiusMeters * math.cos(originLatRad);

    // Из системы магнитного севера обратно в повёрнутую систему:
    // rotDx = компонента вдоль севера (north)
    // rotDy = компонента вдоль востока (east)
    final rotDx = _pixelsForMeters(northMeters);
    final rotDy = _pixelsForMeters(eastMeters);

    // Поворот из системы магнитного севера обратно в пиксельную систему
    final cos = math.cos(northAngle);
    final sin = math.sin(northAngle);
    final dx = rotDx * cos - rotDy * sin;
    final dy = rotDx * sin + rotDy * cos;

    return Offset(baseAnchor.imageX + dx, baseAnchor.imageY + dy);
  }

  @override
  int get usedAnchorCount => 1;

  @override
  double? get metersPerImagePixel {
    if (linePixels == 0) return null;
    return lineMeters / linePixels;
  }

  @override
  double? get rmseMeters => null;

  @override
  double? get selfPointErrorMeters => null;
}