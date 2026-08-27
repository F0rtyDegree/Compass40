import 'dart:io';
import '../log_entry.dart';

class GpxExportService {
  static Future<void> exportGpx({
    required List<LogItem> logItems,
    required List<(String time, double lat, double lon)> trackPoints,
    required String outputPath,
  }) async {
    final buffer = StringBuffer();

    buffer.writeln('<?xml version="1.0" encoding="UTF-8"?>');
    buffer.writeln('<gpx version="1.1" creator="Compass40">');

    // --- 1. Waypoints: КП (LogEntry) ---
    final kpEntries = logItems.whereType<LogEntry>().toList();
    for (int i = 0; i < kpEntries.length; i++) {
      final entry = kpEntries[i];
      final lat = entry.latitude.toStringAsFixed(6);
      final lon = entry.longitude.toStringAsFixed(6);
      final time = entry.timestamp.toUtc().toIso8601String();
      final name = 'КП${i + 1}';
      final desc = entry.distance != null && entry.bearing != null
          ? '${entry.distance!.round()}м ${entry.bearing!.round()}°'
          : '---';
      buffer.writeln('  <wpt lat="$lat" lon="$lon">');
      buffer.writeln('    <time>$time</time>');
      buffer.writeln('    <name>$name</name>');
      buffer.writeln('    <desc><![CDATA[$desc]]></desc>');
      buffer.writeln('  </wpt>');
    }

    // --- 2. Waypoints: Цели (TargetCreationLogEntry) ---
    final targetEntries = logItems.whereType<TargetCreationLogEntry>().toList();
    for (int i = 0; i < targetEntries.length; i++) {
      final entry = targetEntries[i];
      final lat = entry.targetLatitude.toStringAsFixed(6);
      final lon = entry.targetLongitude.toStringAsFixed(6);
      final time = entry.timestamp.toUtc().toIso8601String();
      final name = 'ЦЕЛЬ${i + 1}';
      final desc = '${entry.distance.round()}м ${entry.azimuth.round()}°';
      buffer.writeln('  <wpt lat="$lat" lon="$lon">');
      buffer.writeln('    <time>$time</time>');
      buffer.writeln('    <name>$name</name>');
      buffer.writeln('    <desc><![CDATA[$desc]]></desc>');
      buffer.writeln('  </wpt>');
    }

    // --- 2.5. Waypoints: Точки привязки (MapAnchorLogEntry) ---
    final anchorEntries = logItems.whereType<MapAnchorLogEntry>().toList();
    for (int i = 0; i < anchorEntries.length; i++) {
      final entry = anchorEntries[i];
      final lat = entry.latitude.toStringAsFixed(6);
      final lon = entry.longitude.toStringAsFixed(6);

      // Используем timestamp напрямую, так как timeStr удален
      final time = entry.timestamp.toUtc().toIso8601String();

      final name = 'ТП${i + 1}';
      String desc = '';
      if (entry.distanceFromPrevious != null) {
        desc = '${entry.distanceFromPrevious!.round()}м';
      }
      
      buffer.writeln('  <wpt lat="$lat" lon="$lon">');
      buffer.writeln('    <time>$time</time>');
      buffer.writeln('    <name>$name</name>');
      if (desc.isNotEmpty) {
        buffer.writeln('    <desc><![CDATA[$desc]]></desc>');
      }
      buffer.writeln('  </wpt>');
    }

    // --- 3. Трек (из CSV) ---
    if (trackPoints.isNotEmpty) {
      final fileName = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .replaceAll('.', '-');
      buffer.writeln('  <trk>');
      buffer.writeln('    <name>$fileName</name>');
      buffer.writeln('    <trkseg>');
      for (final (time, lat, lon) in trackPoints) {
        final latStr = lat.toStringAsFixed(6);
        final lonStr = lon.toStringAsFixed(6);
        buffer.writeln('      <trkpt lat="$latStr" lon="$lonStr">');
        buffer.writeln('        <time>$time</time>');
        buffer.writeln('      </trkpt>');
      }
      buffer.writeln('    </trkseg>');
      buffer.writeln('  </trk>');
    }

    buffer.writeln('</gpx>');

    final file = File(outputPath);
    await file.writeAsString(buffer.toString());
  }
}
