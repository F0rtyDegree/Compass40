import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'map_screen.dart';
import '../theme_provider.dart';
import '../widgets/compass_section.dart';
import '../widgets/gps_section.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../controllers/home_logic.dart';
import '../controllers/home_state.dart';
import '../controllers/home_navigation_actions.dart';
import '../services/log_service.dart';
import '../services/sensor_service.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late final HomeState _state;
  late final LogService _logService;
  late final SensorService _sensorService;
  late final HomeLogic _logic;
  late final HomeNavigationActions _actions;

  @override
  void initState() {
    super.initState();
    _state = HomeState();
    _logService = LogService();
    _sensorService = SensorService();
    _logic = HomeLogic(
      state: _state,
      hostState: this,
      logService: _logService,
      sensorService: _sensorService,
    );
    Provider.of<ThemeProvider>(context, listen: false).loadTheme();
    _logic.init();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _actions = HomeNavigationActions(
      context: context,
      state: _state,
      logic: _logic,
    );
  }

  @override
  void dispose() {
    _logic.dispose();
    super.dispose();
  }

  Future<void> _handleExitRequest() async {
    final exit = await showExitConfirmDialog(context);
    if (exit == true) {
      await _logic.clearWaypoint();
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) {
        if (didPop) return;
        _handleExitRequest();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Compass 40°'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _actions.openSettings,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _actions.openAbout,
            ),
          ],
        ),
        body: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            CompassSection(
              headingNotifier: _state.headingNotifier,
              accuracyNotifier: _state.accuracyNotifier,
              isGpsCompassActiveNotifier: _state.isGpsCompassActiveNotifier,
              bearingToTarget: _state.bearingToTarget,
              bearingToWaypoint: _state.bearingToWaypoint,
              logItems: _state.logItems,
              setWaypoint: _logic.setWaypoint,
              clearWaypoint: _logic.clearWaypoint,
              onVerticalDragEnd: _actions.handleVerticalDragEnd,
              getCardinalDirection: _logic.getCardinalDirection,
              getAccuracyStatusColor: _logic.getAccuracyStatusColor,
              getAccuracyText: _logic.getAccuracyText,
              onSwipeToOpenMap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MapScreen(
                      magneticDeclination: _state.magneticDeclination,
                      onAnchorAdded: (lat, lon, distance, timeStr) async {
                        final items = await _logService.addMapAnchorLogEntry(
                          currentLogItems: _state.logItems,
                          latitude: lat,
                          longitude: lon,
                          distanceFromPrevious: distance,
                          timeStr: timeStr,
                        );
                        if (mounted) {
                          setState(() {
                            _state.logItems = items;
                          });
                        }
                      },
                      onStartNavigation: _logic.startNavigationFromExternal,
                      onCancelNavigation: _logic.cancelExternalNavigation,
                    ),
                  ),
                );
              },
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
