import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/models/map_project.dart';

void main() {
  group('MapProject.copyWith — sentinel для cachedGpxPoints', () {
    final base = MapProject(
      id: 'p1',
      imagePath: '/tmp/img.png',
      anchors: const [],
      targets: const [],
      cachedGpxPoints: const [
        {'name': 'A', 'lat': '55.0', 'lon': '37.0'},
      ],
    );

    test('без аргументов сохраняет всё, включая cachedGpxPoints', () {
      final r = base.copyWith();
      expect(r.cachedGpxPoints, base.cachedGpxPoints);
      expect(r.id, base.id);
      expect(r.imagePath, base.imagePath);
    });

    test('явный null обнуляет cachedGpxPoints', () {
      final r = base.copyWith(cachedGpxPoints: null);
      expect(r.cachedGpxPoints, isNull);
    });

    test('новый список заменяет cachedGpxPoints', () {
      final r = base.copyWith(
        cachedGpxPoints: const [
          {'name': 'B', 'lat': '56.0', 'lon': '38.0'},
        ],
      );
      expect(r.cachedGpxPoints, isNotNull);
      expect(r.cachedGpxPoints!.length, 1);
      expect(r.cachedGpxPoints!.first['name'], 'B');
    });

    test('одновременное изменение нескольких полей', () {
      final r = base.copyWith(
        id: 'p2',
        manualMode: true,
        calibrationMode: 'pairNearest',
        cachedGpxPoints: null,
      );
      expect(r.id, 'p2');
      expect(r.manualMode, isTrue);
      expect(r.calibrationMode, 'pairNearest');
      expect(r.cachedGpxPoints, isNull);
      expect(r.imagePath, base.imagePath);
    });
  });
}