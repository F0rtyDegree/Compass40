import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/calibration_utils.dart';

void main() {
  group('isCalibrationStale', () {
    const size = 60;

    test('не откалиброван → false', () {
      expect(
        isCalibrationStale(
          isCalibrated: false,
          calibMagnitude: 50,
          avgMagnitude: 100,
          bufferLength: size,
          bufferSize: size,
        ),
        isFalse,
      );
    });

    test('calibMagnitude == 0 → false', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 0,
          avgMagnitude: 100,
          bufferLength: size,
          bufferSize: size,
        ),
        isFalse,
      );
    });

    test('буфер не заполнен → false', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 50,
          avgMagnitude: 100,
          bufferLength: 10,
          bufferSize: size,
        ),
        isFalse,
      );
    });

    test('магнитуда в пределах 30% → false', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 50,
          avgMagnitude: 60,
          bufferLength: size,
          bufferSize: size,
        ),
        isFalse,
      );
    });

    test('граница ровно 30% → false', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 50,
          avgMagnitude: 65,
          bufferLength: size,
          bufferSize: size,
        ),
        isFalse,
      );
    });

    test('превышение вверх более 30% → true', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 50,
          avgMagnitude: 66,
          bufferLength: size,
          bufferSize: size,
        ),
        isTrue,
      );
    });

    test('превышение вниз более 30% → true', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 50,
          avgMagnitude: 34,
          bufferLength: size,
          bufferSize: size,
        ),
        isTrue,
      );
    });

    test('avg < 20 μT → true', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 21,
          avgMagnitude: 19,
          bufferLength: size,
          bufferSize: size,
        ),
        isTrue,
      );
    });

    test('avg > 80 μT → true', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 82,
          avgMagnitude: 81,
          bufferLength: size,
          bufferSize: size,
        ),
        isTrue,
      );
    });

    test('сценарий из лога: 126 → 40 → true', () {
      expect(
        isCalibrationStale(
          isCalibrated: true,
          calibMagnitude: 126,
          avgMagnitude: 40,
          bufferLength: size,
          bufferSize: size,
        ),
        isTrue,
      );
    });
  });
}