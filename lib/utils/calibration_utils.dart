/// Определяет, устарела ли калибровка магнитного компаса.
///
/// Калибровка считается устаревшей, если средняя магнитуда поля
/// после вычитания офсетов сильно отличается от магнитуды,
/// зафиксированной при последней успешной калибровке.
///
/// [isCalibrated] — есть ли активная калибровка.
/// [calibMagnitude] — магнитуда поля (μT) на момент калибровки.
/// [avgMagnitude] — текущее усреднённое значение магнитуды.
/// [bufferLength] — сколько значений накоплено в буфере.
/// [bufferSize] — размер буфера (должен быть заполнен полностью).
/// [relativeThreshold] — относительный порог отклонения (по умолчанию 0.30).
/// [minMagnitude] — нижняя граница нормы (μT).
/// [maxMagnitude] — верхняя граница нормы (μT).
bool isCalibrationStale({
  required bool isCalibrated,
  required double calibMagnitude,
  required double avgMagnitude,
  required int bufferLength,
  required int bufferSize,
  double relativeThreshold = 0.30,
  double minMagnitude = 20.0,
  double maxMagnitude = 80.0,
}) {
  if (!isCalibrated) return false;
  if (calibMagnitude <= 0) return false;
  if (bufferLength < bufferSize) return false;

  final relDiff = (avgMagnitude - calibMagnitude).abs() / calibMagnitude;
  if (relDiff > relativeThreshold) return true;
  if (avgMagnitude < minMagnitude) return true;
  if (avgMagnitude > maxMagnitude) return true;
  return false;
}