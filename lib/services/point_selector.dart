import 'dart:math' as math;
import 'dart:ui';
import '../models/map_anchor.dart';
import 'affine_transform.dart';
import '../utils/app_constants.dart';
import '../utils/geo_utils.dart';

class PointSelector {
  // Веса для последней точки
  static List<double> buildWeights(int n) {
    final w = List.filled(n, 1.0);
    if (n > 0) w[0] = AppConstants.latestPointWeight;
    return w;
  }

  // RMSE по набору точек
  static double computeRmse(List<MapAnchor> points, AffineTransform affine) {
    double sumSq = 0;
    for (final a in points) {
      final pred = affine.transform(Offset(a.imageX, a.imageY));
      final d = calculateDistance(a.latitude, a.longitude, pred.dy, pred.dx);
      sumSq += d * d;
    }
    return math.sqrt(sumSq / points.length);
  }

  // Self error для последней точки
  static double computeSelfError(List<MapAnchor> points, AffineTransform affine) {
    if (points.isEmpty) return 0;
    final latest = points.first;
    final pred = affine.transform(Offset(latest.imageX, latest.imageY));
    return calculateDistance(latest.latitude, latest.longitude, pred.dy, pred.dx);
  }

  // Основной метод отбора трёх точек
  static List<MapAnchor> selectBestThreePoints(List<MapAnchor> anchors) {
    final latest = anchors.last;
    if (anchors.length == 1) return <MapAnchor>[latest];

    double distMeters(MapAnchor a, MapAnchor b) =>
        calculateDistance(a.latitude, a.longitude, b.latitude, b.longitude);

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
      if (d >= AppConstants.minAnchorDistanceMeters && d > maxDist) {
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
      if (distMeters(latest, x) < AppConstants.minAnchorDistanceMeters || distMeters(farthest, x) < AppConstants.minAnchorDistanceMeters) continue;

      final a = distMeters(farthest, x);
      final b = distMeters(latest, x);
      final c = distMeters(latest, farthest);
      if (a < AppConstants.minTriangleSideMeters || b < AppConstants.minTriangleSideMeters || c < AppConstants.minTriangleSideMeters) continue;

      final cosAngle = (b * b + c * c - a * a) / (2 * b * c);
      final angle = math.acos(cosAngle.clamp(-1.0, 1.0)) * 180 / math.pi;

      if (angle < AppConstants.minTriangleAngleDegrees || angle > AppConstants.maxTriangleAngleDegrees) continue;

      final area = triangleAreaM2(latest, farthest, x);
      if (area > bestArea) {
        bestArea = area;
        bestThird = x;
      }
    }

    if (bestArea < AppConstants.minTriangleAreaM2 || bestThird == null) {
      return <MapAnchor>[];
    }

    return <MapAnchor>[latest, farthest, bestThird];
  }
}
