import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/angle_utils.dart';

void main() {
  group('calculateCircularMedianSync', () {
    test('пустой список → 0', () {
      expect(calculateCircularMedianSync([]), 0.0);
    });

    test('один элемент → он же', () {
      expect(calculateCircularMedianSync([42.0]), 42.0);
    });

    test('обычный диапазон, нечётное количество → средний', () {
      expect(calculateCircularMedianSync([10.0, 20.0, 30.0]), 20.0);
    });

    test('обычный диапазон, чётное количество → среднее двух', () {
      expect(calculateCircularMedianSync([10.0, 20.0, 30.0, 40.0]), 25.0);
    });

    test('переход через 360, нечётное количество → около 5', () {
      expect(calculateCircularMedianSync([350.0, 5.0, 10.0]), closeTo(5.0, 1.0));
    });

    test('переход через 360, чётное количество → около 0', () {
      expect(
        calculateCircularMedianSync([355.0, 0.0, 5.0, 10.0]),
        closeTo(2.5, 2.0),
      );
    });

    test('все около 0 → не сбивается на 180', () {
      final m = calculateCircularMedianSync([359.0, 1.0, 0.0]);
      expect(m, closeTo(0.0, 2.0));
    });

    test('регрессия: [350, 5, 10] не должно дать 10', () {
      final m = calculateCircularMedianSync([350.0, 5.0, 10.0]);
      expect(m, lessThan(10.0));
    });
  });
}