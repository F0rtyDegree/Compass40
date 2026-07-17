// ignore_for_file: avoid_print

import 'dart:io';
import 'package:flutter/foundation.dart';

// Эта функция выполняется в изоляте.
// Она БОЛЬШЕ НЕ запрашивает разрешения. Предполагается, что они уже есть.
Future<void> _writeLogInternal(String message) async {
  try {
    print('writeLog (isolate): entry');

    Directory? downloadsDir;
    if (Platform.isAndroid) {
      downloadsDir = Directory('/storage/emulated/0/Download');
      if (!await downloadsDir.exists()) {
        downloadsDir = Directory('/sdcard/Download'); // Fallback
      }
    } else {
      print('writeLog (isolate): Not on Android, exiting.');
      return;
    }

    if (!await downloadsDir.exists()) {
      print('writeLog (isolate): Download directory not found.');
      return;
    }

    const String folderName = 'Compass40';
    final compassDir = Directory('${downloadsDir.path}/$folderName');
    if (!await compassDir.exists()) {
      await compassDir.create(recursive: true);
    }

    const String logFileName = 'compass_log.txt';
    final file = File('${compassDir.path}/$logFileName');
    
    // Используем append, так как файл уже очищен при инициализации
    final timestamp = DateTime.now().toIso8601String().replaceFirst('T', ' ');
    final logLine = '$timestamp  $message\n';

    await file.writeAsString(logLine, mode: FileMode.append);
    print('writeLog (isolate): exit');
  } catch (e) {
    print('writeLog (isolate) ERROR: $e');
  }
}

class FileLogger {
  static bool _initialized = false;

  /// Инициализировать лог-файл: удалить старый и создать новый.
  /// Вызывать один раз при запуске приложения.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      Directory? downloadsDir;
      if (Platform.isAndroid) {
        downloadsDir = Directory('/storage/emulated/0/Download');
        if (!await downloadsDir.exists()) {
          downloadsDir = Directory('/sdcard/Download');
        }
      }
      if (downloadsDir == null || !await downloadsDir.exists()) {
        print('FileLogger.init: Download directory not found.');
        return;
      }

      const String folderName = 'Compass40';
      final compassDir = Directory('${downloadsDir.path}/$folderName');
      if (!await compassDir.exists()) {
        await compassDir.create(recursive: true);
      }

      final file = File('${compassDir.path}/compass_log.txt');
      if (await file.exists()) {
        await file.delete();
      }
      await file.create(recursive: true);
      _initialized = true;
      print('FileLogger.init: log file cleared');
    } catch (e) {
      print('FileLogger.init ERROR: $e');
    }
  }

  /// Записать сообщение в лог-файл.
  /// Файл должен быть предварительно инициализирован через [init].
  static void writeLog(String message) {
    compute(_writeLogInternal, message);
  }
}