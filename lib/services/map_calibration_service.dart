// ignore_for_file: avoid_print
import '../utils/app_constants.dart';
import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import '../models/map_anchor.dart';
import '../models/geo_point.dart';
import '../utils/geo_utils.dart';
import 'affine_transform.dart';
import '../models/bearing_and_distance.dart';
import 'point_selector.dart';
import '../models/map_working_pair.dart';
import '../transforms/similarity_transform.dart';
import '../transforms/photo_sever_transform.dart';
export '../models/bearing_and_distance.dart';
export '../models/geo_point.dart';
export '../transforms/similarity_transform.dart';

enum CalibrationMode { affine, pairFarthest, pairNearest, photoSever }

class _AffineTransformerAdapter implements MapTransformer {
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
    final selected = PointSelector.selectBestThreePoints(anchors);
    if (selected.length < 3) {
      throw ArgumentError('Could not find valid triangle');
    }
    final three = selected.take(3).toList();
    final affine = AffineTransform.fromPoints(
      three.map((a) => Offset(a.imageX, a.imageY)).toList(),
      three.map((a) => Offset(a.longitude, a.latitude)).toList(),
      weights: PointSelector.buildWeights(three.length),
    );
    final rmse = PointSelector.computeRmse(three, affine);
    final selfError = PointSelector.computeSelfError(three, affine);
    return _AffineTransformerAdapter._(
      affine: affine,
      selectedPoints: three,
      rmse: rmse,
      selfError: selfError,
    );
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
  List<MapAnchor> _anchors = [];
  MapTransformer? _currentTransform;
  CalibrationMode _mode = CalibrationMode.affine;
  final Set<String> _pinnedAnchorIds = {};
  bool _manualMode = false; // true, если пользователь хоть раз коснулся якоря

  // ✅ Данные ФотоСевера для режима P
  double _psLineMeters = 0.0;
  double _psLinePixels = 0.0;
  double _psNorthAngle = 0.0;
  double _magneticDeclination = 0.0;

  void setMagneticDeclination(double declinationDegrees) {
    _magneticDeclination = declinationDegrees;
    // Перестроить трансформацию, если сейчас активен режим P
    if (_mode == CalibrationMode.photoSever) {
      _buildTransformFromAnchors();
    }
  }

  void updatePhotoSeverData({
    required double lineMeters,
    required double linePixels,
    required double northAngle,
  }) {
    _psLineMeters = lineMeters;
    _psLinePixels = linePixels;
    _psNorthAngle = northAngle;
    if (_mode == CalibrationMode.photoSever) {
      _buildTransformFromAnchors();
    }
  }

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
    // В ручном режиме показываем все выбранные точки
    if (_manualMode) {
      return _pinnedAnchorIds.toSet();
    }

    final t = _currentTransform;
    if (t is _AffineTransformerAdapter) {
      return t._selectedPoints.map((a) => a.id).toSet();
    }

    // ✅ ИСПРАВЛЕНИЕ: Для двухточечных режимов (F и N) берем ID из SimilarityTransform
    if (t is SimilarityTransform) {
      return t.activeAnchorIds; // Возвращает {latestId, referenceId}
    }

    return null;
  }

  String? get activeAnchorIndices {
    final t = _currentTransform;
    if (t is! _AffineTransformerAdapter) return null;

    final ids = t._selectedPoints.map((a) => a.id).toSet();
    if (ids.isEmpty) return null;

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
    // ✅ Режим P всегда показывается как 'P', независимо от _manualMode
    if (_mode == CalibrationMode.photoSever) {
      return 'P';
    }
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
      case CalibrationMode.photoSever:
        return 'P';
    }
  }

  void setCalibrationMode(CalibrationMode mode) {
    // Если переключаемся в P, сохраняем текущий активный якорь (если есть)
    if (mode == CalibrationMode.photoSever) {
      // Если уже есть закреплённые якоря, оставляем их (возможно, один)
      if (_pinnedAnchorIds.isEmpty && _anchors.isNotEmpty) {
        // Пытаемся взять активный якорь из текущего трансформа
        if (_currentTransform is _AffineTransformerAdapter) {
          final activeIds = (_currentTransform as _AffineTransformerAdapter)
              ._selectedPoints
              .map((a) => a.id)
              .toSet();
          if (activeIds.length == 1) {
            _pinnedAnchorIds.addAll(activeIds);
          } else {
            // Если активных несколько, берём последний добавленный якорь
            _pinnedAnchorIds.add(_anchors.last.id);
          }
        } else if (_currentTransform is SimilarityTransform) {
          final ids =
              (_currentTransform as SimilarityTransform).activeAnchorIds;
          if (ids != null && ids.isNotEmpty) {
            _pinnedAnchorIds.add(ids.first);
          } else {
            _pinnedAnchorIds.add(_anchors.last.id);
          }
        } else {
          _pinnedAnchorIds.add(_anchors.last.id);
        }
      }
      _manualMode = _pinnedAnchorIds.isNotEmpty;
    } else {
      _manualMode = false;
    }
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
    // ✅ Режим P: всегда ровно один активный якорь, переключение молча
    if (_mode == CalibrationMode.photoSever) {
      if (_pinnedAnchorIds.contains(anchorId)) {
        _pinnedAnchorIds.remove(anchorId);
      } else {
        _pinnedAnchorIds.clear();
        _pinnedAnchorIds.add(anchorId);
      }
      _manualMode = _pinnedAnchorIds.isNotEmpty;
      _buildTransformFromAnchors();
      return;
    }

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
    // Ищем хотя бы одну неколлинеарную тройку
    for (int i = 0; i < points.length; i++) {
      for (int j = i + 1; j < points.length; j++) {
        for (int k = j + 1; k < points.length; k++) {
          double angle = _triangleMinAngle(points[i], points[j], points[k]);
          if (angle >= AppConstants.minTriangleAngleDegrees) {
            return false; // нашли неколлинеарную тройку — набор допустим
          }
        }
      }
    }
    return true; // все тройки вырождены
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
    if (t is _AffineTransformerAdapter) {
      _pinnedAnchorIds.addAll(t._selectedPoints.map((a) => a.id));
    }
    // ✅ ИСПРАВЛЕНИЕ: Захватываем рабочую пару из режимов F и N
    else if (t is SimilarityTransform) {
      final ids = t.activeAnchorIds;
      if (ids != null) {
        _pinnedAnchorIds.addAll(ids);
      }
    }
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
    // ✅ Режим P: одноточечная привязка по данным ФотоСевера
    if (_mode == CalibrationMode.photoSever) {
      print(
        'DEBUG P: pinned=${_pinnedAnchorIds.length}, linePixels=$_psLinePixels',
      );
      if (_pinnedAnchorIds.length == 1 && _psLinePixels > 0) {
        final baseId = _pinnedAnchorIds.first;
        MapAnchor? baseAnchor;
        try {
          baseAnchor = _anchors.firstWhere((a) => a.id == baseId);
        } catch (_) {
          _currentTransform = null;
          return;
        }
        // Переводим магнитный угол в истинный: истинный_север = магнитный_север - склонение
        // (при восточном склонении магнитный север восточнее истинного, значит,
        // чтобы из магнитного угла получить истинный, нужно вычесть склонение)
        final trueNorthAngle =
            _psNorthAngle - _magneticDeclination * math.pi / 180;
        _currentTransform = PhotoSeverTransform(
          baseAnchor: baseAnchor,
          lineMeters: _psLineMeters,
          linePixels: _psLinePixels,
          northAngle: trueNorthAngle,
        );
      } else {
        _currentTransform = null;
      }
      return;
    }

    if (_manualMode) {
      final pinnedList = pinnedAnchors;
      if (pinnedList.length >= 3) {
        try {
          final affine = AffineTransform.fromPoints(
            pinnedList.map((a) => Offset(a.imageX, a.imageY)).toList(),
            pinnedList.map((a) => Offset(a.longitude, a.latitude)).toList(),
            weights: PointSelector.buildWeights(pinnedList.length),
          );
          final rmse = PointSelector.computeRmse(pinnedList, affine);
          final selfError = PointSelector.computeSelfError(pinnedList, affine);
          _currentTransform = _AffineTransformerAdapter._(
            affine: affine,
            selectedPoints: pinnedList,
            rmse: rmse,
            selfError: selfError,
          );
          return;
        } catch (_) {}
      }
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

    if (_mode == CalibrationMode.affine) {
      if (_anchors.length >= 2) {
        // Пытаемся построить аффинную тройку, если точек достаточно
        if (_anchors.length >= 3) {
          try {
            final adapter = _AffineTransformerAdapter.fromAnchorsThreePoints(
              _anchors,
            );
            if (adapter.usedAnchorCount == 3) {
              _currentTransform = adapter;
              return;
            }
          } catch (_) {}
        }
        // Fallback: двухточечная привязка (farthest pair) для 2+ якорей
        final pair = selectWorkingPair(_anchors, minDistanceMeters: AppConstants.minAnchorDistanceMeters);
        if (pair != null) {
          _currentTransform = SimilarityTransform.fromPair(
            pair.latest,
            pair.reference,
          );
          return;
        }
      }
      _currentTransform = null;
      return;
    }

    // Если режим не распознан — сброс
    _currentTransform = null;
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

  double distanceBetweenAnchorsMeters(MapAnchor a, MapAnchor b) {
    return calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);
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

  SimilarityTransform? _buildTransform(MapWorkingPair pair) {
    try {
      return SimilarityTransform.fromPair(pair.latest, pair.reference);
    } catch (_) {
      return null;
    }
  }

  double? getMapRotation(MapWorkingPair pair) {
    final transform = _buildTransform(pair);
    return transform?.angleRadians;
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

  BearingAndDistance bearingAndDistance({
    required double fromLat,
    required double fromLon,
    required double toLat,
    required double toLon,
    required double magneticDeclination,
  }) {
    final dist = calculateDistance(fromLat, fromLon, toLat, toLon);
    final trueBearing = calculateTrueBearing(fromLat, fromLon, toLat, toLon);
    final magneticBearing = (trueBearing - magneticDeclination + 360) % 360;
    return BearingAndDistance(
      distanceMeters: dist,
      trueBearing: trueBearing,
      magneticBearing: magneticBearing,
    );
  }
}
