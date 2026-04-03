import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../about_screen.dart';
import '../settings_screen.dart';
import '../theme_provider.dart';
import '../log_screen.dart';
import '../target_screen.dart';
import '../utils/geo_utils.dart';
import '../widgets/compass_section.dart';
import '../widgets/gps_section.dart';
import '../controllers/home_logic.dart';
import '../controllers/home_state.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final HomeState _state;
  late final HomeLogic _logic;

  @override
  void initState() {
    super.initState();
    _state = HomeState();
    _logic = HomeLogic(state: _state, hostState: this);

    Provider.of<ThemeProvider>(context, listen: false).loadTheme();
    _logic.init();
  }

  @override
  void dispose() {
    _logic.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;

        showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Вы уверены?'),
            content: const Text('Вы хотите закрыть приложение?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Нет'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Да'),
              ),
            ],
          ),
        ).then((exit) {
          if (exit == true) {
            _logic.clearWaypoint().then((_) {
              SystemNavigator.pop();
            });
          }
        });
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compass 40°'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const SettingsScreen(),
                  ),
                ).then((_) => _logic.reloadSettings());
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AboutScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CompassSection(
              headingNotifier: _state.headingNotifier,
              accuracyNotifier: _state.accuracyNotifier,
              bearingToTarget: _state.bearingToTarget,
              bearingToWaypoint: _state.bearingToWaypoint,
              logItems: _state.logItems,
              setWaypoint: _logic.setWaypoint,
              clearWaypoint: _logic.clearWaypoint,
              onVerticalDragEnd: (details) async {
                if (details.primaryVelocity! < 0) {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (c) => LogScreen(logItems: _state.logItems),
                    ),
                  ).then((_) => _logic.loadLogEntries());
                } else if (details.primaryVelocity! > 0) {
                  _logic.setTargetCalculationStartPoint(
                    _state.gpsDataNotifier.value,
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
                    if (_state.targetCalculationStartPoint?.latitude == null) {
                      return;
                    }
                    startLat = _state.targetCalculationStartPoint!.latitude!;
                    startLon = _state.targetCalculationStartPoint!.longitude!;
                  }

                  final magneticAzimuth = result['azimuth'] as double;
                  final trueBearing =
                      (magneticAzimuth + _state.magneticDeclination + 360) % 360;

                  final coords = calculateTargetCoordinates(
                    startLat: startLat,
                    startLon: startLon,
                    distanceMeters: result['distance'] as double,
                    trueBearingDegrees: trueBearing,
                  );

                  _logic.setTarget(coords);

                  await _logic.addTargetCreationLogEntry(
                    baseLatitude: startLat,
                    baseLongitude: startLon,
                    azimuth: magneticAzimuth,
                    distance: result['distance'] as double,
                    targetLatitude: coords['latitude']!,
                    targetLongitude: coords['longitude']!,
                  );
                }
              },
              getCardinalDirection: _logic.getCardinalDirection,
              getAccuracyStatusColor: _logic.getAccuracyStatusColor,
              getAccuracyText: _logic.getAccuracyText,
            ),
            GpsSection(
              gpsDataNotifier: _state.gpsDataNotifier,
              accuracyNotifier: _state.accuracyNotifier,
              distanceToTarget: _state.distanceToTarget,
              bearingToTarget: _state.bearingToTarget,
              distanceToWaypoint: _state.distanceToWaypoint,
              bearingToWaypoint: _state.bearingToWaypoint,
              waypoint: _state.waypoint,
              target: _state.target,
              logItems: _state.logItems,
              magneticDeclination: _state.magneticDeclination,
              onClearTarget: _logic.clearTarget,
              onClearWaypoint: _logic.clearWaypoint,
            ),
          ],
        ),
      ),
    );
  }
}
