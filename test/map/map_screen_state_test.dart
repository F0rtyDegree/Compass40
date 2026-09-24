import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/controllers/map_screen_state.dart';

void main() {
  group('MapScreenState.recalculateCrosshairImagePoint', () {
    test('ничего не делает, если imageSize == null', () {
      final s = MapScreenState();
      s.viewportSize = const Size(400, 800);
      s.recalculateCrosshairImagePoint((p) => p);
      expect(s.crosshairImagePoint, isNull);
    });

    test('ничего не делает, если viewportSize == null', () {
      final s = MapScreenState();
      s.imageSize = const Size(1000, 1000);
      s.recalculateCrosshairImagePoint((p) => p);
      expect(s.crosshairImagePoint, isNull);
    });

    test('пересчитывает точку через переданную функцию', () {
      final s = MapScreenState();
      s.imageSize = const Size(1000, 1000);
      s.viewportSize = const Size(400, 800);
      s.crosshairInCenter = true;

      s.recalculateCrosshairImagePoint(
        (p) => Offset(p.dx * 2, p.dy * 2),
      );

      expect(s.crosshairImagePoint, const Offset(400, 800));
    });
  });

}