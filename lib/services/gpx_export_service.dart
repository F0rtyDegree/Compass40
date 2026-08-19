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
    // Фильтруем все записи журнала, оставляя только те, которые являются точками привязки карты (`MapAnchorLogEntry`).
    final anchorEntries = logItems.whereType<MapAnchorLogEntry>().toList();
    // Начинаем цикл для перебора каждой точки привязки.
    for (int i = 0; i < anchorEntries.length; i++) {
      // Получаем текущую запись (точку привязки).
      final entry = anchorEntries[i];
      // Преобразуем широту и долготу в строки с 6 знаками после запятой для точности.
      final lat = entry.latitude.toStringAsFixed(6);
      final lon = entry.longitude.toStringAsFixed(6);

      // --- Начало сложной обработки времени ---
      // Цель: собрать правильную временную метку в формате UTC, комбинируя дату из одного поля и время из другого.
      
      // 1. Извлекаем только ДАТУ из `timestamp`, преобразовав его в UTC и стандартный формат ISO 8601.
      final datePart = entry.timestamp
          .toUtc()
          .toIso8601String() // -> "2026-08-13T10:35:22.123Z"
          .split('T')      // -> ["2026-08-13", "10:35:22.123Z"]
          .first;         // -> "2026-08-13"

      // 2. Извлекаем только ВРЕМЯ из `timeStr`, которое является более точным, но может содержать доп. информацию.
      final timePart = entry.timeStr.split(' ').first; // -> "13:35:22.00309"
      
      // 3. Разбираем строку времени на компоненты: часы, минуты, секунды и миллисекунды.
      final parts = timePart.split(':');
      final hours = int.parse(parts[0]);
      final minutes = int.parse(parts[1]);
      final secParts = parts[2].split('.');
      final seconds = int.parse(secParts[0]);
      // Приводим миллисекунды к стандартной длине в 3 знака.
      final millis = int.parse(secParts[1].padRight(3, '0').substring(0, 3));
      
      // 4. Собираем новый объект DateTime, используя извлеченную ДАТУ и разобранное ВРЕМЯ.
      // Предполагается, что `timeStr` представляет локальное время.
      final localDateTime = DateTime(
        int.parse(datePart.split('-')[0]), // Год
        int.parse(datePart.split('-')[1]), // Месяц
        int.parse(datePart.split('-')[2]), // День
        hours,
        minutes,
        seconds,
        millis,
      );
      
      // 5. Преобразуем собранное локальное время в UTC, чтобы получить корректное время для GPX.
      final utcDateTime = localDateTime.toUtc();
      final time = utcDateTime.toIso8601String(); // Форматируем в стандарт ISO 8601.

      // --- Конец обработки времени ---

      // Создаем имя для точки, используя ее порядковый номер (ТП1, ТП2 и т.д.).
      final name = 'ТП${i + 1}';
      // Инициализируем пустое описание.
      String desc = '';
      // Если для точки рассчитано расстояние от предыдущей, добавляем его в описание.
      if (entry.distanceFromPrevious != null) {
        desc = '${entry.distanceFromPrevious!.round()}м';
      }
      
      // Записываем в буфер XML-структуру для путевой точки (waypoint).
      buffer.writeln('  <wpt lat="$lat" lon="$lon">');
      buffer.writeln('    <time>$time</time>');
      buffer.writeln('    <name>$name</name>');
      // Если описание не пустое, добавляем его в тег <desc>.
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
