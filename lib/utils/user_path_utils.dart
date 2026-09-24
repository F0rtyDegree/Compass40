import 'dart:ui';

/// Прореживает путь пользователя, если его длина превышает [maxPoints].
///
/// Схема: первая половина точек разрежается (берётся каждая вторая),
/// вторая половина сохраняется полностью. Это ограничивает длину пути
/// без потери формы маршрута: старые участки теряют детализацию,
/// новые остаются плотными.
///
/// Индексы скачков ([jumpIndices]) пересчитываются под новый список.
({List<Offset> path, List<int> jumpIndices}) pruneUserPath({
  required List<Offset> path,
  required List<int> jumpIndices,
  int maxPoints = 5000,
}) {
  if (path.length <= maxPoints) {
    return (path: path, jumpIndices: jumpIndices);
  }

  final half = path.length ~/ 2;
  final jumpSet = jumpIndices.toSet();

  final newPath = <Offset>[];
  final newJumpIndices = <int>[];

  // Первая половина: каждая вторая точка.
  for (int i = 0; i < half; i += 2) {
    if (jumpSet.contains(i)) {
      newJumpIndices.add(newPath.length);
    }
    newPath.add(path[i]);
  }

  // Вторая половина: все точки.
  for (int i = half; i < path.length; i++) {
    if (jumpSet.contains(i)) {
      newJumpIndices.add(newPath.length);
    }
    newPath.add(path[i]);
  }

  return (path: newPath, jumpIndices: newJumpIndices);
}