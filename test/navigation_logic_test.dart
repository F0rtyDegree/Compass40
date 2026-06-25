import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/geo_utils.dart';
import 'package:compass40/utils/angle_utils.dart';
import 'package:compass40/services/map_calibration_service.dart';

void main() {
  group('Чистая геометрия (geo_utils)', () {
    test('расстояние между одинаковыми точками равно 0', () {
      const lat = 53.9056;
      const lon = 27.5633;
      final distance = calculateDistance(lat, lon, lat, lon);
      expect(distance, closeTo(0, 0.01));
    });

    test('истинный азимут строго на Восток равен 90° (неоспоримый факт)', () {
      const lat1 = 53.9000;
      const lon1 = 27.5500;
      const lat2 = 53.9000; // Широта та же
      const lon2 = 27.5600; // Долгота больше (Восток)

      final bearing = calculateTrueBearing(lat1, lon1, lat2, lon2);
      expect(bearing, closeTo(90.0, 0.1));
    });

    test('круговая медиана корректно обрабатывает переход через 360°', () {
      final angles = [350.0, 5.0, 10.0];
      final median = calculateCircularMedian(angles);
      expect(median, closeTo(5.0, 2.0));
    });
  });

  group('Бизнес-логика навигации (MapCalibrationService)', () {
    test('расчет азимута и расстояния с учетом магнитного склонения (Минск)', () {
      final service = MapCalibrationService();

      const fromLat = 53.91414;
      const fromLon = 27.55329;
      const toLat = 53.92301;
      const toLon = 27.55567;
      const magneticDeclination = 9.0;

      final result = service.bearingAndDistance(
        fromLat: fromLat,
        fromLon: fromLon,
        toLat: toLat,
        toLon: toLon,
        magneticDeclination: magneticDeclination,
      );

      const expectedDistanceMeters = 1000.0;
      const expectedTrueBearing = 9.0;

      // Проверяем расстояние (с допуском 15 метров)
      expect(result.distanceMeters, closeTo(expectedDistanceMeters, 15));

      // Проверяем истинный азимут (с допуском 0.5 градуса)
      expect(result.trueBearing, closeTo(expectedTrueBearing, 0.5));

      // Проверяем магнитный азимут С УЧЕТОМ ЦИКЛИЧНОСТИ (0° и 360° это одно и то же)
      // Из-за погрешности float результат может быть 0.02 или 359.98
      final diffFromZero = (result.magneticBearing - 0.0).abs();
      final diffFrom360 = (result.magneticBearing - 360.0).abs();
      final isCloseToNorth = diffFromZero < 0.5 || diffFrom360 < 0.5;

      expect(
        isCloseToNorth,
        isTrue,
        reason:
            'Ожидался магнитный азимут около 0.0° или 360.0°, но получен ${result.magneticBearing}°',
      );
    });
  });

  group('Бизнес-логика: Порядок аргументов (ОТ КП vs НА ЦЕЛЬ)', () {
    test('ВЕДЕНИЕ НА ЦЕЛЬ: азимут считается ОТ пользователя К цели', () {
      // Пользователь находится южнее цели
      const userLat = 53.9000;
      const userLon = 27.5500;
      const targetLat = 53.9100; // Цель строго на Север от пользователя
      const targetLon = 27.5500;

      // Функция должна вызываться: (откуда, куда)
      final bearing = calculateTrueBearing(
        userLat,
        userLon,
        targetLat,
        targetLon,
      );

      // Ожидаем 0° (Север), так как цель находится на Севере от нас
      expect(bearing, closeTo(0.0, 0.5));
    });

    test('СОПРОВОЖДЕНИЕ ОТ КП: азимут считается ОТ КП К пользователю', () {
      // КП находится севернее пользователя
      const kpLat = 53.9100; // КП строго на Север от пользователя
      const kpLon = 27.5500;
      const userLat = 53.9000;
      const userLon = 27.5500;

      // В коде (home_logic.dart:239) вызов именно такой: (КП, Пользователь)
      final bearing = calculateTrueBearing(kpLat, kpLon, userLat, userLon);

      // Ожидаем 180° (Юг), так как мы находимся на Юге от КП.
      // Это означает, что стрелка "ОТ КП" будет указывать назад, на Юг.
      expect(bearing, closeTo(180.0, 0.5));
    });

    test(
      'Защита от перепутанных аргументов: НА ЦЕЛЬ и ОТ КП дают разницу ~180°',
      () {
        const pointALat = 53.9000;
        const pointALon = 27.5500;
        const pointBLat = 53.9050;
        const pointBLon = 27.5550;

        final bearingAtoB = calculateTrueBearing(
          pointALat,
          pointALon,
          pointBLat,
          pointBLon,
        );
        final bearingBtoA = calculateTrueBearing(
          pointBLat,
          pointBLon,
          pointALat,
          pointALon,
        );

        // Разница между прямым и обратным азимутом должна быть около 180 градусов
        double diff = (bearingAtoB - bearingBtoA).abs();
        if (diff > 180) diff = 360 - diff; // Учет цикличности

        expect(diff, closeTo(180.0, 1.0));
      },
    );
  });
}
