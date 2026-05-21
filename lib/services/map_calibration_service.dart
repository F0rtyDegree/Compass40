import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../models/map_working_pair.dart';
import '../utils/geo_utils.dart';
import 'affine_transform.dart';

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

/// Общий интерфейс для всех типов привязки
abstract class _MapTransformer {
  Offset imageToGeo(Offset imagePoint);
  Offset geoToImage(Offset geoPoint);
  double? get rmseMeters => null;
  int get usedAnchorCount => 0;
  double? get selfPointErrorMeters => null;
}

/// Двухточечное подобие (перенос + поворот + равномерный масштаб)
class SimilarityTransform implements _MapTransformer {
  final double originLat;
  final double originLon;
  final double referenceImageX;
  final double referenceImageY;
  final double scale; // метров на пиксель (локальных)
  final double angleRadians;

  SimilarityTransform({
    required this.originLat,
    required this.originLon,
    required this.referenceImageX,
    required this.referenceImageY,
    required this.scale,
    required this.angleRadians,
  });

  factory SimilarityTransform.fromPair(MapAnchor latest, MapAnchor reference) {
    final dx = latest.imageX - reference.imageX;
    final dy = latest.imageY - reference.imageY;
    final imgLen = math.sqrt(dx * dx + dy * dy);
    if (imgLen < 1e-9) throw ArgumentError('Image distance too small');

    final originLat = reference.latitude;
    final originLon = reference.longitude;

    // переводим latest в локальные метры относительно reference
    final dLat = (latest.latitude - reference.latitude) * math.pi / 180;
    final dLon = (latest.longitude - reference.longitude) * math.pi / 180;
    final originLatRad = reference.latitude * math.pi / 180;
    final north = dLat * 6371000.0;
    final east = dLon * 6371000.0 * math.cos(originLatRad);

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

    // переводим локальные метры (east, north) в широту/долготу
    final originLatRad = originLat * math.pi / 180;
    final dLat = north / 6371000.0;
    final dLon = east / (6371000.0 * math.cos(originLatRad));
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
  Offset geoToImage(Offset geoPoint) {
    final lon = geoPoint.dx;
    final lat = geoPoint.dy;
    final originLatRad = originLat * math.pi / 180;
    final dLat = (lat - originLat) * math.pi / 180;
    final dLon = (lon - originLon) * math.pi / 180;
    final north = dLat * 6371000.0;
    final east = dLon * 6371000.0 * math.cos(originLatRad);
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
}

/// Адаптер для аффинного преобразования (3+ точек)
class _AffineTransformerAdapter implements _MapTransformer {
  final AffineTransform _affine;
  final List<MapAnchor> _selectedPoints;
  final double _rmse;
  final double _selfError;

  _AffineTransformerAdapter._({
    required AffineTransform affine,
    required List<MapAnchor> selectedPoints,
    required double rmse,
    required double selfError,
  })  : _affine = affine,
        _selectedPoints = selectedPoints,
        _rmse = rmse,
        _selfError = selfError;

  factory _AffineTransformerAdapter.fromAnchors(List<MapAnchor> anchors) {
    final selected = _selectBestPoints(anchors);
    final affine = AffineTransform.fromPoints(
      selected.map((a) => Offset(a.imageX, a.imageY)).toList(),
      selected.map((a) => Offset(a.longitude, a.latitude)).toList(),
      weights: _buildWeights(selected.length),
    );
    final rmse = _computeRmse(selected, affine);
    final selfError = _computeSelfError(selected, affine);
    return _AffineTransformerAdapter._(
      affine: affine,
      selectedPoints: selected,
      rmse: rmse,
      selfError: selfError,
    );
  }

  static List<double> _buildWeights(int n) {
    final w = List.filled(n, 1.0);
    if (n > 0) w[0] = 1000.0;
    return w;
  }

  static double _computeRmse(List<MapAnchor> points, AffineTransform affine) {
    double sumSq = 0;
    for (final a in points) {
      final pred = affine.transform(Offset(a.imageX, a.imageY));
      final d = _haversineDistance(
          a.latitude, a.longitude, pred.dy, pred.dx);
      sumSq += d * d;
    }
    return math.sqrt(sumSq / points.length);
  }

  static double _computeSelfError(List<MapAnchor> points, AffineTransform affine) {
    if (points.isEmpty) return 0;
    final latest = points.first;
    final pred = affine.transform(Offset(latest.imageX, latest.imageY));
    return _haversineDistance(
        latest.latitude, latest.longitude, pred.dy, pred.dx);
  }

  static double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) * math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static List<MapAnchor> _selectBestPoints(List<MapAnchor> anchors) {
    if (anchors.length <= 6) return anchors;
    final latest = anchors.last;
    final candidates = anchors.sublist(0, anchors.length - 1);
    candidates.sort((a, b) {
      final da = _pixelDistSq(latest, a);
      final db = _pixelDistSq(latest, b);
      return db.compareTo(da);
    });
    final selected = <MapAnchor>[latest];
    const minSeparationPx = 50.0;
    for (final candidate in candidates) {
      if (selected.length >= 6) break;
      bool farEnough = true;
      for (final s in selected) {
        if (_pixelDistSq(s, candidate) < minSeparationPx * minSeparationPx) {
          farEnough = false;
          break;
        }
      }
      if (farEnough) selected.add(candidate);
    }
    return selected;
  }

  static double _pixelDistSq(MapAnchor a, MapAnchor b) {
    final dx = a.imageX - b.imageX;
    final dy = a.imageY - b.imageY;
    return dx * dx + dy * dy;
  }

  @override
  Offset imageToGeo(Offset imagePoint) => _affine.transform(imagePoint);

  @override
  Offset geoToImage(Offset geoPoint) => _affine.inverseTransform(geoPoint);

  @override
  double? get rmseMeters => _rmse;

  @override
  int get usedAnchorCount => _selectedPoints.length;

  @override
  double? get selfPointErrorMeters => _selfError;
}

class MapCalibrationService {
  static const double _earthRadius = 6371000.0;

  // ---------------------------------------------------------
  // Внутреннее состояние (для автоматического режима)
  // ---------------------------------------------------------
  List<MapAnchor> _anchors = [];
  _MapTransformer? _currentTransform;

  int get usedAnchorCount {
    final t = _currentTransform;
    if (t != null) return t.usedAnchorCount;
    return 0;
  }

  int get totalAnchorCount => _anchors.length;

  double? get rmseMeters => _currentTransform?.rmseMeters;

  double? get selfPointErrorMeters => _currentTransform?.selfPointErrorMeters;

  /// Вызывается извне при любом изменении списка якорей
  void updateAnchors(List<MapAnchor> anchors) {
    _anchors = anchors;
    _buildTransformFromAnchors();
  }

  void _buildTransformFromAnchors() {
    if (_anchors.length >= 3) {
      _currentTransform = _AffineTransformerAdapter.fromAnchors(_anchors);
    } else if (_anchors.length == 2) {
      final pair = selectWorkingPair(_anchors);
      if (pair != null) {
        _currentTransform =
            SimilarityTransform.fromPair(pair.latest, pair.reference);
      } else {
        _currentTransform = null;
      }
    } else {
      _currentTransform = null;
    }
  }

  /// Преобразование изображение → гео (использует текущее состояние)
  GeoPoint? imagePointToGeoFromCurrent(Offset imagePoint) {
    final t = _currentTransform;
    if (t == null) return null;
    final geo = t.imageToGeo(imagePoint);
    return GeoPoint(latitude: geo.dy, longitude: geo.dx);
  }

  /// Преобразование гео → изображение (использует текущее состояние)
  Offset? geoToImagePointFromCurrent(double latitude, double longitude) {
    final t = _currentTransform;
    if (t == null) return null;
    return t.geoToImage(Offset(longitude, latitude));
  }

  // ---------------------------------------------------------
  // Старые методы (работа с явной парой, обратная совместимость)
  // ---------------------------------------------------------

  MapWorkingPair? selectWorkingPair(
    List<MapAnchor> anchors, {
    double minDistanceMeters = 50.0,
  }) {
    if (anchors.length < 2) return null;

    final latest = anchors.last; // последняя добавленная точка
    MapAnchor? farthest;
    double maxDist = -1;
    for (int i = 0; i < anchors.length - 1; i++) {
      final candidate = anchors[i];
      final dist = distanceBetweenAnchorsMeters(latest, candidate);
      if (dist >= minDistanceMeters && dist > maxDist) {
        maxDist = dist;
        farthest = candidate;
      }
    }

    if (farthest == null) return null;
    return MapWorkingPair(latest: latest, reference: farthest);
  }

  double? getMapRotation(MapWorkingPair pair) {
    final transform = _buildTransform(pair);
    return transform?.angleRadians;
  }

  double distanceBetweenAnchorsMeters(MapAnchor a, MapAnchor b) {
    return calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);
  }

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

  /// Построение двухточечного преобразования по рабочей паре
  SimilarityTransform? _buildTransform(MapWorkingPair pair) {
    try {
      return SimilarityTransform.fromPair(pair.latest, pair.reference);
    } catch (_) {
      return null;
    }
  }

  GeoPoint? imagePointToGeo({
    required Offset imagePoint,
    required MapWorkingPair pair,
  }) {
    final t = _buildTransform(pair);
    if (t == null) return null;

    // Используем поля старого класса напрямую (referenceImageX/Y и т.д.)
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
    final dist = calculateDistance(fromLat, fromLon, toLat, toLon);

    final phi1 = fromLat * math.pi / 180;
    final phi2 = toLat * math.pi / 180;
    final dLambda = (toLon - fromLon) * math.pi / 180;

    final y = math.sin(dLambda) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);

    final trueBearing = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    final magneticBearing = (trueBearing - magneticDeclination + 360) % 360;

    return BearingAndDistance(
      distanceMeters: dist,
      trueBearing: trueBearing,
      magneticBearing: magneticBearing,
    );
  }
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
