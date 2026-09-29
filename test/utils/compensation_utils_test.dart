import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/compensation_utils.dart';

void main() {
  group('updateCompensationEma', () {
    test('один шаг: 0.9*current + 0.1*(delta*0.5)', () {
      // 1500*0.9 + (2500*0.5)*0.1 = 1350 + 125 = 1475
      expect(updateCompensationEma(1500, 2500), closeTo(1475, 1e-9));
    });

    test('сходится к delta * 0.5 при стабильном входе', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 2000);
      }
      // delta = 2000, цель = 1000
      expect(x, closeTo(1000, 1.0));
    });

    test('регрессия: не сходится к полной delta', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 2000);
      }
      expect(x, lessThan(1500));
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
      // delta = 5000, цель = 2500. До 3000 не доходит.
      // Проверяем, что clamp не мешает.
      expect(x, closeTo(2500, 1.0));
    });

    test('верхний предел 3000 с большим delta', () {
      double x = 1500;
      for (int i = 0; i < 200; i++) {
        x = updateCompensationEma(x, 20000);
      }
      // delta = 20000, цель = 10000. Clamp обрежет до 3000.
      expect(x, closeTo(3000, 1.0));
    });
  });
}