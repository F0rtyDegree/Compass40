import 'dart:async';
import 'dart:developer' as developer;

import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SensorService {
  Future<SensorSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final useManualDeclination =
        prefs.getBool('useManualDeclination') ?? false;

    final magneticDeclination = useManualDeclination
        ? (prefs.getDouble('manualDeclination') ?? 0.0)
        : 0.0;

    final averagingPeriod = prefs.getInt('averagingPeriod') ?? 500;
    final smoothingFactor = prefs.getDouble('smoothingFactor') ?? 0.5;
    final uiUpdatePeriod = prefs.getInt('uiUpdatePeriod') ?? 250;
    final gpsInterval = prefs.getInt('gpsUpdateInterval') ?? 1;

    return SensorSettings(
      useManualDeclination: useManualDeclination,
      magneticDeclination: magneticDeclination,
      averagingPeriod: averagingPeriod,
      smoothingFactor: smoothingFactor,
      uiUpdatePeriod: uiUpdatePeriod,
      gpsInterval: gpsInterval,
    );
  }

  Future<bool> requestLocationPermission() async {
    return (await Permission.location.request()).isGranted;
  }

  StreamSubscription<GpsData> subscribeToGps({
    required GpsInfo gpsInfo,
    required int intervalSeconds,
    required void Function(GpsData gpsData) onData,
  }) {
    return gpsInfo
        .getGpsDataStream(intervalSeconds * 1000)
        .handleError((error, stack) {
      developer.log(
        'Error in GPS stream',
        name: 'by.fortydegree.testgps',
        error: error,
        stackTrace: stack,
      );
    }).listen(onData);
  }

  StreamSubscription<List<double>> subscribeToCompass({
    required void Function(List<double> data) onData,
  }) {
    return MyCompass.events.listen(onData);
  }
}

class SensorSettings {
  final bool useManualDeclination;
  final double magneticDeclination;
  final int averagingPeriod;
  final double smoothingFactor;
  final int uiUpdatePeriod;
  final int gpsInterval;

  SensorSettings({
    required this.useManualDeclination,
    required this.magneticDeclination,
    required this.averagingPeriod,
    required this.smoothingFactor,
    required this.uiUpdatePeriod,
    required this.gpsInterval,
  });
}
