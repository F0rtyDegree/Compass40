import 'package:flutter/services.dart';
import '../utils/geo_utils.dart';
import '../utils/gpx_parser.dart';

class BRouterRouteResult {
  final List<Offset> gpsPoints;
  final double distanceMeters;

  const BRouterRouteResult({
    required this.gpsPoints,
    required this.distanceMeters,
  });
}

class BRouterService {
  static const MethodChannel _channel = MethodChannel(
    'by.fortydegree.compass40/brouter',
  );

  static Future<bool> isInstalled() async {
    try {
      final result = await _channel.invokeMethod<bool>('isInstalled');
      return result ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<BRouterRouteResult?> getRoute({
    required double startLat,
    required double startLon,
    required double targetLat,
    required double targetLon,
    required String profile,
  }) async {
    try {
      final gpxString = await _channel.invokeMethod<String>('getRoute', {
        'lats': <double>[startLat, targetLat],
        'lons': <double>[startLon, targetLon],
        'v': profile,
      });

      if (gpxString == null || gpxString.isEmpty) return null;
      final trimmed = gpxString.trimLeft();
      if (!trimmed.startsWith('<?xml') && !trimmed.startsWith('<gpx')) {
        return null;
      }

      final points = parseTrackFromGpx(gpxString);
      if (points.length < 2) return null;

      double totalDistance = 0.0;
      for (int i = 1; i < points.length; i++) {
        totalDistance += calculateDistance(
          points[i - 1].dy,
          points[i - 1].dx,
          points[i].dy,
          points[i].dx,
        );
      }

      return BRouterRouteResult(
        gpsPoints: points,
        distanceMeters: totalDistance,
      );
    } catch (_) {
      return null;
    }
  }
}
