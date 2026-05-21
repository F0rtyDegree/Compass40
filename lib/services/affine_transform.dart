import 'dart:ui';

class AffineTransform {
  final List<double> m; // матрица 3x3, третья строка [0,0,1]

  AffineTransform._(this.m);

  factory AffineTransform.fromPoints(
    List<Offset> imagePoints,
    List<Offset> geoPoints, {
    List<double>? weights,
  }) {
    final n = imagePoints.length;
    if (n < 3) throw ArgumentError('Need at least 3 points');
    final w = weights ?? List.filled(n, 1.0);
    if (w.length != n) throw ArgumentError('weights length mismatch');

    final ata = List.generate(6, (_) => List.filled(6, 0.0));
    final atb = List.filled(6, 0.0);

    for (int i = 0; i < n; i++) {
      final weight = w[i];
      final x = imagePoints[i].dx;
      final y = imagePoints[i].dy;
      final u = geoPoints[i].dx;
      final v = geoPoints[i].dy;

      _addRow(ata, atb, [x, y, 1, 0, 0, 0], u, weight);
      _addRow(ata, atb, [0, 0, 0, x, y, 1], v, weight);
    }

    final solution = _solve6x6(ata, atb);
    return AffineTransform._([
      solution[0], solution[1], solution[2],
      solution[3], solution[4], solution[5],
      0, 0, 1,
    ]);
  }

  static void _addRow(List<List<double>> ata, List<double> atb,
      List<double> row, double b, double weight) {
    for (int i = 0; i < 6; i++) {
      if (row[i] == 0.0) continue;
      for (int j = 0; j < 6; j++) {
        if (row[j] != 0.0) ata[i][j] += row[i] * row[j] * weight;
      }
      atb[i] += row[i] * b * weight;
    }
  }

  static List<double> _solve6x6(List<List<double>> a, List<double> b) {
    final n = 6;
    final aa = List.generate(n, (i) => [...a[i]]);
    final bb = [...b];

    for (int col = 0; col < n; col++) {
      int maxRow = col;
      double maxVal = aa[col][col].abs();
      for (int row = col + 1; row < n; row++) {
        if (aa[row][col].abs() > maxVal) {
          maxVal = aa[row][col].abs();
          maxRow = row;
        }
      }
      if (maxVal < 1e-12) throw ArgumentError('Singular matrix');
      if (maxRow != col) {
        final temp = aa[col]; aa[col] = aa[maxRow]; aa[maxRow] = temp;
        final tb = bb[col]; bb[col] = bb[maxRow]; bb[maxRow] = tb;
      }
      for (int row = col + 1; row < n; row++) {
        final factor = aa[row][col] / aa[col][col];
        for (int j = col; j < n; j++) {
          aa[row][j] -= factor * aa[col][j];
        }
        bb[row] -= factor * bb[col];
      }
    }

    final x = List.filled(n, 0.0);
    for (int i = n - 1; i >= 0; i--) {
      double s = bb[i];
      for (int j = i + 1; j < n; j++) {
        s -= aa[i][j] * x[j];
      }
      x[i] = s / aa[i][i];
    }
    return x;
  }

  /// Прямое преобразование: пиксель → географическая точка
  Offset transform(Offset imagePoint) {
    final x = imagePoint.dx, y = imagePoint.dy;
    final u = m[0] * x + m[1] * y + m[2];
    final v = m[3] * x + m[4] * y + m[5];
    return Offset(u, v);
  }

  /// Обратное преобразование: географическая точка → пиксель
  Offset inverseTransform(Offset geoPoint) {
    // Обращение матрицы 3x3 аффинного преобразования
    final a = m[0], b = m[1], c = m[2];
    final d = m[3], e = m[4], f = m[5];
    final det = a * e - b * d;
    if (det.abs() < 1e-12) throw StateError('Non-invertible affine matrix');
    final invDet = 1.0 / det;
    final u = geoPoint.dx, v = geoPoint.dy;
    final x = (e * u - b * v + b * f - e * c) * invDet;
    final y = (-d * u + a * v + d * c - a * f) * invDet;
    return Offset(x, y);
  }
}