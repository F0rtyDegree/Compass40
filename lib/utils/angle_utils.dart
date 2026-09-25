/// Приводит азимут к диапазону [0, 360), где 360 становится 0.
/// Обрабатывает как положительные, так и отрицательные входные значения.
double normalizeBearing(double bearing) {
  // Оператор % в Dart может вернуть отрицательный результат.
  final result = bearing % 360;
  return result < 0 ? result + 360 : result;
}

/// Переводит истинный азимут в магнитный.
/// Магнитный = истинный − склонение, с приведением к [0, 360).
double trueToMagneticBearing(double trueBearing, double declination) {
  return normalizeBearing(trueBearing - declination);
}


double calculateCircularMedianSync(List<double> angles) {
  if (angles.isEmpty) return 0.0;
  if (angles.length == 1) return angles.first;

  final sorted = List<double>.from(angles)..sort();
  final n = sorted.length;

  double maxGap = 0;
  int maxGapIndex = -1;
  for (int i = 0; i < n - 1; i++) {
    final gap = sorted[i + 1] - sorted[i];
    if (gap > maxGap) {
      maxGap = gap;
      maxGapIndex = i;
    }
  }
  final wrapGap = (sorted.first + 360) - sorted.last;
  if (wrapGap > maxGap) {
    maxGap = wrapGap;
    maxGapIndex = n - 1;
  }

  List<double> ordered = sorted;
  if (maxGap > 180 && maxGapIndex != -1) {
    final startIndex = (maxGapIndex + 1) % n;
    ordered = List<double>.generate(
      n,
      (i) => sorted[(startIndex + i) % n],
    );
  }

  if (n % 2 == 1) {
    return ordered[n ~/ 2];
  } else {
    final m1 = ordered[n ~/ 2 - 1];
    final m2 = ordered[n ~/ 2];
    if ((m2 - m1).abs() > 180) {
      final avg = (m1 + m2 + 360) / 2;
      return avg >= 360 ? avg - 360 : avg;
    }
    return (m1 + m2) / 2;
  }
}

/// Форматирует азимут для отображения. Округляет до целого
/// и преобразурует 360 в 0, добавляя знак градуса.
String formatBearing(double bearing) {
  // Округление может дать 360 (например, для 359.8),
  // поэтому используем остаток от деления, чтобы получить 0.
  return '${bearing.round() % 360}°';
}