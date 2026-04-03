import 'dart:convert';
import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:gps_info/gps_info.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../log_entry.dart';
import '../utils/geo_utils.dart';

class LogService {
  Future<List<LogItem>> loadLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? logJson = prefs.getString('log_items');

    if (logJson != null) {
      try {
        final List<dynamic> decodedList = jsonDecode(logJson);
        return decodedList.map((e) => logItemFromJson(e)).toList();
      } catch (e) {
        return [];
      }
    }

    return [];
  }

  Future<void> saveLogEntries(List<LogItem> logItems) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'log_items',
      jsonEncode(logItems.map((e) => e.toJson()).toList()),
    );
  }

  Future<SetWaypointResult?> setWaypoint({
    required List<LogItem> currentLogItems,
    required GpsData currentGpsData,
    required double magneticDeclination,
  }) async {
    if (currentGpsData.latitude == null || currentGpsData.longitude == null) {
      return null;
    }

    final logItems = await loadLogEntries();

    final lastIncompleteEntry = logItems.lastWhereOrNull(
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
          (bearing - magneticDeclination + 360) % 360;
    }

    final existingTrackEntries = logItems.whereType<LogEntry>();
    final newId = existingTrackEntries.isEmpty
        ? 1
        : existingTrackEntries.map((e) => e.id).reduce(math.max) + 1;

    final newEntry = LogEntry(
      id: newId,
      latitude: currentGpsData.latitude!,
      longitude: currentGpsData.longitude!,
    );

    logItems.add(newEntry);
    await saveLogEntries(logItems);

    return SetWaypointResult(
      logItems: logItems,
      waypoint: currentGpsData,
    );
  }

  Future<ClearWaypointResult> clearWaypoint({
    required List<LogItem> currentLogItems,
    required GpsData currentGpsData,
    required double magneticDeclination,
  }) async {
    final logItems = await loadLogEntries();

    final lastIncompleteEntry = logItems.lastWhereOrNull(
      (item) => item is LogEntry && item.distance == null,
    ) as LogEntry?;

    if (lastIncompleteEntry == null) {
      return ClearWaypointResult(
        logItems: logItems,
        waypoint: null,
        clearedOnly: true,
      );
    }

    if (currentGpsData.latitude == null || currentGpsData.longitude == null) {
      return ClearWaypointResult(
        logItems: currentLogItems,
        waypoint: null,
        clearedOnly: true,
      );
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
    lastIncompleteEntry.bearing = (bearing - magneticDeclination + 360) % 360;

    await saveLogEntries(logItems);

    return ClearWaypointResult(
      logItems: logItems,
      waypoint: null,
      clearedOnly: true,
    );
  }

  Future<List<LogItem>> addTargetCreationLogEntry({
    required List<LogItem> currentLogItems,
    required double baseLatitude,
    required double baseLongitude,
    required double azimuth,
    required double distance,
    required double targetLatitude,
    required double targetLongitude,
  }) async {
    final logItems = await loadLogEntries();

    final newId = logItems.whereType<TargetCreationLogEntry>().isNotEmpty
        ? logItems
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

    logItems.add(entry);
    await saveLogEntries(logItems);
    return logItems;
  }
}

class SetWaypointResult {
  final List<LogItem> logItems;
  final GpsData waypoint;

  SetWaypointResult({
    required this.logItems,
    required this.waypoint,
  });
}

class ClearWaypointResult {
  final List<LogItem> logItems;
  final GpsData? waypoint;
  final bool clearedOnly;

  ClearWaypointResult({
    required this.logItems,
    required this.waypoint,
    required this.clearedOnly,
  });
}
