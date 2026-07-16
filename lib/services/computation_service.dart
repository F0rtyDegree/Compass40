double calculateCircularMedian(List<double> angles) {
  if (angles.isEmpty) {
    return 0.0;
  }

  angles.sort();
  final n = angles.length;
  if (n % 2 == 1) {
    return angles[n ~/ 2];
  } else {
    final m1 = angles[n ~/ 2 - 1];
    final m2 = angles[n ~/ 2];
    double median;
    if ((m2 - m1).abs() > 180) {
      median = (m1 + m2 + 360) / 2;
      if (median >= 360) {
        median -= 360;
      }
    } else {
      median = (m1 + m2) / 2;
    }
    return median;
  }
}
