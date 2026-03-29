class GpsData {
  final double? latitude;
  final double? longitude;
  final double? accuracy;
  final double? speed;
  final double? altitude;
  final double? mslAltitude; 
  final int? satellitesUsed;
  final int? satellitesInView;
  final double? magneticDeclination; 

  GpsData({
    this.latitude,
    this.longitude,
    this.accuracy,
    this.speed,
    this.altitude,
    this.mslAltitude,
    this.satellitesUsed,
    this.satellitesInView,
    this.magneticDeclination,
  });

  factory GpsData.fromMap(Map<dynamic, dynamic> map) {
    return GpsData(
      latitude: map['latitude'] as double?,
      longitude: map['longitude'] as double?,
      accuracy: map['accuracy'] as double?,
      speed: map['speed'] as double?,
      altitude: map['altitude'] as double?,
      mslAltitude: map['msl_altitude'] as double?,
      satellitesUsed: map['satellitesUsed'] as int?,
      satellitesInView: map['satellitesInView'] as int?,
      magneticDeclination: map['magneticDeclination'] as double?,
    );
  }
}
