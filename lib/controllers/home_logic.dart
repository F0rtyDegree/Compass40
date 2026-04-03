import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log_entry.dart';
import '../utils/geo_utils.dart';
import 'home_state.dart';

class HomeLogic {
  final HomeState state;
  final State hostState;

  HomeLogic({
    required this.state,
    required this.hostState,
  });

  bool get mounted => hostState.mounted;

  void setState(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      hostState.setState(fn);
    }
  }

  Future<void> init() async {
    await _loadAllSettings();
    await _loadLogEntries();
    _requestPermissions();
  }

  void dispose() {
    state.uiUpdateTimer?.cancel();
    state.gpsDataSubscription.cancel();
    state.compassSubscription.cancel();
    state.disposeNotifiers();
  }

  // ----------------------------------------------------------------------
  // ----------------------- МАГНИТНАЯ СИСТЕМА ----------------------------
  // ----------------------------------------------------------------------

  void startUiUpdateTimer() {
    state.uiUpdateTimer?.cancel();
    state.uiUpdateTimer = Timer.periodic(
      Duration(milliseconds: state.uiUpdatePeriod),
      (timer) {
        if (mounted) {
          _updateHeading();
          _calculateWaypointData();
          _calculateTargetData();
        }
      },
    );
  }

  void _updateHeading() {
    final now = DateTime.now().millisecondsSinceEpoch;
    state.headingSamples.removeWhere(
      (s) => now - s.$2 > state.averagingPeriod,
    );
    if (state.headingSamples.isEmpty) return;

    double sinSum = 0, cosSum = 0;
    for (var s in state.headingSamples) {
      final a = s.$1 * math.pi / 180;
      sinSum += math.sin(a);
      cosSum += math.cos(a);
    }

    final avgSin = sinSum / state.headingSamples.length;
    final avgCos = cosSum / state.headingSamples.length;
    final avgHeading = math.atan2(avgSin, avgCos) * 180 / math.pi;

    double diff = avgHeading - state.filteredHeading;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;

    state.filteredHeading += state.smoothingFactor * diff;
    state.filteredHeading = (state.filteredHeading + 360) % 360;

    state.headingNotifier.value = state.filteredHeading;
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      state.useManualDeclination =
          prefs.getBool('useManualDeclination') ?? false;
      if (state.useManualDeclination) {
        state.magneticDeclination =
            prefs.getDouble('manualDeclination') ?? 0.0;
      } else {
        state.magneticDeclination = 0.0;
      }
      state.averagingPeriod = prefs.getInt('averagingPeriod') ?? 500;
      state.smoothingFactor = prefs.getDouble('smoothingFactor') ?? 0.5;
      state.uiUpdatePeriod = prefs.getInt('uiUpdatePeriod') ?? 250;
    });

    startUiUpdateTimer();
  }

  Future<void> reloadSettings() async {
    await _loadAllSettings();
  }

  void _requestPermissions() async {
    if (await Permission.location.request().isGranted) {
      _subscribeToGpsDataStream();
      _subscribeToCompassStream();
    }
  }

  void _subscribeToGpsDataStream() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('gpsUpdateInterval') ?? 1;

    state.gpsDataSubscription = state.gpsInfo
        .getGpsDataStream(interval * 1000)
        .handleError((error, stack) {
      developer.log(
        'Error in GPS stream',
        name: 'by.fortydegree.testgps',
        error: error,
        stackTrace: stack,
      );
    }).listen((gpsData) {
      if (!mounted) return;
      state.gpsDataNotifier.value = gpsData;
      if (!state.useManualDeclination) {
        setState(() {
          state.magneticDeclination = gpsData.magneticDeclination ?? 0.0;
        });
      }
    });
  }

  void _subscribeToCompassStream() {
    state.compassSubscription = MyCompass.events.listen((data) {
      if (!mounted || data.isEmpty) return;

      final heading = data[0];
      final accuracy = data.length > 1 ? data[1] : 0.0;
      if (accuracy < 2) return;

      state.headingSamples.add((heading, DateTime.now().millisecondsSinceEpoch));
      if (state.headingSamples.length > HomeState.maxSamples) {
        state.headingSamples.removeAt(0);
      }

      state.accuracyNotifier.value = accuracy;

      if (state.headingSamples.length == 1) {
        state.filteredHeading = heading;
        state.headingNotifier.value = heading;
      }
    });
  }

  // ----------------------------------------------------------------------
  // Расчёты навигации
  // ----------------------------------------------------------------------

  void _calculateWaypointData() {
    if (state.waypoint == null || state.gpsDataNotifier.value.latitude == null) {
      return;
    }

    final nowData = state.gpsDataNotifier.value;

    state.distanceToWaypoint.value = calculateDistance(
      state.waypoint!.latitude!,
      state.waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
    );

    final trueBearing = calculateTrueBearing(
      state.waypoint!.latitude!,
      state.waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
    );

    state.bearingToWaypoint.value =
        (trueBearing - state.magneticDeclination + 360) % 360;
  }

  void _calculateTargetData() {
    if (state.target == null || state.gpsDataNotifier.value.latitude == null) {
      return;
    }

    final nowData = state.gpsDataNotifier.value;

    state.distanceToTarget.value = calculateDistance(
      nowData.latitude!,
      nowData.longitude!,
      state.target!['latitude']!,
      state.target!['longitude']!,
    );

    final trueBearing = calculateTrueBearing(
      nowData.latitude!,
      nowData.longitude!,
      state.target!['latitude']!,
      state.target!['longitude']!,
    );

    state.bearingToTarget.value =
        (trueBearing - state.magneticDeclination + 360) % 360;
  }

  // ----------------------------------------------------------------------
  // --- Работа с логами и контрольными точками --------------------------
  // ----------------------------------------------------------------------

  Future<void> _loadLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? logJson = prefs.getString('log_items');

    if (mounted) {
      setState(() {
        if (logJson != null) {
          try {
            final List<dynamic> decodedList = jsonDecode(logJson);
            state.logItems = decodedList.map((e) => logItemFromJson(e)).toList();
          } catch (e) {
            state.logItems = [];
          }
        } else {
          state.logItems = [];
        }
      });
    }
  }

  Future<void> loadLogEntries() async {
    await _loadLogEntries();
  }

  Future<void> _saveLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'log_items',
      jsonEncode(state.logItems.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> setWaypoint() async {
    final currentGpsData = state.gpsDataNotifier.value;
    if (currentGpsData.latitude == null || currentGpsData.longitude == null) {
      return;
    }

    await _loadLogEntries();

    final lastIncompleteEntry = state.logItems.lastWhereOrNull(
      (item) => item is LogEntry && item.distance == null,
    ) as LogEntry?;

    if (lastIncompleteEntry != null) {
      final distance = calculateDistance(
        lastIncompleteEntry.latitude,
        lastIncompleteEntry.longitude,
        currentGpsData.latitude!,
        currentGpsData.longitude!,
      );

      final bearing = calculateTrueBearing(
        lastIncompleteEntry.latitude,
        lastIncompleteEntry.longitude,
        currentGpsData.latitude!,
        currentGpsData.longitude!,
      );

      lastIncompleteEntry.distance = distance;
      lastIncompleteEntry.bearing =
          (bearing - state.magneticDeclination + 360) % 360;
    }

    final existingTrackEntries = state.logItems.whereType<LogEntry>();
    final newId = existingTrackEntries.isEmpty
        ? 1
        : existingTrackEntries.map((e) => e.id).reduce(math.max) + 1;

    final newEntry = LogEntry(
      id: newId,
      latitude: currentGpsData.latitude!,
      longitude: currentGpsData.longitude!,
    );

    setState(() {
      state.logItems.add(newEntry);
      state.waypoint = currentGpsData;
    });

    await _saveLogEntries();
  }

  Future<void> clearWaypoint() async {
    await _loadLogEntries();

    final lastIncompleteEntry = state.logItems.lastWhereOrNull(
      (item) => item is LogEntry && item.distance == null,
    ) as LogEntry?;

    if (lastIncompleteEntry == null) {
      setState(() {
        state.waypoint = null;
        state.distanceToWaypoint.value = null;
        state.bearingToWaypoint.value = null;
      });
      return;
    }

    final currentGpsData = state.gpsDataNotifier.value;
    if (currentGpsData.latitude == null || currentGpsData.longitude == null) {
      return;
    }

    final distance = calculateDistance(
      lastIncompleteEntry.latitude,
      lastIncompleteEntry.longitude,
      currentGpsData.latitude!,
      currentGpsData.longitude!,
    );

    final bearing = calculateTrueBearing(
      lastIncompleteEntry.latitude,
      lastIncompleteEntry.longitude,
      currentGpsData.latitude!,
      currentGpsData.longitude!,
    );

    lastIncompleteEntry.distance = distance;
    lastIncompleteEntry.bearing =
        (bearing - state.magneticDeclination + 360) % 360;

    await _saveLogEntries();

    setState(() {
      state.waypoint = null;
      state.distanceToWaypoint.value = null;
      state.bearingToWaypoint.value = null;
    });
  }

  void clearTarget() {
    setState(() {
      state.target = null;
      state.distanceToTarget.value = null;
      state.bearingToTarget.value = null;
    });
  }

  Future<void> addTargetCreationLogEntry({
    required double baseLatitude,
    required double baseLongitude,
    required double azimuth,
    required double distance,
    required double targetLatitude,
    required double targetLongitude,
  }) async {
    await _loadLogEntries();

    final newId = state.logItems.whereType<TargetCreationLogEntry>().isNotEmpty
        ? state.logItems
                .whereType<TargetCreationLogEntry>()
                .map((e) => e.id)
                .reduce(math.max) +
            1
        : 1;

    final entry = TargetCreationLogEntry(
      id: newId,
      baseLatitude: baseLatitude,
      baseLongitude: baseLongitude,
      azimuth: azimuth,
      distance: distance,
      targetLatitude: targetLatitude,
      targetLongitude: targetLongitude,
    );

    setState(() => state.logItems.add(entry));
    await _saveLogEntries();
  }

  void setTarget(Map<String, double>? target) {
    setState(() {
      state.target = target;
    });
  }

  void setTargetCalculationStartPoint(GpsData gpsData) {
    state.targetCalculationStartPoint = gpsData;
  }

  // ----------------------------------------------------------------------
  // --- Сервисная информация и цвета ------------------------------------
  // ----------------------------------------------------------------------

  String getAccuracyText(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return 'Низкая (калибруйте)';
      case 1:
        return 'Средняя';
      case 2:
        return 'Высокая';
      case 3:
        return 'Отличная';
      default:
        return 'Неизвестно';
    }
  }

  Color getAccuracyStatusColor(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String getCardinalDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'Север';
    if (heading >= 22.5 && heading < 67.5) return 'С-Восток';
    if (heading >= 67.5 && heading < 112.5) return 'Восток';
    if (heading >= 112.5 && heading < 157.5) return 'Ю-Восток';
    if (heading >= 157.5 && heading < 202.5) return 'Юг';
    if (heading >= 202.5 && heading < 247.5) return 'Ю-Запад';
    if (heading >= 247.5 && heading < 292.5) return 'Запад';
    if (heading >= 292.5 && heading < 337.5) return 'С-Запад';
    return '--';
  }
}
