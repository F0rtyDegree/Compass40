class AppConstants {
  // Калибровка карты
  static const double minAnchorDistanceMeters = 50.0;
  static const double minTriangleAngleDegrees = 15.0;
  static const double metersPerDegreeLat = 111320.0;

  // Компас / сенсоры (настройки по умолчанию)
  static const int uiUpdatePeriodDefaultMs = 250;
  static const int sensorStabilizationDefaultMs = 500;
  static const double autoSwitchSpeedDefaultKmh = 3.0;

  // Карта: масштаб
  static const double minMapScale = 0.05;
  static const double maxMapScale = 20.0;
}