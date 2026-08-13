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
    anchorEntries.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    for (int i = 0; i < anchorEntries.length; i++) {
      final entry = anchorEntries[i];
      final lat = entry.latitude.toStringAsFixed(6);
      final lon = entry.longitude.toStringAsFixed(6);
      // Берём дату из entry.timestamp (она корректная) и время из entry.timeStr
      final datePart = entry.timestamp
          .toUtc()
          .toIso8601String()
          .split('T')
          .first; // "2026-08-13"
      final timePart = entry.timeStr.split(' ').first; // "13:35:22.00309"
      // Разбираем локальное время (Минск, UTC+3)
      final parts = timePart.split(':');
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final seconds = int.parse(secParts[0]);
      final millis = int.parse(secParts[1].padRight(3, '0').substring(0, 3));
      // Создаём DateTime в локальном времени (без указания зоны, но мы знаем, что это UTC+3)
      final localDateTime = DateTime(
        int.parse(datePart.split('-')[0]),
        int.parse(datePart.split('-')[1]),
        int.parse(datePart.split('-')[2]),
        hours,
        minutes,
        seconds,
        millis,
      );
      // Переводим в UTC (вычитаем 3 часа)
      final utcDateTime = localDateTime.toUtc();
      final time = utcDateTime.toIso8601String();
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
