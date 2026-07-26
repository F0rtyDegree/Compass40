class AppConstants {
  static const double minTriangleAngleDegrees = 15.0;
  static const double maxTriangleAngleDegrees = 165.0; // 180 - 15
  static const double minAnchorDistanceMeters = 50.0;
  static const double metersPerDegreeLat = 111320.0;
  static const double earthRadiusMeters = 6371000.0;

  static const int uiUpdatePeriodDefaultMs = 250;
  static const int sensorStabilizationDefaultMs = 500;
  static const double autoSwitchSpeedDefaultKmh = 2.5;
  static const int gpsUpdateIntervalDefaultSec = 1;
  static const int gpsAveragingSamplesDefault = 3;
  static const int rotateModeTimeoutDefaultMs = 1000;
  static const double smoothingFactorDefault = 0.5;

  static const double minMapScale = 0.05;
  static const double maxMapScale = 20.0;
  
  static const double imageFitPaddingFactor = 0.92;
  static const int feedbackDurationMs = 200;
  
  static const double spikeThresholdDegrees = 30.0;
  static const double latestPointWeight = 10.0;
  static const double minTriangleSideMeters = 1.0;
  static const double minTriangleAreaM2 = 1.0;
}
