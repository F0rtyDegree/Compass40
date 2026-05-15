import 'dart:math';

/// Вычисляет круговую медиану для списка углов (в градусах).
double calculateCircularMedian(List<double> angles) {
  if (angles.isEmpty) return 0.0;
  if (angles.length == 1) return angles.first % 360;

  final sorted = List<double>.from(angles)..sort();
  final n = sorted.length;
  
  double maxGap = 0;
  int gapIndex = 0;
  
  for (int i = 0; i < n; i++) {
    final current = sorted[i];
    final next = sorted[(i + 1) % n];
    double gap = (next - current) % 360;
    if (gap < 0) gap += 360;
    
    if (gap > maxGap) {
      maxGap = gap;
      gapIndex = i;
    }
  }
  
  final cutList = <double>[];
  for (int i = 0; i < n; i++) {
    final idx = (gapIndex + 1 + i) % n;
    double val = sorted[idx];
    if (idx <= gapIndex) {
      val += 360;
    }
    cutList.add(val);
  }
  
  double median;
  if (n % 2 == 1) {
    median = cutList[n ~/ 2];
  } else {
    median = (cutList[n ~/ 2 - 1] + cutList[n ~/ 2]) / 2;
  }
  
  return median % 360;
}

/// Вычисляет расстояние между двумя точками (в метрах).
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const double earthRadius = 6371000; // метров
  final dLat = _toRadians(lat2 - lat1);
  final dLon = _toRadians(lon2 - lon1);
  final a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);
  final c = 2 * asin(sqrt(a));
  return earthRadius * c;
}

/// Вычисляет истинный пеленг (азимут) от точки 1 к точке 2 (в градусах).
double calculateTrueBearing(
    double lat1, double lon1, double lat2, double lon2) {
  final dLon = _toRadians(lon2 - lon1);
  final lat1Rad = _toRadians(lat1);
  final lat2Rad = _toRadians(lat2);

  final y = sin(dLon) * cos(lat2Rad);
  final x = cos(lat1Rad) * sin(lat2Rad) -
      sin(lat1Rad) * cos(lat2Rad) * cos(dLon);
  final bearingRad = atan2(y, x);
  final bearingDeg = bearingRad * (180 / pi);
  
  return (bearingDeg + 360) % 360;
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
  final lon2 = lon1 + atan2(
    sin(bearing) * sin(d) * cos(lat1),
    cos(d) - sin(lat1) * sin(lat2)
  );

  return {
    'lat': lat2 * (180 / pi),
    'lon': lon2 * (180 / pi),
  };
}

double _toRadians(double degrees) => degrees * (pi / 180);