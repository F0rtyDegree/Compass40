import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/user_path_utils.dart';

void main() {
  group('pruneUserPath', () {
    test('короткий путь возвращается без изменений', () {
      final path = List.generate(100, (i) => Offset(i.toDouble(), 0));
      final jumps = [10, 50];
      final result = pruneUserPath(
        path: path,
        jumpIndices: jumps,
        maxPoints: 5000,
      );
      expect(result.path, same(path));
      expect(result.jumpIndices, same(jumps));
    });

    test('путь ровно maxPoints не прореживается', () {
      final path = List.generate(5000, (i) => Offset(i.toDouble(), 0));
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [],
        maxPoints: 5000,
      );
      expect(result.path.length, 5000);
    });

    test('путь maxPoints+1 прореживается, длина падает', () {
      final path = List.generate(5001, (i) => Offset(i.toDouble(), 0));
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [],
        maxPoints: 5000,
      );
      expect(result.path.length, lessThan(5001));
    });

    test('последняя точка сохраняется', () {
      final path = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [],
        maxPoints: 5000,
      );
      expect(result.path.last, path.last);
    });

    test('первая точка сохраняется', () {
      final path = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [],
        maxPoints: 5000,
      );
      expect(result.path.first, path.first);
    });

    test('индексы прыжков пересчитаны корректно', () {
      final path = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      // Прыжок на старой позиции 0 и 3000.
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [0, 3000],
        maxPoints: 5000,
      );
      // Старый индекс 0 сохраняется (первая точка) → новый индекс 0.
      // Старый индекс 3000 во второй половине (half=3000) → первый элемент второй половины.
      expect(result.jumpIndices, contains(0));
      // Первая половина: 1500 элементов. Значит 3000 станет 1500.
      expect(result.jumpIndices, contains(1500));
    });

    test('прыжок на прореженной точке исчезает', () {
      final path = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      // Индекс 1 (нечётный в первой половине) — прореживается.
      final result = pruneUserPath(
        path: path,
        jumpIndices: const [1],
        maxPoints: 5000,
      );
      expect(result.jumpIndices, isEmpty);
    });
  });
}