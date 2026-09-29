double updateCompensationEma(double current, double delta) {
//  0.5 — эмпирический коэффициент.  
  final next = current * 0.9 + (delta * 0.5) * 0.1;
  return next.clamp(500.0, 3000.0);
}