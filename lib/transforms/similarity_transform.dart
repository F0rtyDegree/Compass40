import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../utils/app_constants.dart';

/// Общий интерфейс для всех типов привязки
abstract class MapTransformer {
  Offset imageToGeo(Offset imagePoint);
  Offset geoToImage(Offset geoPoint);
  double? get rmseMeters => null;
  int get usedAnchorCount => 0;
  double? get selfPointErrorMeters => null;
  double? get metersPerImagePixel => null;
}

/// Двухточечное подобие (перенос + поворот + равномерный масштаб)
class SimilarityTransform implements MapTransformer {
  final double originLat;
  final double originLon;
  final double referenceImageX;
  final double referenceImageY;
  final double scale; // метров на пиксель (локальных)
  final double angleRadians;
  final String latestId;
  final String referenceId;

  SimilarityTransform({
    required this.originLat,
    required this.originLon,
    required this.referenceImageX,
    required this.referenceImageY,
    required this.scale,
    required this.angleRadians,
    required this.latestId,
    required this.referenceId,
  });

  factory SimilarityTransform.fromPair(MapAnchor latest, MapAnchor reference) {
    final dx = latest.imageX - reference.imageX;
    final dy = latest.imageY - reference.imageY;
    final imgLen = math.sqrt(dx * dx + dy * dy);
    if (imgLen < 1e-9) throw ArgumentError('Image distance too small');

    final originLat = reference.latitude;
    final originLon = reference.longitude;

    final dLat = (latest.latitude - reference.latitude) * math.pi / 180;
    final dLon = (latest.longitude - reference.longitude) * math.pi / 180;
    final originLatRad = reference.latitude * math.pi / 180;
    final north = dLat * AppConstants.earthRadiusMeters;
    final east = dLon * AppConstants.earthRadiusMeters * math.cos(originLatRad);

    final geoVec = Offset(east, -north);
    final geoLen = geoVec.distance;
    if (geoLen < 1e-9) throw ArgumentError('Geo distance too small');

    final scale = geoLen / imgLen;
    final angle = math.atan2(geoVec.dy, geoVec.dx) - math.atan2(dy, dx);

    return SimilarityTransform(
      originLat: originLat,
      originLon: originLon,
      referenceImageX: reference.imageX,
      referenceImageY: reference.imageY,
      scale: scale,
      angleRadians: angle,
      latestId: latest.id,
      referenceId: reference.id,
    );
  }

  @override
  Offset imageToGeo(Offset imagePoint) {
    final dx = imagePoint.dx - referenceImageX;
    final dy = imagePoint.dy - referenceImageY;
    final scaledDx = dx * scale;
    final scaledDy = dy * scale;
    final cos = math.cos(angleRadians);
    final sin = math.sin(angleRadians);
    final east = scaledDx * cos - scaledDy * sin;
    final northNeg = scaledDx * sin + scaledDy * cos;
    final north = -northNeg;

    final originLatRad = originLat * math.pi / 180;
    final dLat = north / AppConstants.earthRadiusMeters;
    final dLon = east / (AppConstants.earthRadiusMeters * math.cos(originLatRad));
    final lat = originLat + dLat * 180 / math.pi;
    final lon = originLon + dLon * 180 / math.pi;
    return Offset(lon, lat);
  }

  @override
  int get usedAnchorCount => 2;

  @override
  double? get rmseMeters => null;

  @override
  double? get selfPointErrorMeters => null;

  @override
  double? get metersPerImagePixel => scale;

  @override
  Offset geoToImage(Offset geoPoint) {
    final lon = geoPoint.dx;
    final lat = geoPoint.dy;
    final originLatRad = originLat * math.pi / 180;
    final dLat = (lat - originLat) * math.pi / 180;
    final dLon = (lon - originLon) * math.pi / 180;
    final north = dLat * AppConstants.earthRadiusMeters;
    final east = dLon * AppConstants.earthRadiusMeters * math.cos(originLatRad);
    final geoX = east;
    final geoY = -north;

    final cos = math.cos(-angleRadians);
    final sin = math.sin(-angleRadians);
    final rotX = geoX * cos - geoY * sin;
    final rotY = geoX * sin + geoY * cos;

    final dx = rotX / scale;
    final dy = rotY / scale;
    return Offset(referenceImageX + dx, referenceImageY + dy);
  }

  Set<String>? get activeAnchorIds => {latestId, referenceId};
}