// ignore_for_file: avoid_print

import 'dart:io';
import '../utils/app_constants.dart';

class FileLogger {
  static bool _initialized = false;

  /// Инициализировать лог-файл: удалить старый и создать новый.
  /// Вызывать один раз при запуске приложения.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory(AppConstants.externalDownloadDir);
        if (!await downloadsDir.exists()) {
          downloadsDir = Directory(AppConstants.externalDownloadFallback);
        }
      }
      if (downloadsDir == null || !await downloadsDir.exists()) {
        print('FileLogger.init: Download directory not found.');
        return;
      }

      final compassDir =
          Directory('${downloadsDir.path}/${AppConstants.compassFolderName}');
      if (!await compassDir.exists()) {
        await compassDir.create(recursive: true);
      }

      final file = File('${compassDir.path}/compass_log.txt');
      if (await file.exists()) {
        await file.delete();
      }
      await file.create(recursive: true);
      _initialized = true;
    } catch (e) {
      print('FileLogger.init ERROR: $e');
    }
  }

  /// Записать сообщение в лог-файл. Синхронно.
  /// Файл должен быть предварительно инициализирован через [init].
  static void writeLog(String message) {
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory(AppConstants.externalDownloadDir);
        if (!downloadsDir.existsSync()) {
          downloadsDir = Directory(AppConstants.externalDownloadFallback);
        }
      } else {
        return;
      }

      if (!downloadsDir.existsSync()) {
        return;
      }

      final compassDir =
          Directory('${downloadsDir.path}/${AppConstants.compassFolderName}');
      if (!compassDir.existsSync()) {
        compassDir.createSync(recursive: true);
      }

      final file = File('${compassDir.path}/compass_log.txt');
      final timestamp = DateTime.now().toIso8601String().replaceFirst('T', ' ');
      final logLine = '$timestamp  $message\n';
      file.writeAsStringSync(logLine, mode: FileMode.append);
    } catch (e) {
      print('writeLog ERROR: $e');
    }
  }
}