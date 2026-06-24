import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import 'similarity_transform.dart';

class PhotoSeverTransform implements MapTransformer {
  final MapAnchor baseAnchor;
  final double metersPerPixel;
  final double northRotationRad;
  final double magneticDeclinationRad; // ✅ ДОБАВЛЕНО

  PhotoSeverTransform({
    required this.baseAnchor,
    required this.metersPerPixel,
    required this.northRotationRad,
    this.magneticDeclinationRad = 0.0, // ✅ По умолчанию 0 для обратной совместимости
  });

  @override
  Offset imageToGeo(Offset imagePoint) {
    final dx = imagePoint.dx - baseAnchor.imageX;
    final dy = imagePoint.dy - baseAnchor.imageY;

    // Поворачиваем вектор из экранных координат в систему Магнитного Севера
    final cos = math.cos(northRotationRad);
    final sin = math.sin(northRotationRad);
    final rotDx = dx * cos - dy * sin;
    final rotDy = dx * sin + dy * cos;

    final eastMeters = rotDx * metersPerPixel;
    final northMeters = -rotDy * metersPerPixel;

    // ✅ КОМПЕНСАЦИЯ: Поворачиваем из системы Магнитного Севера в Истинный
    final cosD = math.cos(magneticDeclinationRad);
    final sinD = math.sin(magneticDeclinationRad);
    final trueEast = eastMeters * cosD - northMeters * sinD;
    final trueNorth = eastMeters * sinD + northMeters * cosD;

    final originLatRad = baseAnchor.latitude * math.pi / 180;
    final dLat = trueNorth / 6371000.0;
    final dLon = trueEast / (6371000.0 * math.cos(originLatRad));

    final lat = baseAnchor.latitude + dLat * 180 / math.pi;
    final lon = baseAnchor.longitude + dLon * 180 / math.pi;

    return Offset(lon, lat);
  }

  @override
  Offset geoToImage(Offset geoPoint) {
    final originLatRad = baseAnchor.latitude * math.pi / 180;
    final dLat = (geoPoint.dy - baseAnchor.latitude) * math.pi / 180;
    final dLon = (geoPoint.dx - baseAnchor.longitude) * math.pi / 180;

    final trueNorth = dLat * 6371000.0;
    final trueEast = dLon * 6371000.0 * math.cos(originLatRad);

    // ✅ ОБРАТНАЯ КОМПЕНСАЦИЯ: Из Истинного Севера в Магнитный
    final cosD = math.cos(-magneticDeclinationRad);
    final sinD = math.sin(-magneticDeclinationRad);
    final eastMeters = trueEast * cosD - trueNorth * sinD;
    final northMeters = trueEast * sinD + trueNorth * cosD;

    final rotDx = eastMeters / metersPerPixel;
    final rotDy = -northMeters / metersPerPixel;

    final cos = math.cos(-northRotationRad);
    final sin = math.sin(-northRotationRad);
    final dx = rotDx * cos - rotDy * sin;
    final dy = rotDx * sin + rotDy * cos;

    return Offset(baseAnchor.imageX + dx, baseAnchor.imageY + dy);
  }

  @override
  int get usedAnchorCount => 1;

  @override
  double? get metersPerImagePixel => metersPerPixel;
  
  @override
  double? get rmseMeters => null;
  
  @override
  double? get selfPointErrorMeters => null;
}