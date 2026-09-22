import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/compensation_utils.dart';

void main() {
  group('updateCompensationEma', () {
    test('один шаг: 0.9*current + 0.1*delta', () {
      expect(updateCompensationEma(1500, 2500), closeTo(1600, 1e-9));
    });

    test('сходится к delta при стабильном входе', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 2000);
      }
      expect(x, closeTo(2000, 1.0));
    });

    test('регрессия: не застревает на половине delta', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 2000);
      }
      expect(x, greaterThan(1900));
    });

    test('нижний предел 500', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 100);
      }
      expect(x, closeTo(500, 1e-9));
    });

    test('верхний предел 3000', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 5000);
      }
      expect(x, closeTo(3000, 1e-9));
    });
  });
}