import 'dart:ui';
import 'package:xml/xml.dart';

/// Парсит GPX-файл. Берёт первый `trk`, объединяет все `trkseg` в один список.
/// Возвращает список точек: dx = долгота, dy = широта.
/// Пустой список — если трек не найден или файл повреждён.
List<Offset> parseTrackFromGpx(String xmlString) {
  try {
    final document = XmlDocument.parse(xmlString);
    final trk = document.findAllElements('trk').firstOrNull;
    if (trk == null) return [];

    final result = <Offset>[];
    for (final trkpt in trk.findAllElements('trkpt')) {
      final latStr = trkpt.getAttribute('lat');
      final lonStr = trkpt.getAttribute('lon');
      if (latStr == null || lonStr == null) continue;
      final lat = double.tryParse(latStr);
      final lon = double.tryParse(lonStr);
      if (lat == null || lon == null) continue;
      result.add(Offset(lon, lat));
    }
    return result;
  } catch (_) {
    return [];
  }
}