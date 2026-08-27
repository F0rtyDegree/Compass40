// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'map_screen.dart';
import 'help_viewer_screen.dart';
import '../theme_provider.dart';
import '../widgets/compass_section.dart';
import '../widgets/gps_section.dart';
import '../widgets/exit_confirm_dialog.dart';
import '../controllers/home_logic.dart';
import '../controllers/home_state.dart';
import '../controllers/home_navigation_actions.dart';
import '../services/log_service.dart';
import '../services/sensor_service.dart';
import 'dart:async';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with WidgetsBindingObserver {
  late final HomeState _state;
  late final LogService _logService;
  late final SensorService _sensorService;
  late final HomeLogic _logic;
  late final HomeNavigationActions _actions;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state = HomeState();
    _logService = LogService();
    _sensorService = SensorService();
    _logic = HomeLogic(
      state: _state,
      setState: (fn) {
        if (mounted) setState(fn);
      },
      logService: _logService,
      sensorService: _sensorService,
    );
    Provider.of<ThemeProvider>(context, listen: false).loadTheme();
    _logic.init().then((_) {
      // Показываем уведомление о восстановлении трека
      if (_logic.wasTrackRecovered && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Запись трека восстановлена после сбоя'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    });
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
    WidgetsBinding.instance.removeObserver(this);
    _logic.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached) {
      _logic.dispose();
    }
  }

  Future<void> _handleExitRequest() async {
    final exitConfirmed = await showExitConfirmDialog(context);
    if (exitConfirmed == true) {
      final completer = Completer<void>();

      // Таймаут на случай, если финализация зависнет
      Future.delayed(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          print('finalizeTrackAndExport timeout, forcing exit');
          completer.complete();
        }
      });

      try {
        await _logic.finalizeTrackAndExport();
      } catch (e, stack) {
        print('Error finalizing track: $e');
        print(stack);
      } finally {
        if (!completer.isCompleted) {
          completer.complete();
        }
      }

      await completer.future;

      try {
        await _logic.clearWaypoint();
      } catch (e) {
        print('Error clearing waypoint: $e');
      }

      _logic.dispose();

      // Закрываем приложение безопасным способом
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
            // Кнопка записи трека
            ValueListenableBuilder<bool>(
              valueListenable: _state.isRecordingTrackNotifier,
              builder: (context, isRecording, _) {
                return IconButton(
                  icon: Icon(
                    isRecording ? Icons.stop : Icons.play_arrow,
                    color: isRecording ? Colors.red : Colors.grey,
                  ),
                  onPressed: _logic.toggleTrackRecording,
                  tooltip: isRecording
                      ? 'Остановить запись трека'
                      : 'Начать запись трека',
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: _actions.openSettings,
            ),
            IconButton(
              icon: const Icon(Icons.help_outline),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const HelpViewerScreen(
                      helpFilePath: 'assets/help/compass_help.md',
                    ),
                  ),
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: _actions.openAbout,
            ),
          ],
        ),
        body: ListView(
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
                      gpsDataNotifier: _state.gpsDataNotifier,
                      magneticDeclination: _state.magneticDeclination,
                      headingNotifier: _state.headingNotifier,
                      onAnchorAdded: (lat, lon, distance, createdAt) async {
                        final items = await _logService.addMapAnchorLogEntry(
                          currentLogItems: _state.logItems,
                          latitude: lat,
                          longitude: lon,
                          distanceFromPrevious: distance,
                          createdAt: createdAt,
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
                ).then((_) => _logic.reloadSettings());
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
