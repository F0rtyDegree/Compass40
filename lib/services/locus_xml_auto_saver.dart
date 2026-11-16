// ignore_for_file: avoid_print

import 'dart:io';
import '../models/map_project.dart';
import '../utils/app_constants.dart';
import 'locus_calibration_service.dart';

class LocusXmlAutoSaver {
  static Future<void> save(MapProject project) async {
    if (project.imagePath.isEmpty) return;
    final photoPath = project.originalImagePath ?? project.imagePath;
    final imageName = photoPath.split('/').last;
    final dotIndex = imageName.lastIndexOf('.');
    final nameWithoutExt =
        dotIndex > 0 ? imageName.substring(0, dotIndex) : imageName;

    // Пытаемся сохранить XML рядом с изображением карты.
    // Если не удаётся (нет прав, директория недоступна) — fallback
    // в Download/Compass40.
    final photoDir = Directory(photoPath).parent.path;
    final primaryPath = '$photoDir/$nameWithoutExt.xml';
    final fallbackPath =
        '${AppConstants.externalDownloadDir}/${AppConstants.compassFolderName}/$nameWithoutExt.xml';

    for (final xmlPath in [primaryPath, fallbackPath]) {
      try {
        await LocusCalibrationService.saveCalibration(
          outputPath: xmlPath,
          photoPath: photoPath,
          anchors: project.anchors,
        );
        return; // Успешно сохранили — выходим.
      } catch (e) {
        print('Попытка сохранения XML в $xmlPath не удалась: $e');
      }
    }
    print('Не удалось сохранить XML ни в одну из директорий');
  }
}