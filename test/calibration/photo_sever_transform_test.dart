import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/transforms/photo_sever_transform.dart';
import 'package:compass40/models/map_anchor.dart';

void main() {
  final base = MapAnchor(
    id: 'b',
    imageX: 500, imageY: 500,
    latitude: 55.0, longitude: 37.0,
    createdAt: DateTime.now(),
  );

  const lineMeters = 100.0;
  const linePixels = 200.0;

  final oneMeterLatDeg = 1 / 111320.0;
  final oneMeterLonDeg = 1 / (111320.0 * math.cos(base.latitude * math.pi / 180));

  group('PhotoSeverTransform – все ориентации севера', () {
    final cases = [
      _Case('север вверху', northAngle: -math.pi / 2,
          northOffset: Offset(0, -linePixels), eastOffset: Offset(linePixels, 0)),
      _Case('север внизу', northAngle: math.pi / 2,
          northOffset: Offset(0, linePixels), eastOffset: Offset(-linePixels, 0)),
      _Case('север справа', northAngle: 0.0,
          northOffset: Offset(linePixels, 0), eastOffset: Offset(0, linePixels)),
      _Case('север слева', northAngle: math.pi,
          northOffset: Offset(-linePixels, 0), eastOffset: Offset(0, -linePixels)),
    ];

    for (final c in cases) {
      test(c.name, () {
        final t = PhotoSeverTransform(
          baseAnchor: base,
          lineMeters: lineMeters,
          linePixels: linePixels,
          northAngle: c.northAngle,
        );

        final imgNorth = Offset(base.imageX, base.imageY) + c.northOffset;
        final geoNorth = t.imageToGeo(imgNorth);
        expect(geoNorth.dy, closeTo(base.latitude + 100 * oneMeterLatDeg, 1e-5));
        expect(geoNorth.dx, closeTo(base.longitude, 1e-5));

        final imgEast = Offset(base.imageX, base.imageY) + c.eastOffset;
        final geoEast = t.imageToGeo(imgEast);
        expect(geoEast.dx, closeTo(base.longitude + 100 * oneMeterLonDeg, 1e-5));
        expect(geoEast.dy, closeTo(base.latitude, 1e-5));
      });
    }
  });
}

class _Case {
  final String name;
  final double northAngle;
  final Offset northOffset;
  final Offset eastOffset;
  _Case(this.name, {required this.northAngle, required this.northOffset, required this.eastOffset});
}