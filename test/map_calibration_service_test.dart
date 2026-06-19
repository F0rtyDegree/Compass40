import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/models/map_anchor.dart';
import 'package:compass40/services/map_calibration_service.dart';

void main() {
  group(
    'MapCalibrationService - Точки привязки ВСЕГДА зеленые (activeAnchorIds)',
    () {
      late MapCalibrationService service;

      setUp(() {
        service = MapCalibrationService();
      });

      test('Режим A (Affine): 3 точки привязки зеленые', () {
        service.setCalibrationMode(CalibrationMode.affine);
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0),
          _anchor('2', 300, 100, 55.0, 37.002),
          _anchor('3', 100, 300, 55.002, 37.0),
        ];
        service.updateAnchors(anchors);

        final activeIds = service.activeAnchorIds;
        expect(
          activeIds,
          isNotNull,
          reason: 'В режиме A точки привязки не могут быть null',
        );
        expect(
          activeIds!.length,
          3,
          reason: 'Должно быть ровно 3 зеленых якоря',
        );
        expect(activeIds.containsAll(['1', '2', '3']), isTrue);
      });

      test('Режим F (Farthest): 2 точки рабочей пары зеленые', () {
        service.setCalibrationMode(CalibrationMode.pairFarthest);
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0), // Самая далекая от 3-й
          _anchor('2', 200, 200, 55.001, 37.001), // Ближе к 3-й
          _anchor(
            '3',
            300,
            300,
            55.002,
            37.002,
          ), // latest (последняя добавленная)
        ];
        service.updateAnchors(anchors);

        final activeIds = service.activeAnchorIds;
        expect(
          activeIds,
          isNotNull,
          reason: 'В режиме F точки привязки не могут быть null',
        );
        expect(
          activeIds!.length,
          2,
          reason: 'Должно быть ровно 2 зеленых якоря (рабочая пара)',
        );
        expect(
          activeIds.contains('3'),
          isTrue,
          reason: 'Последняя точка (latest) всегда зеленая',
        );
        expect(
          activeIds.contains('1'),
          isTrue,
          reason: 'Самая далекая точка (reference) зеленая',
        );
        expect(
          activeIds.contains('2'),
          isFalse,
          reason: 'Точка вне пары должна быть фиолетовой',
        );
      });

      test('Режим N (Nearest): 2 точки рабочей пары зеленые', () {
        service.setCalibrationMode(CalibrationMode.pairNearest);
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0), // Далеко от 3-й (~250 метров)
          // ✅ ИСПРАВЛЕНО: ~115 метров от 3-й (больше 50м, но ближе, чем 1-я)
          _anchor('2', 290, 290, 55.0011, 37.0011), 
          _anchor('3', 300, 300, 55.002, 37.002), // latest
        ];
        service.updateAnchors(anchors);

        final activeIds = service.activeAnchorIds;
        expect(
          activeIds,
          isNotNull,
          reason: 'В режиме N точки привязки не могут быть null',
        );
        expect(
          activeIds!.length,
          2,
          reason: 'Должно быть ровно 2 зеленых якоря',
        );
        expect(
          activeIds.contains('3'),
          isTrue,
          reason: 'Последняя точка (latest) всегда зеленая',
        );
        expect(
          activeIds.contains('2'),
          isTrue,
          reason: 'Ближайшая валидная точка (reference) зеленая',
        );
        expect(
          activeIds.contains('1'),
          isFalse,
          reason: 'Точка вне пары должна быть фиолетовой',
        );
      });

      test('Ручной режим (M): зеленые только закрепленные (pinned) точки', () {
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0),
          _anchor('2', 200, 200, 55.001, 37.001),
          _anchor('3', 300, 300, 55.002, 37.002),
        ];
        service.updateAnchors(anchors);
        service.enableManualMode();

        service.toggleAnchorPinned('1');
        service.toggleAnchorPinned('3');

        final activeIds = service.activeAnchorIds;
        expect(activeIds, isNotNull);
        expect(activeIds!.length, 2);
        expect(
          activeIds.containsAll(['1', '3']),
          isTrue,
          reason: 'Закрепленные точки зеленые',
        );
        expect(
          activeIds.contains('2'),
          isFalse,
          reason: 'Незакрепленная точка фиолетовая',
        );
      });
    },
  );

  group('MapCalibrationService - ручной режим и коллинеарность', () {
    late MapCalibrationService service;

    setUp(() {
      service = MapCalibrationService();
    });

    test('Коллинеарная точка автоматически удаляется через 1 секунду', () {
      fakeAsync((async) {
        // Подготавливаем три коллинеарные точки
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0),
          _anchor('2', 200, 100, 55.0, 37.001),
          _anchor('3', 300, 100, 55.0, 37.002),
        ];

        service.updateAnchors(anchors);
        // Переходим в ручной режим вручную, чтобы избежать захвата автоматического набора
        service.enableManualMode();

        // Активируем первые две точки (они неколлинеарны)
        service.toggleAnchorPinned('1');
        async.elapse(
          const Duration(milliseconds: 1100),
        ); // ждём срабатывания таймера

        service.toggleAnchorPinned('2');
        async.elapse(const Duration(milliseconds: 1100));

        // Теперь набор из двух точек корректен
        expect(service.pinnedAnchorIdsList.length, 2);

        // Добавляем третью (коллинеарную) точку
        service.toggleAnchorPinned('3');
        async.elapse(const Duration(milliseconds: 1100)); // ждём проверку

        final pinned = service.pinnedAnchorIdsList;
        expect(pinned.length, 2, reason: 'Третья точка должна быть удалена');
        expect(pinned.contains('1'), isTrue);
        expect(pinned.contains('2'), isTrue);
        expect(
          pinned.contains('3'),
          isFalse,
          reason: 'Коллинеарная точка удалена',
        );
      });
    });

    test('Неколлинеарная точка остаётся в наборе', () {
      fakeAsync((async) {
        final anchors = [
          _anchor('1', 100, 100, 55.0, 37.0),
          _anchor('2', 200, 100, 55.0, 37.001),
          _anchor('3', 150, 200, 55.001, 37.0005), // образует треугольник
        ];

        service.updateAnchors(anchors);
        service.enableManualMode();

        service.toggleAnchorPinned('1');
        async.elapse(const Duration(milliseconds: 1100));
        service.toggleAnchorPinned('2');
        async.elapse(const Duration(milliseconds: 1100));
        service.toggleAnchorPinned('3');
        async.elapse(const Duration(milliseconds: 1100));

        final pinned = service.pinnedAnchorIdsList;
        expect(pinned.length, 3, reason: 'Все три точки должны остаться');
        expect(pinned.contains('1'), isTrue);
        expect(pinned.contains('2'), isTrue);
        expect(pinned.contains('3'), isTrue);
      });
    });
  });

  group('MapCalibrationService - Режим "A" (Affine) с fallback на 2 точки', () {
    late MapCalibrationService service;

    setUp(() {
      service = MapCalibrationService();
      // Явно устанавливаем режим Affine
      service.setCalibrationMode(CalibrationMode.affine);
    });

    test('Проверка корректности привязки при добавлении второй точки привязки', () {
      // Точки должны быть достаточно удалены друг от друга (>= 50 метров),
      // чтобы сработала стандартная логика выбора рабочей пары.
      final anchor1 = MapAnchor(
        id: '1',
        imageX: 100,
        imageY: 100,
        latitude: 55.0,
        longitude: 37.0,
        createdAt: DateTime.now(),
      );

      // Вторая точка смещена примерно на ~250 метров
      final anchor2 = MapAnchor(
        id: '2',
        imageX: 300,
        imageY: 300,
        latitude: 55.0018,
        longitude: 37.0018,
        createdAt: DateTime.now(),
      );

      // 1. Добавляем первую точку
      service.updateAnchors([anchor1]);
      expect(
        service.usedAnchorCount,
        0,
        reason: 'Одной точки недостаточно для привязки',
      );
      expect(
        service.imagePointToGeoFromCurrent(const Offset(200, 200)),
        isNull,
      );

      // 2. Добавляем вторую точку
      service.updateAnchors([anchor1, anchor2]);

      // ПРОВЕРКИ: По задумке, в режиме "A" при 2 точках должен сработать fallback
      // на двухточечную схему (SimilarityTransform).
      expect(
        service.usedAnchorCount,
        2,
        reason:
            'При 2 точках в режиме "A" должна строиться двухточечная привязка',
      );

      expect(
        service.imagePointToGeoFromCurrent(const Offset(200, 200)),
        isNotNull,
        reason:
            'Преобразование экранных координат в географические должно работать уже при 2 точках',
      );

      // Индикатор режима для UI должен по-прежнему показывать "A"
      expect(service.calibrationModeLetter, 'A');
    });
  });
}

/// Вспомогательная функция для создания якоря с минимальными полями
MapAnchor _anchor(String id, double x, double y, double lat, double lon) {
  return MapAnchor(
    id: id,
    imageX: x,
    imageY: y,
    latitude: lat,
    longitude: lon,
    createdAt: DateTime.now(),
  );
}
