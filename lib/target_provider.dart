
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

class TargetProvider with ChangeNotifier {
  double? _targetAzimuth;
  double? _targetDistance;

  double? get targetAzimuth => _targetAzimuth;
  double? get targetDistance => _targetDistance;

  void setTarget(double azimuth, double distance) {
    _targetAzimuth = azimuth;
    _targetDistance = distance;
    notifyListeners();
  }

  void clearTarget() {
    _targetAzimuth = null;
    _targetDistance = null;
    notifyListeners();
  }

  void updateTarget(double currentLat, double currentLon, double targetLat, double targetLon) {
    _targetDistance = _calculateDistance(currentLat, currentLon, targetLat, targetLon);
    _targetAzimuth = _calculateBearing(currentLat, currentLon, targetLat, targetLon);
    notifyListeners();
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371e3;
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final deltaPhi = (lat2 - lat1) * math.pi / 180;
    final deltaLambda = (lon2 - lon1) * math.pi / 180;

    final a = math.sin(deltaPhi / 2) * math.sin(deltaPhi / 2) +
        math.cos(phi1) * math.cos(phi2) *
            math.sin(deltaLambda / 2) * math.sin(deltaLambda / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return R * c;
  }

  double _calculateBearing(double lat1, double lon1, double lat2, double lon2) {
    final phi1 = lat1 * math.pi / 180;
    final phi2 = lat2 * math.pi / 180;
    final lambda1 = lon1 * math.pi / 180;
    final lambda2 = lon2 * math.pi / 180;

    final y = math.sin(lambda2 - lambda1) * math.cos(phi2);
    final x = math.cos(phi1) * math.sin(phi2) -
        math.sin(phi1) * math.cos(phi2) * math.cos(lambda2 - lambda1);
    final theta = math.atan2(y, x);
    return (theta * 180 / math.pi + 360) % 360;
  }
}
