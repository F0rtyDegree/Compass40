import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/models/map_anchor.dart';
import 'package:compass40/services/map_calibration_service.dart';

void main() {
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
        async.elapse(const Duration(milliseconds: 1100)); // ждём срабатывания таймера

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
        expect(pinned.contains('3'), isFalse,
            reason: 'Коллинеарная точка удалена');
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