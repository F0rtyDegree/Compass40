import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../models/map_working_pair.dart';

// Простая модель GPS-точки
class GeoPoint {
  final double latitude;
  final double longitude;

  const GeoPoint({required this.latitude, required this.longitude});
}

// Локальная метрическая точка (East / North в метрах)
class LocalPoint {
  final double east;
  final double north;

  const LocalPoint({required this.east, required this.north});
}

class MapCalibrationService {
  static const double _earthRadius = 6371000.0;

  // ---------------------------------------------------------
  // Выбор рабочей пары
  // ---------------------------------------------------------

  MapWorkingPair? selectWorkingPair(
    List<MapAnchor> anchors, {
    double minDistanceMeters = 50.0,
  }) {
    if (anchors.length < 2) return null;

    final sorted = List<MapAnchor>.from(anchors)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final latest = sorted.last;

    for (int i = sorted.length - 2; i >= 0; i--) {
      final candidate = sorted[i];
      final dist = distanceBetweenAnchorsMeters(latest, candidate);
      if (dist >= minDistanceMeters) {
        return MapWorkingPair(latest: latest, reference: candidate);
      }
    }

    return null;
  }

  double? getMapRotation(MapWorkingPair pair) {
    final transform = _buildTransform(pair);
    return transform?.angleRadians;
  }

  // ---------------------------------------------------------
  // Расстояние между точками привязки
  // ---------------------------------------------------------

  double distanceBetweenAnchorsMeters(MapAnchor a, MapAnchor b) {
    return _haversineDistance(a.latitude, a.longitude, b.latitude, b.longitude);
  }

  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final dPhi = (lat2 - lat1) * math.pi / 180;
    final dLambda = (lon2 - lon1) * math.pi / 180;

    final a =
        math.sin(dPhi / 2) * math.sin(dPhi / 2) +
        math.cos(phi1) *
            math.cos(phi2) *
            math.sin(dLambda / 2) *
            math.sin(dLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return _earthRadius * c;
  }

  // ---------------------------------------------------------
  // Перевод GPS → LocalPoint (метры East/North)
  // ---------------------------------------------------------

  LocalPoint geoToLocal({
    required double latitude,
    required double longitude,
    required double originLat,
    required double originLon,
  }) {
    final dLat = (latitude - originLat) * math.pi / 180;
    final dLon = (longitude - originLon) * math.pi / 180;
    final originLatRad = originLat * math.pi / 180;

    final north = dLat * _earthRadius;
    final east = dLon * _earthRadius * math.cos(originLatRad);

    return LocalPoint(east: east, north: north);
  }

  GeoPoint localToGeo({
    required LocalPoint local,
    required double originLat,
    required double originLon,
  }) {
    final originLatRad = originLat * math.pi / 180;

    final dLat = local.north / _earthRadius;
    final dLon = local.east / (_earthRadius * math.cos(originLatRad));

    return GeoPoint(
      latitude: originLat + dLat * 180 / math.pi,
      longitude: originLon + dLon * 180 / math.pi,
    );
  }

  // ---------------------------------------------------------
  // Построение локального 2-точечного преобразования
  // ---------------------------------------------------------

  _SimilarityTransform? _buildTransform(MapWorkingPair pair) {
    final imgVec = Offset(
      pair.latest.imageX - pair.reference.imageX,
      pair.latest.imageY - pair.reference.imageY,
    );

    final imgLen = imgVec.distance;
    if (imgLen < 1e-9) return null;

    final originLat = pair.reference.latitude;
    final originLon = pair.reference.longitude;

    final latestLocal = geoToLocal(
      latitude: pair.latest.latitude,
      longitude: pair.latest.longitude,
      originLat: originLat,
      originLon: originLon,
    );

    final geoVec = Offset(latestLocal.east, -latestLocal.north);
    final geoLen = geoVec.distance;
    if (geoLen < 1e-9) return null;

    final scale = geoLen / imgLen;

    final angle =
        math.atan2(geoVec.dy, geoVec.dx) - math.atan2(imgVec.dy, imgVec.dx);

    return _SimilarityTransform(
      originLat: originLat,
      originLon: originLon,
      referenceImageX: pair.reference.imageX,
      referenceImageY: pair.reference.imageY,
      scale: scale,
      angleRadians: angle,
    );
  }

  // ---------------------------------------------------------
  // image ↔ GPS
  // ---------------------------------------------------------

  GeoPoint? imagePointToGeo({
    required Offset imagePoint,
    required MapWorkingPair pair,
  }) {
    final t = _buildTransform(pair);
    if (t == null) return null;

    final dx = imagePoint.dx - t.referenceImageX;
    final dy = imagePoint.dy - t.referenceImageY;

    final scaledDx = dx * t.scale;
    final scaledDy = dy * t.scale;

    final cos = math.cos(t.angleRadians);
    final sin = math.sin(t.angleRadians);
    final localEast = scaledDx * cos - scaledDy * sin;
    final localNorthNeg = scaledDx * sin + scaledDy * cos;

    final localNorth = -localNorthNeg;

    return localToGeo(
      local: LocalPoint(east: localEast, north: localNorth),
      originLat: t.originLat,
      originLon: t.originLon,
    );
  }

  Offset? geoToImagePoint({
    required double latitude,
    required double longitude,
    required MapWorkingPair pair,
  }) {
    final t = _buildTransform(pair);
    if (t == null) return null;

    final local = geoToLocal(
      latitude: latitude,
      longitude: longitude,
      originLat: t.originLat,
      originLon: t.originLon,
    );

    final geoX = local.east;
    final geoY = -local.north;

    final cos = math.cos(-t.angleRadians);
    final sin = math.sin(-t.angleRadians);
    final rotX = geoX * cos - geoY * sin;
    final rotY = geoX * sin + geoY * cos;

    final dx = rotX / t.scale;
    final dy = rotY / t.scale;

    return Offset(t.referenceImageX + dx, t.referenceImageY + dy);
  }

  // ---------------------------------------------------------
  // Вспомогательные проверки
  // ---------------------------------------------------------

  bool canBuildTransform(List<MapAnchor> anchors) {
    return selectWorkingPair(anchors) != null;
  }

  BearingAndDistance bearingAndDistance({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required double magneticDeclination,
  }) {
    final dist = _haversineDistance(fromLat, fromLon, toLat, toLon);

    final phi1 = fromLat * math.pi / 180;
    final phi2 = toLat * math.pi / 180;
    final dLambda = (toLon - fromLon) * math.pi / 180;

    final y = math.sin(dLambda) * math.cos(phi2);
    final x = 
        math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);

    final trueBearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    // Convention: East declination is positive. True North = Magnetic North + Declination.
    final magneticBearing = (trueBearing - magneticDeclination + 360) % 360;

    return BearingAndDistance(
      distanceMeters: dist,
      trueBearing: trueBearing,
      magneticBearing: magneticBearing,
    );
  }
}

class _SimilarityTransform {
  final double originLat;
  final double originLon;
  final double referenceImageX;
  final double referenceImageY;
  final double scale;
  final double angleRadians;

  const _SimilarityTransform({
    required this.originLat,
    required this.originLon,
    required this.referenceImageX,
    required this.referenceImageY,
    required this.scale,
    required this.angleRadians,
  });
}

class BearingAndDistance {
  final double distanceMeters;
  final double trueBearing;
  final double magneticBearing;

  const BearingAndDistance({
    required this.distanceMeters,
    required this.trueBearing,
    required this.magneticBearing,
  });
}
