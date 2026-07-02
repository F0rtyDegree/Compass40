import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/services/map_calibration_service.dart';
import 'package:compass40/models/map_anchor.dart';

void main() {
  group('MapCalibrationService – режим P (ФотоСевер)', () {
    const declination = 10.0; // градусов
    final declinationRad = declination * math.pi / 180;
    final service = MapCalibrationService();
    service.setMagneticDeclination(declination);

    final baseAnchor = MapAnchor(
      id: '1',
      imageX: 500,
      imageY: 200,
      latitude: 55.0,
      longitude: 37.0,
      createdAt: DateTime.now(),
    );

    setUp(() {
      service.updateAnchors([baseAnchor]);
      service.setPinnedAnchorIds(['1']);
      service.setCalibrationMode(CalibrationMode.photoSever);
      service.updatePhotoSeverData(
        lineMeters: 100,
        linePixels: 200,
        northAngle: -math.pi / 2, // магнитный север вверх
      );
    });

    test('geoToImagePointFromCurrent правильно учитывает склонение', () {
      final lat = baseAnchor.latitude + 100 / 111320.0;
      final lon = baseAnchor.longitude;

      final imagePoint = service.geoToImagePointFromCurrent(lat, lon);
      expect(imagePoint, isNotNull);

      // При восточном склонении истинный север западнее магнитного → смещение по X отрицательное
      final expectedDx = -200 * math.sin(declinationRad);
      final expectedDy = -200 * math.cos(declinationRad);
      final expectedImagePoint = Offset(
        baseAnchor.imageX + expectedDx,
        baseAnchor.imageY + expectedDy,
      );
      expect(imagePoint!.dx, closeTo(expectedImagePoint.dx, 0.5));
      expect(imagePoint.dy, closeTo(expectedImagePoint.dy, 0.5));
    });

    test('imagePointToGeoFromCurrent работает обратно', () {
      final lat = baseAnchor.latitude + 100 / 111320.0;
      final lon = baseAnchor.longitude;
      final imagePoint = service.geoToImagePointFromCurrent(lat, lon)!;
      final geo = service.imagePointToGeoFromCurrent(imagePoint);
      expect(geo, isNotNull);
      expect(geo!.latitude, closeTo(lat, 1e-5));
      expect(geo.longitude, closeTo(lon, 1e-5));
    });
  });
}