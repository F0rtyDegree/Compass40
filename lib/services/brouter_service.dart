import 'package:flutter/services.dart';
import '../utils/geo_utils.dart';
import '../utils/gpx_parser.dart';
import 'navigation_method_service.dart';

class BRouterRouteResult {
  final List<Offset> gpsPoints;
  final double distanceMeters;

  const BRouterRouteResult({
    required this.gpsPoints,
    required this.distanceMeters,
  });
}

class BRouterResponse {
  final BRouterRouteResult? route;
  final String? errorReason;

  const BRouterResponse.success(this.route) : errorReason = null;
  const BRouterResponse.failure(this.errorReason) : route = null;
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

  static Future<BRouterResponse> getRoute({
    required double startLat,
    required double startLon,
    required double targetLat,
    required double targetLon,
    required NavigationMethod method,
  }) async {
    try {
      final args = <String, dynamic>{
        'lats': <double>[startLat, targetLat],
        'lons': <double>[startLon, targetLon],
        if (method.isCustom && method.customFilePath != null)
          'remoteProfilePath': method.customFilePath
        else
          'v': method.profileName ?? 'foot',
      };

      final responseString =
          await _channel.invokeMethod<String>('getRoute', args);

      if (responseString == null || responseString.isEmpty) {
        return const BRouterResponse.failure('BRouter не вернул маршрут');
      }

      final trimmed = responseString.trimLeft();
      if (!trimmed.startsWith('<?xml') && !trimmed.startsWith('<gpx')) {
        final cleanError = trimmed
            .replaceFirst(RegExp(r'^Error:\s*', caseSensitive: false), '')
            .trim();
        return BRouterResponse.failure(
          cleanError.isNotEmpty
              ? cleanError
              : 'Не удалось построить маршрут в BRouter',
        );
      }

      final points = parseTrackFromGpx(responseString);
      if (points.length < 2) {
        return const BRouterResponse.failure('BRouter вернул пустой трек');
      }

      double totalDistance = 0.0;
      for (int i = 1; i < points.length; i++) {
        totalDistance += calculateDistance(
          points[i - 1].dy,
          points[i - 1].dx,
          points[i].dy,
          points[i].dx,
        );
      }

      return BRouterResponse.success(
        BRouterRouteResult(
          gpsPoints: points,
          distanceMeters: totalDistance,
        ),
      );
    } catch (e) {
      return BRouterResponse.failure('Ошибка BRouter: $e');
    }
  }
}
