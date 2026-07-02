import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/controllers/map_screen_logic.dart';

void main() {
  group('computeResetRotation', () {
    const declinationRad = 10 * math.pi / 180;
    test('режим P с истинным northAngle', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: 0.5, // некоторый истинный угол поворота
        photoSeverLinePixels: 100,
        declinationRad: declinationRad,
      );
      expect(result, closeTo(0.5 - declinationRad, 1e-9));
    });
    test('обычный режим F', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0.8,
        photoSeverNorthAngle: 0,
        photoSeverLinePixels: 0,
        declinationRad: declinationRad,
      );
      expect(result, closeTo(0.8 - declinationRad, 1e-9));
    });
    test('без калибровки', () {
      final result = MapScreenLogic.computeResetRotation(
        mapRotation: 0,
        photoSeverNorthAngle: 0,
        photoSeverLinePixels: 0,
        declinationRad: declinationRad,
      );
      expect(result, 0.0);
    });
  });
}