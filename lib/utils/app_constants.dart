class AppConstants {
  // У программы единственный пользователь — сам разработчик.
  // В текущих условиях жёсткие пути Android работают и менять их
  // на path_provider не нужно. Когда появятся проблемы на других
  // устройствах — вернуться к этому вопросу.
  static const String externalDownloadDir = '/storage/emulated/0/Download';
  static const String externalDownloadFallback = '/sdcard/Download';
  static const String compassFolderName = 'Compass40';

  static const String logFileName = 'compass_log.txt';
  static const String trackFileName = 'track_points.csv';
  static const String mapsFolderName = 'compass40_maps';
  static const String notificationChannelId = 'compass40_tracking_channel';

  /// Ключи SharedPreferences.
  static const String prefUseManualDeclination = 'useManualDeclination';
  static const String prefManualDeclination = 'manualDeclination';
  static const String prefGpsUpdateInterval = 'gpsUpdateInterval';
  static const String prefGpsAveragingSamples = 'gpsAveragingSamples';
  static const String prefAutoSwitchSpeedKmh = 'autoSwitchSpeedKmh';
  static const String prefUiUpdatePeriod = 'uiUpdatePeriod';
  static const String prefCompassSmoothness = 'compassSmoothness';
  static const String prefCompassMode = 'compassMode';
  static const String prefThemeMode = 'themeMode';
  static const String prefRotateModeTimeoutMs = 'rotateModeTimeoutMs';
  static const String prefAnchorCompensationMs = 'anchor_compensation_ms';
  static const String prefPhotoSeverDistance = 'photoSeverDistance';
  static const String prefIsRecordingTrack = 'isRecordingTrack';
  static const String prefLogItems = 'log_items';
  static const String prefMapProjects = 'map_projects';
  static const String prefCurrentMapProjectId = 'current_map_project_id';
  static const String prefMapTransformPrefix = 'map_transform_';
  static const String prefCompassCalibX = 'compass_calib_x';
  static const String prefCompassCalibY = 'compass_calib_y';
  static const String prefCompassCalibZ = 'compass_calib_z';
  static const String prefCompassCalibRangeX = 'compass_calib_range_x';
  static const String prefCompassCalibRangeY = 'compass_calib_range_y';
  static const String prefCompassCalibRangeZ = 'compass_calib_range_z';
  static const String prefCompassCalibrated = 'compass_calibrated';
  static const String prefCompassCalibMagnitude = 'compass_calib_magnitude';

  static const double minTriangleAngleDegrees = 15.0;
  static const double maxTriangleAngleDegrees = 165.0; // 180 - 15
  static const double minAnchorDistanceMeters = 30.0;
  static const double metersPerDegreeLat = 111320.0;
  static const double earthRadiusMeters = 6371000.0;

  static const int uiUpdatePeriodDefaultMs = 250;
  static const int sensorStabilizationDefaultMs = 500;
  static const int compassSmoothnessDefault = 50;
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
