// Модель для одной контрольной точки (КП)
class Checkpoint {
  final int id; // Порядковый номер внутри трека (0, 1, 2...)
  final double latitude;
  final double longitude;
  final double distanceFromPrevious; // Дистанция от предыдущей точки в метрах
  final double azimuthFromPrevious;  // Азимут от предыдущей точки в градусах

  Checkpoint({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.distanceFromPrevious = 0.0,
    this.azimuthFromPrevious = 0.0,
  });

  // Методы для сериализации в JSON и десериализации
  Map<String, dynamic> toJson() => {
        'id': id,
        'latitude': latitude,
        'longitude': longitude,
        'distanceFromPrevious': distanceFromPrevious,
        'azimuthFromPrevious': azimuthFromPrevious,
      };

  factory Checkpoint.fromJson(Map<String, dynamic> json) => Checkpoint(
        id: json['id'],
        latitude: json['latitude'],
        longitude: json['longitude'],
        distanceFromPrevious: json['distanceFromPrevious'] ?? 0.0,
        azimuthFromPrevious: json['azimuthFromPrevious'] ?? 0.0,
      );
}

// Модель для одного трека
class Track {
  final String id; // Уникальный ID, например, временная метка начала
  final DateTime startTime;
  final List<Checkpoint> checkpoints;

  Track({
    required this.id,
    required this.startTime,
    required this.checkpoints,
  });

  // Методы для сериализации в JSON и десериализации
  Map<String, dynamic> toJson() => {
        'id': id,
        'startTime': startTime.toIso8601String(),
        'checkpoints': checkpoints.map((cp) => cp.toJson()).toList(),
      };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
        id: json['id'],
        startTime: DateTime.parse(json['startTime']),
        checkpoints: List<Checkpoint>.from(
            json['checkpoints'].map((cp) => Checkpoint.fromJson(cp))),
      );
}
