import 'dart:io';
import 'package:path_provider/path_provider.dart';

Future<int> getDirectorySize(Directory dir) async {
  int total = 0;
  if (!await dir.exists()) return 0;
  await for (final entity in dir.list(recursive: true, followLinks: false)) {
    if (entity is File) {
      try {
        total += await entity.length();
      } catch (_) {}
    }
  }
  return total;
}

Future<double> getTotalAppStorageMB() async {
  final docDir = await getApplicationDocumentsDirectory();
  final cacheDir = await getTemporaryDirectory();
  final docSize = await getDirectorySize(docDir);
  final cacheSize = await getDirectorySize(cacheDir);
  return (docSize + cacheSize) / (1024 * 1024);
}