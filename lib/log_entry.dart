// ignore_for_file: avoid_print


// Базовый абстрактный класс для всех записей в журнале
abstract class LogItem {
  final DateTime timestamp;
  final String type;
  // VZ: В конструкторе базового класса автоматически фиксируется время создания любой записи журнала.
  LogItem({required this.type, DateTime? createdAt})
    : timestamp = createdAt ?? DateTime.now();
  Map<String, dynamic> toJson();
}

// Класс для записей о создании цели
class TargetCreationLogEntry extends LogItem {
  final int id;
  final double baseLatitude;
  final double baseLongitude;
  final double azimuth;
  final double distance;
  final double targetLatitude;
  final double targetLongitude;

  TargetCreationLogEntry({
    required this.id,
    required this.baseLatitude,
    required this.baseLongitude,
    required this.azimuth,
    required this.distance,
    required this.targetLatitude,
    required this.targetLongitude,
    super.createdAt,
  }) : super(type: 'target_creation');

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'id': id,
    'baseLatitude': baseLatitude,
    'baseLongitude': baseLongitude,
    'azimuth': azimuth,
    'distance': distance,
    'targetLatitude': targetLatitude,
    'targetLongitude': targetLongitude,
  };

  factory TargetCreationLogEntry.fromJson(Map<String, dynamic> json) {
    return TargetCreationLogEntry(
      id: json['id'] as int,
      baseLatitude: json['baseLatitude'],
      baseLongitude: json['baseLongitude'],
      azimuth: json['azimuth'],
      distance: json['distance'],
      targetLatitude: json['targetLatitude'],
      targetLongitude: json['targetLongitude'],
      createdAt: DateTime.parse(json['timestamp']),
    );
  }
}

// Добавляю после класса TargetCreationLogEntry

class MapAnchorLogEntry extends LogItem {
  final int id;
  final double latitude;
  final double longitude;
  final double? distanceFromPrevious;

  MapAnchorLogEntry({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.distanceFromPrevious,
    super.createdAt,
  }) : super(type: 'map_anchor');

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'distanceFromPrevious': distanceFromPrevious,
  };

  factory MapAnchorLogEntry.fromJson(Map<String, dynamic> json) {
    final entry = MapAnchorLogEntry(
      id: json['id'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      distanceFromPrevious: json['distanceFromPrevious'],
      createdAt: DateTime.parse(json['timestamp']),
    );
    print('loadLogEntries: parsed timestamp = ${entry.timestamp}');
    return entry;
  }
}

// Существующий класс для точек маршрута
class LogEntry extends LogItem {
  final int id;
  final double latitude;
  final double longitude;
  double? distance;
  double? bearing;

  LogEntry({
    required this.id,
    required this.latitude,
    required this.longitude,
    this.distance,
    this.bearing,
    super.createdAt,
  }) : super(type: 'track');

  @override
  Map<String, dynamic> toJson() => {
    'type': type,
    'timestamp': timestamp.toIso8601String(),
    'id': id,
    'latitude': latitude,
    'longitude': longitude,
    'distance': distance,
    'bearing': bearing,
  };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
    id: json['id'],
    latitude: json['latitude'],
    longitude: json['longitude'],
    distance: json['distance'],
    bearing: json['bearing'],
    createdAt: DateTime.parse(json['timestamp']),
  );
}

// Фабрика для десериализации из JSON
LogItem logItemFromJson(Map<String, dynamic> json) {
  switch (json['type']) {
    case 'target_creation':
      return TargetCreationLogEntry.fromJson(json);
    case 'track':
      return LogEntry.fromJson(json);
    case 'map_anchor': // новый тип
      return MapAnchorLogEntry.fromJson(json);
    default:
      throw ArgumentError('Unknown log item type: ${json['type']}');
  }
}
