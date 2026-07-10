import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/controllers/map_screen_logic.dart';

void main() {
  group('computeResetRotation', () {
    const declinationRad = 9 * math.pi / 180; // 9°

    test('режим P: север вверху', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: -math.pi / 2, // магнитный север вверх
        photoSeverLinePixels: 100,
        declinationRad: declinationRad,
      );
      // Ожидаем: -π/2 - (-π/2) = 0
      expect(result, closeTo(0.0, 1e-9));
    });

    test('режим P: север внизу', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: math.pi / 2,
        photoSeverLinePixels: 100,
        declinationRad: declinationRad,
      );
      // Ожидаем: -π/2 - π/2 = -π
      expect(result, closeTo(-math.pi, 1e-9));
    });

    test('режим P: север слева', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: math.pi,
        photoSeverLinePixels: 100,
        declinationRad: declinationRad,
      );
      // Ожидаем: -π/2 - π = -3π/2, что эквивалентно π/2
      final normalized = result % (2 * math.pi);
      expect(normalized, closeTo(math.pi / 2, 1e-9));
    });

    test('режим P: север справа', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: 0.0,
        photoSeverLinePixels: 100,
        declinationRad: declinationRad,
      );
      // Ожидаем: -π/2 - 0 = -π/2
      expect(result, closeTo(-math.pi / 2, 1e-9));
    });

    test('обычный режим A/F/N с mapRotation', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0.8,
        photoSeverNorthAngle: 0,
        photoSeverLinePixels: 0,
        declinationRad: declinationRad,
      );
      expect(result, closeTo(0.8, 1e-9));
    });
  });
}