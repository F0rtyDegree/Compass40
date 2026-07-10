import 'dart:math';
import 'angle_utils.dart';
import '../models/geo_point.dart';

/// Вычисляет расстояние между двумя точками (в метрах).
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadius = 6371000; // метров
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * asin(sqrt(a));
  return earthRadius * c;
}

/// Вычисляет истинный пеленг (азимут) от точки 1 к точке 2 (в градусах).
double calculateTrueBearing(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  final dLon = _toRadians(lon2 - lon1);
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);

  final y = sin(dLon) * cos(lat2Rad);
  final x =
      cos(lat1Rad) * sin(lat2Rad) - sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
  final bearingRad = atan2(y, x);
  final bearingDeg = bearingRad * (180 / pi);

  return normalizeBearing(bearingDeg);
}

/// Вычисляет координаты точки, находящейся на заданном расстоянии и пеленге от начальной точки.
Map<String, double> calculateTargetCoordinates({
  required double startLat,
  required double startLon,
  required double distanceMeters,
  required double trueBearingDegrees,
}) {
  const double earthRadius = 6371000; // метров

  final lat1 = startLat * (pi / 180);
  final lon1 = startLon * (pi / 180);
  final bearing = trueBearingDegrees * (pi / 180);
  final d = distanceMeters / earthRadius;

  final lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(bearing));
  final lon2 =
      lon1 +
      atan2(sin(bearing) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2));

  return {'latitude': lat2 * (180 / pi), 'longitude': lon2 * (180 / pi)};
}

/// Результат навигационных расчетов: дистанция, истинный и магнитный азимуты.
class NavigationData {
  final double distanceMeters;
  final double trueBearing;
  final double magneticBearing;

  const NavigationData({
    required this.distanceMeters,
    required this.trueBearing,
    required this.magneticBearing,
  });
}

/// Вычисляет дистанцию, истинный и магнитный азимуты между двумя точками.
NavigationData calculateNavigationData({
  required double fromLat,
  required double fromLon,
  required double toLat,
  required double toLon,
  required double magneticDeclination,
}) {
  final distance = calculateDistance(fromLat, fromLon, toLat, toLon);
  final trueBearing = calculateTrueBearing(fromLat, fromLon, toLat, toLon);
  final magneticBearing = normalizeBearing(trueBearing - magneticDeclination);

  return NavigationData(
    distanceMeters: distance,
    trueBearing: trueBearing,
    magneticBearing: magneticBearing,
  );
}

double _toRadians(double degrees) => degrees * (pi / 180);

/// Пытается распарсить строку вида "широта,долгота".
/// Возвращает [GeoPoint] или `null` при неверном формате.
GeoPoint? parseCoordinates(String text) {
  final parts = text.trim().split(',');
  if (parts.length != 2) return null;
  final lat = double.tryParse(parts[0].trim());
  final lon = double.tryParse(parts[1].trim());
  if (lat == null || lon == null) return null;
  return GeoPoint(latitude: lat, longitude: lon);
}