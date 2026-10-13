
/// Формирует фразу для озвучки движения на цель.
///
/// [distanceMeters] — расстояние до цели в метрах.
/// [bearingToTarget] — магнитный азимут на цель в градусах.
/// [currentHeading] — текущий курс в градусах.
///
/// Возвращает строку вида «Пятьсот, вправо два».
/// Если расстояние ≤ 10 м — «Цель рядом».
String buildAnnouncePhrase({
  required double distanceMeters,
  required double bearingToTarget,
  required double currentHeading,
}) {
  if (distanceMeters <= 10) return 'Цель рядом';

  final distText = _formatDistance(distanceMeters);
  final dirText = _formatDirection(
    bearingToTarget: bearingToTarget,
    currentHeading: currentHeading,
  );
  return '$distText, $dirText';
}

String _formatDistance(double meters) {
  if (meters >= 100) {
    final rounded = (meters / 10).round() * 10;
    return '$rounded';
  }
  if (meters >= 50) {
    final rounded = (meters / 5).round() * 5;
    return '$rounded';
  }
  return '${meters.round()}';
}

String _formatDirection({
  required double bearingToTarget,
  required double currentHeading,
}) {
  double relative = (bearingToTarget - currentHeading + 540) % 360 - 180;

  if (relative >= -15 && relative < 15) return 'прямо';
  if (relative >= 165 || relative < -165) return 'назад';

  if (relative > 0) {
    final hour = (relative / 30).round();
    return 'вправо $hour';
  } else {
    final hour = (relative.abs() / 30).round();
    return 'влево $hour';
  }
}