import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/transforms/similarity_transform.dart';
import 'package:compass40/models/map_anchor.dart';

void main() {
  test('SimilarityTransform строит правильное преобразование', () {
    // Два якоря: (0,0) пикс -> (0°, 0°) и (100,0) пикс -> (0.001°, 0°)
    // Ожидаем поворот 0, масштаб по X = 0.001/100 = 1e-5 град/пикс
    final anchor1 = MapAnchor(
      id: 'a1',
      imageX: 0, imageY: 0,
      latitude: 0, longitude: 0,
      createdAt: DateTime.now(),
    );
    final anchor2 = MapAnchor(
      id: 'a2',
      imageX: 100, imageY: 0,
      latitude: 0, longitude: 0.001,
      createdAt: DateTime.now(),
    );
    final transform = SimilarityTransform.fromPair(anchor2, anchor1);
    final geo = transform.imageToGeo(Offset(50, 0));
    expect(geo.dx, closeTo(0.0005, 1e-9));
    expect(geo.dy, closeTo(0, 1e-9));
    // Обратно
    final img = transform.geoToImage(Offset(0.0005, 0));
    expect(img.dx, closeTo(50, 1e-6));
    expect(img.dy, closeTo(0, 1e-6));
  });
}