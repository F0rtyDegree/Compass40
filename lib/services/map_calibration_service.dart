// ignore_for_file: avoid_print
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../models/map_working_pair.dart';
import '../utils/geo_utils.dart';
import 'affine_transform.dart';

enum CalibrationMode { affine, pairFarthest, pairNearest }

class GeoPoint {
  final double latitude;
  final double longitude;
  const GeoPoint({required this.latitude, required this.longitude});
}

class LocalPoint {
  final double east;
  final double north;
  const LocalPoint({required this.east, required this.north});
}

abstract class _MapTransformer {
  Offset imageToGeo(Offset imagePoint);
  Offset geoToImage(Offset geoPoint);
  double? get rmseMeters => null;
  int get usedAnchorCount => 0;
  double? get selfPointErrorMeters => null;
  double? get metersPerImagePixel => null;
}

class SimilarityTransform implements _MapTransformer {
  final double originLat;
  final double originLon;
  final double referenceImageX;
  final double referenceImageY;
  final double scale;
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

  Set<String>? get activeAnchorIds => {latestId, referenceId};
}

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

  factory _AffineTransformerAdapter.fromAnchorsThreePoints(
    List<MapAnchor> anchors,
  ) {
    final selected = _selectBestPoints(anchors);
    if (selected.length < 3) {
      throw ArgumentError('Could not find valid triangle');
    }
    final three = selected.take(3).toList();
    final affine = AffineTransform.fromPoints(
      three.map((a) => Offset(a.imageX, a.imageY)).toList(),
      three.map((a) => Offset(a.longitude, a.latitude)).toList(),
      weights: _buildWeights(three.length),
    );
    final rmse = _computeRmse(three, affine);
    final selfError = _computeSelfError(three, affine);
    return _AffineTransformerAdapter._(
      affine: affine,
      selectedPoints: three,
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

  static List<MapAnchor> _selectBestPoints(List<MapAnchor> anchors) {
  final latest = anchors.last;
  if (anchors.length == 1) return <MapAnchor>[latest];

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
  if (others.length == 1) return <MapAnchor>[latest, farthest];

  // Ищем лучшую третью точку
  MapAnchor? bestThird;
  double bestArea = -1;
  for (final x in others) {
    if (x == farthest) continue;
    if (distMeters(latest, x) < 50 || distMeters(farthest, x) < 50) {
      continue;
    }

    final a = distMeters(farthest, x);
    final b = distMeters(latest, x);
    final c = distMeters(latest, farthest);
    if (a < 1 || b < 1 || c < 1) continue;

    final cosAngle = (b * b + c * c - a * a) / (2 * b * c);
    final angle = math.acos(cosAngle.clamp(-1.0, 1.0)) * 180 / math.pi;

    if (angle < 15 || angle > 165) continue;

    final area = triangleAreaM2(latest, farthest, x);
    if (area > bestArea) {
      bestArea = area;
      bestThird = x;
    }
  }
  
  if (bestArea < 1.0 || bestThird == null) {
    return <MapAnchor>[];
  }
  
  return <MapAnchor>[latest, farthest, bestThird];
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
    final p = _selectedPoints.first;
    final a = _affine.m[0];
    final d = _affine.m[3];
    final latRad = p.latitude * math.pi / 180;
    final metersPerDegLon = 111320.0 * math.cos(latRad);
    final metersPerDegLat = 111320.0;
    final dxMeters = a * metersPerDegLon;
    final dyMeters = d * metersPerDegLat;
    return math.sqrt(dxMeters * dxMeters + dyMeters * dyMeters);
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

  List<MapAnchor> _anchors = [];
  _MapTransformer? _currentTransform;
  CalibrationMode _mode = CalibrationMode.affine;
  final Set<String> _pinnedAnchorIds = {};
  bool _manualMode = false; // true, если пользователь хоть раз коснулся якоря

  int get usedAnchorCount {
    final t = _currentTransform;
    if (t != null) return t.usedAnchorCount;
    return 0;
  }

  int get totalAnchorCount => _anchors.length;

  double? get rmseMeters => _currentTransform?.rmseMeters;
  double? get selfPointErrorMeters => _currentTransform?.selfPointErrorMeters;
  double? get metersPerImagePixel => _currentTransform?.metersPerImagePixel;

  Set<String>? get activeAnchorIds {
    // В ручном режиме показываем все выбранные точки, даже если привязка не построена
    if (_manualMode) {
      return _pinnedAnchorIds.toSet();
    }
    final t = _currentTransform;
    if (t is SimilarityTransform) {
      return t.activeAnchorIds;
    }
    if (t is _AffineTransformerAdapter) {
      return t._selectedPoints.map((a) => a.id).toSet();
    }
    return null;
  }

  String? get activeAnchorIndices {
    final t = _currentTransform;
    if (t == null) return null;

    Set<String>? ids;
    if (t is _AffineTransformerAdapter) {
      ids = t._selectedPoints.map((a) => a.id).toSet();
    } else if (t is SimilarityTransform) {
      final pair = selectWorkingPair(_anchors);
      if (pair != null) {
        ids = {pair.latest.id, pair.reference.id};
      }
    }
    if (ids == null || ids.isEmpty) return null;

    final indices = <int>[];
    for (int i = 0; i < _anchors.length; i++) {
      if (ids.contains(_anchors[i].id)) {
        indices.add(i + 1);
      }
    }
    indices.sort();
    return indices.join(' ');
  }

  List<MapAnchor> get pinnedAnchors =>
      _anchors.where((a) => _pinnedAnchorIds.contains(a.id)).toList();

  String get calibrationModeLetter {
    if (_manualMode) {
      return '${_pinnedAnchorIds.length}';
    }
    switch (_mode) {
      case CalibrationMode.affine:
        return 'A';
      case CalibrationMode.pairFarthest:
        return 'F';
      case CalibrationMode.pairNearest:
        return 'N';
    }
  }

  void setCalibrationMode(CalibrationMode mode) {
    _manualMode = false;
    _mode = mode;
    _buildTransformFromAnchors();
  }

  void enableManualMode() {
    _manualMode = true;
    _buildTransformFromAnchors();
  }

  CalibrationMode get currentMode => _mode;
  bool get isManualMode => _manualMode;

  void restoreState({
    required CalibrationMode mode,
    required bool manual,
    required List<String> pinnedIds,
  }) {
    _mode = mode;
    _manualMode = manual;
    _pinnedAnchorIds.clear();
    _pinnedAnchorIds.addAll(pinnedIds);
    _buildTransformFromAnchors();
  }

  List<String> get pinnedAnchorIdsList => _pinnedAnchorIds.toList();

  void setPinnedAnchorIds(List<String> ids) {
    _pinnedAnchorIds.clear();
    _pinnedAnchorIds.addAll(ids);
    _manualMode = ids.isNotEmpty;
    _buildTransformFromAnchors();
  }

  void toggleAnchorPinned(String anchorId) {
    // Если не в ручном режиме, захватываем текущий автоматический набор
    if (!_manualMode) {
      _captureCurrentAutomaticSet();
    }

    // Переключаем точку в наборе
    if (_pinnedAnchorIds.contains(anchorId)) {
      _pinnedAnchorIds.remove(anchorId);
      _manualMode = _pinnedAnchorIds.isNotEmpty;
      _buildTransformFromAnchors();
    } else {
      _pinnedAnchorIds.add(anchorId);
      _manualMode = true;
      // НЕ вызываем _buildTransformFromAnchors() здесь — подождём проверки коллинеарности
      // Запускаем таймер для проверки и последующего перестроения
      Future.delayed(const Duration(seconds: 1), () {
        _checkAndApplyManualSet(anchorId);
      });
    }
  }

  void _checkAndApplyManualSet(String addedAnchorId) {
    // Если точка уже была удалена пользователем до срабатывания таймера — ничего не делаем
    if (!_pinnedAnchorIds.contains(addedAnchorId)) {
      _buildTransformFromAnchors();
      return;
    }

    // Проверяем коллинеарность всего ручного набора
    final pinned = pinnedAnchors;
    if (pinned.length >= 3 && _isCollinear(pinned)) {
      // Набор коллинеарен — удаляем последнюю добавленную точку
      _pinnedAnchorIds.remove(addedAnchorId);
      _manualMode = _pinnedAnchorIds.isNotEmpty;
    }
    // Применяем результат
    _buildTransformFromAnchors();
  }

  bool _isCollinear(List<MapAnchor> points) {
    if (points.length < 3) return false;
    // Находим минимальный угол среди всех троек
    double minAngle = double.infinity;
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        for (int k = j + 1; k < points.length; k++) {
          double angle = _triangleMinAngle(points[i], points[j], points[k]);
          if (angle < minAngle) minAngle = angle;
        }
      }
    }
    return minAngle < 15.0; // порог 15°
  }

  double _triangleMinAngle(MapAnchor a, MapAnchor b, MapAnchor c) {
    double distAB = _distanceBetweenAnchorsMeters(a, b);
    double distBC = _distanceBetweenAnchorsMeters(b, c);
    double distCA = _distanceBetweenAnchorsMeters(c, a);
    if (distAB < 1 || distBC < 1 || distCA < 1) return 0;

    double angleA = _angleFromSides(distBC, distCA, distAB);
    double angleB = _angleFromSides(distCA, distAB, distBC);
    double angleC = _angleFromSides(distAB, distBC, distCA);
    return math.min(angleA, math.min(angleB, angleC));
  }

  double _angleFromSides(double opposite, double side1, double side2) {
    double cosAngle =
        (side1 * side1 + side2 * side2 - opposite * opposite) /
        (2 * side1 * side2);
    cosAngle = cosAngle.clamp(-1.0, 1.0);
    return math.acos(cosAngle) * 180 / math.pi;
  }

  double _distanceBetweenAnchorsMeters(MapAnchor a, MapAnchor b) {
    return distanceBetweenAnchorsMeters(a, b);
  }

  void _captureCurrentAutomaticSet() {
    _pinnedAnchorIds.clear();
    final t = _currentTransform;
    if (t is SimilarityTransform) {
      _pinnedAnchorIds.addAll({t.latestId, t.referenceId});
    } else if (t is _AffineTransformerAdapter) {
      _pinnedAnchorIds.addAll(t._selectedPoints.map((a) => a.id));
    }
    // Если трансформер отсутствует, набор остаётся пустым
  }

  void removeAnchor(String anchorId) {
    _anchors.removeWhere((a) => a.id == anchorId);
    _pinnedAnchorIds.remove(anchorId);
    _buildTransformFromAnchors();
  }

  void updateAnchors(List<MapAnchor> anchors) {
    _anchors = anchors;
    _buildTransformFromAnchors();
  }

  void _buildTransformFromAnchors() {
    if (_manualMode) {
      final pinnedList = pinnedAnchors;

      if (pinnedList.length >= 3) {
        try {
          final affine = AffineTransform.fromPoints(
            pinnedList.map((a) => Offset(a.imageX, a.imageY)).toList(),
            pinnedList.map((a) => Offset(a.longitude, a.latitude)).toList(),
            weights: _AffineTransformerAdapter._buildWeights(pinnedList.length),
          );
          final rmse = _AffineTransformerAdapter._computeRmse(
            pinnedList,
            affine,
          );
          final selfError = _AffineTransformerAdapter._computeSelfError(
            pinnedList,
            affine,
          );
          _currentTransform = _AffineTransformerAdapter._(
            affine: affine,
            selectedPoints: pinnedList,
            rmse: rmse,
            selfError: selfError,
          );
          return;
        } catch (_) {}
      } else if (pinnedList.length == 2) {
        _currentTransform = SimilarityTransform.fromPair(
          pinnedList[0],
          pinnedList[1],
        );
        return;
      }
      // недостаточно точек – привязка отсутствует
      _currentTransform = null;
      return;
    }

    // ----- Автоматический режим -----
    if (_mode == CalibrationMode.pairFarthest ||
        _mode == CalibrationMode.pairNearest) {
      if (_anchors.length >= 2) {
        MapWorkingPair? pair;
        if (_mode == CalibrationMode.pairFarthest) {
          pair = selectWorkingPair(_anchors);
        } else {
          pair = selectNearestValidPair(_anchors);
        }
        _currentTransform = pair != null
            ? SimilarityTransform.fromPair(pair.latest, pair.reference)
            : null;
      } else {
        _currentTransform = null;
      }
      return;
    }

    if (_anchors.length >= 3) {
      _MapTransformer? transform;
      try {
        final adapter = _AffineTransformerAdapter.fromAnchorsThreePoints(
          _anchors,
        );
        transform = adapter;
      } catch (_) {
        transform = null;
      }
      if (transform != null && transform.usedAnchorCount == 3) {
        _currentTransform = transform;
        return;
      }
      _buildFallback();
      return;
    }

    if (_anchors.length == 2) {
      final pair = selectWorkingPair(_anchors);
      _currentTransform = pair != null
          ? SimilarityTransform.fromPair(pair.latest, pair.reference)
          : null;
      return;
    }

    _currentTransform = null;
  }

  void _buildFallback() {
    final pair = selectWorkingPair(_anchors);
    _currentTransform = pair != null
        ? SimilarityTransform.fromPair(pair.latest, pair.reference)
        : null;
  }

  GeoPoint? imagePointToGeoFromCurrent(Offset imagePoint) {
    final t = _currentTransform;
    if (t == null) return null;
    final geo = t.imageToGeo(imagePoint);
    return GeoPoint(latitude: geo.dy, longitude: geo.dx);
  }

  Offset? geoToImagePointFromCurrent(double latitude, double longitude) {
    final t = _currentTransform;
    if (t == null) return null;
    return t.geoToImage(Offset(longitude, latitude));
  }

  MapWorkingPair? selectWorkingPair(
    List<MapAnchor> anchors, {
    double minDistanceMeters = 50.0,
  }) {
    if (anchors.length < 2) return null;
    final latest = anchors.last;
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

  MapWorkingPair? selectNearestValidPair(
    List<MapAnchor> anchors, {
    double minDistanceMeters = 50.0,
  }) {
    if (anchors.length < 2) return null;
    final latest = anchors.last;
    for (int i = anchors.length - 2; i >= 0; i--) {
      final candidate = anchors[i];
      final dist = distanceBetweenAnchorsMeters(latest, candidate);
      if (dist >= minDistanceMeters) {
        return MapWorkingPair(latest: latest, reference: candidate);
      }
    }
    return selectWorkingPair(anchors, minDistanceMeters: 0);
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
