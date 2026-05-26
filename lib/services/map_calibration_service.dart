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
  double? get metersPerImagePixel => null;
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
  double? get metersPerImagePixel => scale;

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
  }) : _affine = affine,
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
    if (n > 0) w[0] = 10.0;
    return w;
  }

  static double _computeRmse(List<MapAnchor> points, AffineTransform affine) {
    double sumSq = 0;
    for (final a in points) {
      final pred = affine.transform(Offset(a.imageX, a.imageY));
      final d = _haversineDistance(a.latitude, a.longitude, pred.dy, pred.dx);
      sumSq += d * d;
    }
    return math.sqrt(sumSq / points.length);
  }

  /// Алгоритм выбора до 6 опорных точек с максимальным покрытием территории.
  /// Правила:
  /// 1. Текущая точка (latest) всегда участвует, позже с большим весом.
  /// 2. Точки привязки не могут быть ближе 50 метров друг к другу.
  /// 3. Двухточечная схема (latest + farthest), пока все точки коллинеарны.
  /// 4. При появлении неколлинеарной точки – поиск треугольника (latest, farthest, X)
  ///    с максимальной площадью.
  /// 5. Для 4-х точек: к фиксированному треугольнику добавляется новый latest.
  /// 6. Для 5-и точек: выбираются 4 точки (кроме latest) с максимальной площадью
  ///    выпуклой оболочки, и добавляется latest.
  /// 7. Для 6-и точек: выбираются 5 точек (кроме latest) с максимальной площадью
  ///    выпуклой оболочки, и добавляется latest.
  static List<MapAnchor> _selectBestPoints(List<MapAnchor> anchors) {
    final latest = anchors.last;
    if (anchors.length == 1) return <MapAnchor>[latest];

    // ---------- вспомогательные функции ----------
    double distMeters(MapAnchor a, MapAnchor b) {
      return _haversineDistance(
        a.latitude,
        a.longitude,
        b.latitude,
        b.longitude,
      );
    }

    double triangleAreaM2(MapAnchor a, MapAnchor b, MapAnchor c) {
      final ab = distMeters(a, b);
      final bc = distMeters(b, c);
      final ca = distMeters(c, a);
      final s = (ab + bc + ca) / 2;
      if (s - ab <= 0 || s - bc <= 0 || s - ca <= 0) return 0;
      return math.sqrt(s * (s - ab) * (s - bc) * (s - ca));
    }

    double convexHullAreaM2(List<MapAnchor> points) {
      if (points.length < 3) return 0;
      double sumLat = 0, sumLon = 0;
      for (final p in points) {
        sumLat += p.latitude;
        sumLon += p.longitude;
      }
      final centerLat = sumLat / points.length;
      final centerLon = sumLon / points.length;
      const metersPerDegLat = 111320.0;
      final metersPerDegLon = 111320.0 * math.cos(centerLat * math.pi / 180);

      final local = points.map((p) {
        final dx = (p.longitude - centerLon) * metersPerDegLon;
        final dy = (p.latitude - centerLat) * metersPerDegLat;
        return Offset(dx, dy);
      }).toList();

      int start = 0;
      for (int i = 1; i < local.length; i++) {
        if (local[i].dy < local[start].dy ||
            (local[i].dy == local[start].dy && local[i].dx < local[start].dx)) {
          start = i;
        }
      }
      final pivot = local[start];
      final sorted = <Offset>[];
      for (int i = 0; i < local.length; i++) {
        if (i == start) continue;
        sorted.add(local[i]);
      }
      sorted.sort((a, b) {
        final cross =
            (a.dx - pivot.dx) * (b.dy - pivot.dy) -
            (a.dy - pivot.dy) * (b.dx - pivot.dx);
        if (cross != 0) return cross < 0 ? 1 : -1;
        final distA =
            (a.dx - pivot.dx) * (a.dx - pivot.dx) +
            (a.dy - pivot.dy) * (a.dy - pivot.dy);
        final distB =
            (b.dx - pivot.dx) * (b.dx - pivot.dx) +
            (b.dy - pivot.dy) * (b.dy - pivot.dy);
        return distA.compareTo(distB);
      });

      final hull = <Offset>[pivot];
      for (final p in sorted) {
        while (hull.length >= 2) {
          final a = hull[hull.length - 2];
          final b = hull.last;
          final cross =
              (b.dx - a.dx) * (p.dy - a.dy) - (b.dy - a.dy) * (p.dx - a.dx);
          if (cross <= 0) {
            hull.removeLast();
          } else {
            break;
          }
        }
        hull.add(p);
      }

      double area = 0;
      for (int i = 0; i < hull.length; i++) {
        final j = (i + 1) % hull.length;
        area += hull[i].dx * hull[j].dy;
        area -= hull[j].dx * hull[i].dy;
      }
      return area.abs() / 2;
    }

    // ---------- основной алгоритм ----------
    final others = anchors.sublist(0, anchors.length - 1);

    MapAnchor? farthest;
    double maxDist = -1;
    for (final a in others) {
      final d = distMeters(latest, a);
      if (d >= 50 && d > maxDist) {
        maxDist = d;
        farthest = a;
      }
    }
    if (farthest == null) return <MapAnchor>[latest];

    final base = <MapAnchor>[latest, farthest];
    if (others.length == 1) return base;

    bool hasNonCollinear = false;
    for (final x in others) {
      if (x == farthest) continue;
      if (triangleAreaM2(latest, farthest, x) > 1e-6) {
        hasNonCollinear = true;
        break;
      }
    }
    if (!hasNonCollinear) return base;

    // Переменная для результата
    List<MapAnchor> result;

    if (anchors.length == 3) {
      MapAnchor? bestThird;
      double bestArea = -1;
      for (final x in others) {
        if (x == farthest) continue;
        if (distMeters(latest, x) < 50 || distMeters(farthest, x) < 50) {
          continue;
        }

        final area = triangleAreaM2(latest, farthest, x);
        if (area > bestArea) {
          bestArea = area;
          bestThird = x;
        }
      }
      result = bestThird != null
          ? <MapAnchor>[latest, farthest, bestThird]
          : base;
    } else if (anchors.length == 4) {
      final latestNow = anchors.last;
      final prevTriangle = anchors.sublist(0, anchors.length - 1);
      bool valid = true;
      for (int i = 0; i < prevTriangle.length && valid; i++) {
        for (int j = i + 1; j < prevTriangle.length; j++) {
          if (distMeters(prevTriangle[i], prevTriangle[j]) < 50) valid = false;
        }
      }
      if (valid &&
          triangleAreaM2(prevTriangle[0], prevTriangle[1], prevTriangle[2]) >
              1e-6) {
        result = [...prevTriangle, latestNow];
      } else {
        result = <MapAnchor>[latestNow, farthest];
      }
    } else {
      // anchors.length >= 5
      final n = anchors.length >= 6 ? 5 : 4;
      final latestNow = anchors.last;
      final pool = anchors.sublist(0, anchors.length - 1);
      double bestHullArea = -1;
      List<MapAnchor>? bestHullSet;

      void findBestCombination(int start, List<MapAnchor> current) {
        if (current.length == n) {
          for (int i = 0; i < current.length; i++) {
            for (int j = i + 1; j < current.length; j++) {
              if (distMeters(current[i], current[j]) < 50) return;
            }
          }
          final area = convexHullAreaM2(current);
          if (area > bestHullArea) {
            bestHullArea = area;
            bestHullSet = List.from(current);
          }
          return;
        }
        for (int i = start; i <= pool.length - (n - current.length); i++) {
          current.add(pool[i]);
          findBestCombination(i + 1, current);
          current.removeLast();
        }
      }

      findBestCombination(0, []);
      if (bestHullSet != null && bestHullArea > 0) {
        if (!bestHullSet!.contains(latestNow)) {
          bestHullSet!.add(latestNow);
        }
        result = bestHullSet!;
      } else {
        result = <MapAnchor>[latestNow, farthest];
      }
    }

    // Гарантируем, что latest на первом месте (для _computeSelfError)
    final idx = result.indexOf(latest);
    if (idx > 0) {
      final moved = result.removeAt(idx);
      result.insert(0, moved);
    }
    return result;
  }

  static double _computeSelfError(
    List<MapAnchor> points,
    AffineTransform affine,
  ) {
    if (points.isEmpty) return 0;
    final latest = points.first;
    final pred = affine.transform(Offset(latest.imageX, latest.imageY));
    return _haversineDistance(
      latest.latitude,
      latest.longitude,
      pred.dy,
      pred.dx,
    );
  }

  static double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const R = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  double? get metersPerImagePixel {
    if (_selectedPoints.isEmpty) return null;
    final dx = _affine.m[0]; // dLon/dx
    final dy = _affine.m[3]; // dLat/dx
    final distDeg = math.sqrt(dx * dx + dy * dy);
    return distDeg * 111320;
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

  double? get metersPerImagePixel => _currentTransform?.metersPerImagePixel;

  /// ID якорей, используемых в текущем преобразовании
  Set<String>? get activeAnchorIds {
    final t = _currentTransform;
    if (t is _AffineTransformerAdapter) {
      return t._selectedPoints.map((a) => a.id).toSet();
    }
    if (t is SimilarityTransform) {
      return null; // для двух точек не выделяем
    }
    return null;
  }

  /// Возвращает строку с номерами (начиная с 1) активных якорей в _anchors,
  /// разделёнными пробелами. Например: "9 1 3".
  String? get activeAnchorIndices {
    final t = _currentTransform;
    if (t == null) return null;

    Set<String>? ids;
    if (t is _AffineTransformerAdapter) {
      ids = t._selectedPoints.map((a) => a.id).toSet();
    } else if (t is SimilarityTransform) {
      // для двухточечной схемы перевычисляем пару
      final pair = selectWorkingPair(_anchors);
      if (pair != null) {
        ids = {pair.latest.id, pair.reference.id};
      }
    }
    if (ids == null || ids.isEmpty) return null;

    final indices = <int>[];
    for (int i = 0; i < _anchors.length; i++) {
      if (ids.contains(_anchors[i].id)) {
        indices.add(i + 1); // нумерация с 1
      }
    }
    indices.sort();
    return indices.join(' ');
  }

  void updateAnchors(List<MapAnchor> anchors) {
    _anchors = anchors;
    _buildTransformFromAnchors();
  }

  void _buildTransformFromAnchors() {
    if (_anchors.length >= 3) {
      _MapTransformer? transform;
      try {
        final adapter = _AffineTransformerAdapter.fromAnchors(_anchors);
        transform = adapter;
      } catch (_) {
        transform = null;
      }
      if (transform != null && transform.usedAnchorCount >= 3) {
        _currentTransform = transform;
      } else {
        // Не удалось набрать 3 неколлинеарные точки – используем двухточечную схему
        final pair = selectWorkingPair(_anchors);
        _currentTransform = pair != null
            ? SimilarityTransform.fromPair(pair.latest, pair.reference)
            : null;
      }
    } else if (_anchors.length == 2) {
      final pair = selectWorkingPair(_anchors);
      _currentTransform = pair != null
          ? SimilarityTransform.fromPair(pair.latest, pair.reference)
          : null;
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
    final x =
        math.cos(phi1) * math.sin(phi2) -
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
