import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/models/map_anchor.dart';
import 'package:compass40/models/map_target.dart';
import 'package:compass40/models/map_transform_state.dart';
import 'package:compass40/widgets/map_overlay_painter.dart';

MapAnchor _anchor(String id, {double x = 0, double y = 0}) => MapAnchor(
      id: id,
      imageX: x,
      imageY: y,
      latitude: 55.0,
      longitude: 37.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

MapTarget _target(String id, {MapTargetStatus status = MapTargetStatus.planned}) =>
    MapTarget(
      id: id,
      imageX: 0,
      imageY: 0,
      latitude: 55.0,
      longitude: 37.0,
      status: status,
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    );

MapOverlayPainter _painter({
  List<MapAnchor> anchors = const [],
  List<MapTarget> targets = const [],
  MapAnchor? pendingAnchor,
  List<Offset> userPath = const [],
  List<int> pathJumpIndices = const [],
}) {
  return MapOverlayPainter(
    imageSize: const Size(1000, 1000),
    transformState: const MapTransformState(),
    viewportSize: const Size(400, 800),
    anchors: anchors,
    targets: targets,
    pendingAnchor: pendingAnchor,
    userPath: userPath,
    pathJumpIndices: pathJumpIndices,
  );
}

void main() {
  group('MapOverlayPainter.shouldRepaint', () {
    test('пустые списки → false', () {
      final a = _painter();
      final b = _painter();
      expect(b.shouldRepaint(a), isFalse);
    });

    test('равные списки → false', () {
      final a = _painter(
        anchors: [_anchor('1'), _anchor('2')],
        targets: [_target('t1')],
      );
      final b = _painter(
        anchors: [_anchor('1'), _anchor('2')],
        targets: [_target('t1')],
      );
      expect(b.shouldRepaint(a), isFalse);
    });

    test('добавление якоря → true', () {
      final a = _painter(anchors: [_anchor('1')]);
      final b = _painter(anchors: [_anchor('1'), _anchor('2')]);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('изменение среднего якоря → true', () {
      final a = _painter(
        anchors: [_anchor('1', x: 0), _anchor('2', x: 0), _anchor('3', x: 0)],
      );
      final b = _painter(
        anchors: [_anchor('1', x: 0), _anchor('2', x: 99), _anchor('3', x: 0)],
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('изменение статуса цели в середине → true', () {
      final a = _painter(
        targets: [
          _target('t1', status: MapTargetStatus.planned),
          _target('t2', status: MapTargetStatus.active),
          _target('t3', status: MapTargetStatus.passed),
        ],
      );
      final b = _painter(
        targets: [
          _target('t1', status: MapTargetStatus.planned),
          _target('t2', status: MapTargetStatus.passed),
          _target('t3', status: MapTargetStatus.passed),
        ],
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('изменение последнего якоря → true', () {
      final a = _painter(anchors: [_anchor('1'), _anchor('2', x: 0)]);
      final b = _painter(anchors: [_anchor('1'), _anchor('2', x: 50)]);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('изменение userPath → true', () {
      final a = _painter(userPath: const [Offset(0, 0), Offset(1, 1)]);
      final b = _painter(
        userPath: const [Offset(0, 0), Offset(1, 1), Offset(2, 2)],
      );
      expect(b.shouldRepaint(a), isTrue);
    });

    test('изменение pathJumpIndices → true', () {
      final a = _painter(pathJumpIndices: const [1]);
      final b = _painter(pathJumpIndices: const [1, 5]);
      expect(b.shouldRepaint(a), isTrue);
    });

    test('появление pendingAnchor → true', () {
      final a = _painter();
      final b = _painter(pendingAnchor: _anchor('pending'));
      expect(b.shouldRepaint(a), isTrue);
    });

    test('исчезновение pendingAnchor → true', () {
      final a = _painter(pendingAnchor: _anchor('pending'));
      final b = _painter();
      expect(b.shouldRepaint(a), isTrue);
    });
  });
}