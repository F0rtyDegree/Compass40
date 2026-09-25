import 'package:flutter_test/flutter_test.dart';
import 'package:compass40/utils/track_utils.dart';

void main() {
  group('pruneTrackPoints', () {
    test('короткий список возвращается как есть', () {
      final points = List.generate(100, (i) => Offset(i.toDouble(), 0));
      final result = pruneTrackPoints(points: points, maxPoints: 5000);
      expect(result, same(points));
    });

    test('ровно maxPoints не прореживается', () {
      final points = List.generate(5000, (i) => Offset(i.toDouble(), 0));
      final result = pruneTrackPoints(points: points, maxPoints: 5000);
      expect(result.length, 5000);
    });

    test('maxPoints+1 прореживается, длина падает', () {
      final points = List.generate(5001, (i) => Offset(i.toDouble(), 0));
      final result = pruneTrackPoints(points: points, maxPoints: 5000);
      expect(result.length, lessThan(5001));
    });

    test('первая точка сохраняется', () {
      final points = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      final result = pruneTrackPoints(points: points, maxPoints: 5000);
      expect(result.first, points.first);
    });

    test('последняя точка сохраняется', () {
      final points = List.generate(6000, (i) => Offset(i.toDouble(), 0));
      final result = pruneTrackPoints(points: points, maxPoints: 5000);
      expect(result.last, points.last);
    });
  });
}