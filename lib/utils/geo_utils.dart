import 'dart:math' as math;

/// Расчёт координат цели по дистанции и истинному азимуту
Map<String, double> calculateTargetCoordinates({
  required double startLat,
  required double startLon,
  required double distanceMeters,
  required double trueBearingDegrees, // истинный азимут
}) {
  const R = 6371000.0;

  final phi1 = startLat * math.pi / 180;
  final lambda1 = startLon * math.pi / 180;
  final theta = trueBearingDegrees * math.pi / 180;
  final dR = distanceMeters / R;

  final sinPhi2 =
      math.sin(phi1) * math.cos(dR) + math.cos(phi1) * math.sin(dR) * math.cos(theta);
  final phi2 = math.asin(sinPhi2);
  final y = math.sin(theta) * math.sin(dR) * math.cos(phi1);
  final x = math.cos(dR) - math.sin(phi1) * math.sin(phi2);
  final lambda2 = lambda1 + math.atan2(y, x);

  return {
    'latitude': phi2 * 180 / math.pi,
    'longitude': lambda2 * 180 / math.pi,
  };
}

double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  const R = 6371e3;
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dPhi = (lat2 - lat1) * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;

  final a = math.sin(dPhi / 2) * math.sin(dPhi / 2) +
      math.cos(phi1) * math.cos(phi2) *
          math.sin(dLambda / 2) * math.sin(dLambda / 2);
  final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  return R * c;
}

/// Возвращает истинный азимут
double calculateTrueBearing(double lat1, double lon1, double lat2, double lon2) {
  final phi1 = lat1 * math.pi / 180;
  final phi2 = lat2 * math.pi / 180;
  final dLambda = (lon2 - lon1) * math.pi / 180;

  final y = math.sin(dLambda) * math.cos(phi2);
  final x =
      math.cos(phi1) * math.sin(phi2) - math.sin(phi1) * math.cos(phi2) * math.cos(dLambda);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}
