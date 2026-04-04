import 'package:flutter/material.dart';

import '../about_screen.dart';
import '../log_screen.dart';
import '../settings_screen.dart';
import '../target_screen.dart';
import '../utils/geo_utils.dart';
import 'home_logic.dart';
import 'home_state.dart';

class HomeNavigationActions {
  final BuildContext context;
  final HomeState state;
  final HomeLogic logic;

  HomeNavigationActions({
    required this.context,
    required this.state,
    required this.logic,
  });

  void openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const SettingsScreen(),
      ),
    ).then((_) => logic.reloadSettings());
  }

  void openAbout() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AboutScreen(),
      ),
    );
  }

  Future<void> handleVerticalDragEnd(DragEndDetails details) async {
    if (details.primaryVelocity! < 0) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (c) => LogScreen(logItems: state.logItems),
        ),
      ).then((_) => logic.loadLogEntries());
    } else if (details.primaryVelocity! > 0) {
      logic.setTargetCalculationStartPoint(
        state.gpsDataNotifier.value,
      );

      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (context) => const TargetScreen(),
        ),
      );

      if (result == null) return;

      final useClipboardAsBase =
          result['useClipboardAsBase'] as bool? ?? false;

      double startLat, startLon;
      if (useClipboardAsBase) {
        startLat = result['base_latitude'] as double;
        startLon = result['base_longitude'] as double;
      } else {
        if (state.targetCalculationStartPoint?.latitude == null) {
          return;
        }
        startLat = state.targetCalculationStartPoint!.latitude!;
        startLon = state.targetCalculationStartPoint!.longitude!;
      }

      final magneticAzimuth = result['azimuth'] as double;
      final trueBearing =
          (magneticAzimuth + state.magneticDeclination + 360) % 360;

      final coords = calculateTargetCoordinates(
        startLat: startLat,
        startLon: startLon,
        distanceMeters: result['distance'] as double,
        trueBearingDegrees: trueBearing,
      );

      logic.setTarget(coords);

      await logic.addTargetCreationLogEntry(
        baseLatitude: startLat,
        baseLongitude: startLon,
        azimuth: magneticAzimuth,
        distance: result['distance'] as double,
        targetLatitude: coords['latitude']!,
        targetLongitude: coords['longitude']!,
      );
    }
  }
}
