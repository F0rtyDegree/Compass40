double updateCompensationEma(double current, double delta) {
  final next = current * 0.9 + delta * 0.1;
  return next.clamp(500.0, 3000.0);
}