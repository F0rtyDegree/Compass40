
import 'package:flutter/foundation.dart';

/// Приводит азимут к диапазону [0, 360), где 360 становится 0.
/// Обрабатывает как положительные, так и отрицательные входные значения.
double normalizeBearing(double bearing) {
  // Оператор % в Dart может вернуть отрицательный результат.
  final result = bearing % 360;
  return result < 0 ? result + 360 : result;
}


Future<double> calculateCircularMedian(List<double> angles) async {
  // Выносим в изолят, если вдруг список будет большим
  return await compute(_calculateCircularMedian, angles);
}


double _calculateCircularMedian(List<double> angles) {
  if (angles.isEmpty) {
    return 0.0;
  }
  
  final n = angles.length;
  if (n == 1) {
    return angles.first;
  }

  // Сортируем углы, чтобы найти разрывы
  angles.sort();

  // Ищем самый большой разрыв между соседними углами.
  // Этот разрыв, скорее всего, является точкой перехода 359° -> 0°
  double maxGap = 0;
  int maxGapIndex = -1;

  for (int i = 0; i < n - 1; i++) {
    final gap = angles[i + 1] - angles[i];
    if (gap > maxGap) {
      maxGap = gap;
      maxGapIndex = i;
    }
  }
  // Также проверяем разрыв между последним и первым элементом (переход через 360)
  final wrapAroundGap = (angles.first + 360) - angles.last;
  if (wrapAroundGap > maxGap) {
    maxGap = wrapAroundGap;
    maxGapIndex = n - 1; // Разрыв между последним и первым
  }

  // "Поворачиваем" массив, чтобы он стал непрерывной последовательностью
  List<double> sortedCircular = List.from(angles);
  if (maxGap > 180 && maxGapIndex != -1) {
    final startIndex = (maxGapIndex + 1) % n;
    sortedCircular = [];
    for (int i = 0; i < n; i++) {
      sortedCircular.add(angles[(startIndex + i) % n]);
    }
  }

  // Теперь, когда массив отсортирован по-круговому, находим медиану
  if (n % 2 == 1) {
    // Для нечетного количества, это просто средний элемент
    return sortedCircular[n ~/ 2];
  } else {
    // Для четного, это средняя точка между двумя центральными элементами
    final m1 = sortedCircular[n ~/ 2 - 1];
    double m2 = sortedCircular[n ~/ 2];

    // Вычисляем среднюю точку по кратчайшей дуге
    double median;
    final diff = (m2 - m1).abs();
    if (diff > 180) {
      // Если дуга > 180, идем через 0/360
      final avg = (m1 + m2 + 360) / 2;
      median = avg >= 360 ? avg - 360 : avg;
    } else {
      median = (m1 + m2) / 2;
    }
    return median;
  }
}


/// Форматирует азимут для отображения. Округляет до целого
/// и преобразурует 360 в 0, добавляя знак градуса.
String formatBearing(double bearing) {
  // Округление может дать 360 (например, для 359.8),
  // поэтому используем остаток от деления, чтобы получить 0.
  return '${bearing.round() % 360}°';
}
