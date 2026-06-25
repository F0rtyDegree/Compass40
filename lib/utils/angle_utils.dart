/// Приводит азимут к диапазону [0, 360), где 360 становится 0.
/// Обрабатывает как положительные, так и отрицательные входные значения.
double normalizeBearing(double bearing) {
  // Оператор % в Dart может вернуть отрицательный результат.
  final result = bearing % 360;
  return result < 0 ? result + 360 : result;
}

/// Вычисляет круговую медиану для списка углов (в градусах).
double calculateCircularMedian(List<double> angles) {
  if (angles.isEmpty) return 0.0;
  if (angles.length == 1) return normalizeBearing(angles.first);

  final sorted = List<double>.from(angles)..sort();
  final n = sorted.length;
  
  double maxGap = 0;
  int gapIndex = 0;
  
  // Находим самый большой разрыв между углами, чтобы "разрезать" круг
  for (int i = 0; i < n; i++) {
    final current = sorted[i];
    final next = sorted[(i + 1) % n];
    // Используем normalizeBearing для корректного расчета разрыва через 0/360
    double gap = normalizeBearing(next - current);
    
    if (gap > maxGap) {
      maxGap = gap;
      gapIndex = i;
    }
  }
  
  // Перестраиваем список так, как будто он линеен
  final cutList = <double>[];
  for (int i = 0; i < n; i++) {
    final idx = (gapIndex + 1 + i) % n;
    double val = sorted[idx];
    if (idx <= gapIndex) {
      val += 360;
    }
    cutList.add(val);
  }
  
  // Находим обычную медиану в линеаризованном списке
  double median;
  if (n % 2 == 1) {
    median = cutList[n ~/ 2];
  } else {
    median = (cutList[n ~/ 2 - 1] + cutList[n ~/ 2]) / 2;
  }
  
  // Нормализуем результат обратно в диапазон [0, 360)
  return normalizeBearing(median);
}

/// Форматирует азимут для отображения. Округляет до целого
/// и преобразует 360 в 0, добавляя знак градуса.
String formatBearing(double bearing) {
  // Округление может дать 360 (например, для 359.8), 
  // поэтому используем остаток от деления, чтобы получить 0.
  return '${bearing.round() % 360}°';
}
