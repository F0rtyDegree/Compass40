import 'dart:io';
import 'package:xml/xml.dart';
import 'package:collection/collection.dart';
import '../models/map_anchor.dart';

class LocusImportResult {
  final String photoPath;
  final List<MapAnchor> anchors;

  LocusImportResult({required this.photoPath, required this.anchors});
}

class LocusCalibrationService {
  /// Сохраняет привязку в формате Locus XML.
  static Future<void> saveCalibration({
    required String outputPath,
    required String photoPath,
    required List<MapAnchor> anchors,
  }) async {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
    
    builder.element('map_calibration', nest: () {
      builder.element('photo', nest: photoPath);
      
      for (final anchor in anchors) {
        builder.element('point', nest: () {
          builder.attribute('x', anchor.imageX.toString());
          builder.attribute('y', anchor.imageY.toString());
          builder.attribute('lon', anchor.longitude.toString());
          builder.attribute('lat', anchor.latitude.toString());
        });
      }
    });

    final file = File(outputPath);
    await file.writeAsString(builder.buildDocument().toXmlString(pretty: true));
  }

  /// Загружает привязку из файла Locus XML.
  static Future<LocusImportResult?> loadCalibration(String xmlPath) async {
    final file = File(xmlPath);
    if (!await file.exists()) return null;

    try {
      final content = await file.readAsString();
      final doc = XmlDocument.parse(content);
      
      final photoElement = doc.findAllElements('photo').firstOrNull;
      final photoPath = photoElement?.innerText.trim();
      
      if (photoPath == null || photoPath.isEmpty) return null;

      final anchors = <MapAnchor>[];
      final points = doc.findAllElements('point');
      
      for (final p in points) {
        final x = double.tryParse(p.getAttribute('x') ?? '');
        final y = double.tryParse(p.getAttribute('y') ?? '');
        final lon = double.tryParse(p.getAttribute('lon') ?? '');
        final lat = double.tryParse(p.getAttribute('lat') ?? '');

        if (x != null && y != null && lon != null && lat != null) {
          anchors.add(MapAnchor(
            id: '${DateTime.now().millisecondsSinceEpoch}_${anchors.length}',
            imageX: x,
            imageY: y,
            latitude: lat,
            longitude: lon,
            createdAt: DateTime.now(),
          ));
        }
      }
      
      return LocusImportResult(photoPath: photoPath, anchors: anchors);
    } catch (e) {
      return null;
    }
  }
}