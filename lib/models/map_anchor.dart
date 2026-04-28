import 'package:equatable/equatable.dart';

class MapAnchor extends Equatable {
  final String id;
  final double imageX;
  final double imageY;
  final double latitude;
  final double longitude;
  final DateTime createdAt;

  const MapAnchor({
    required this.id,
    required this.imageX,
    required this.imageY,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
  });

  factory MapAnchor.fromJson(Map<String, dynamic> json) {
    return MapAnchor(
      id: json['id'] as String,
      imageX: (json['imageX'] as num).toDouble(),
      imageY: (json['imageY'] as num).toDouble(),
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imageX': imageX,
      'imageY': imageY,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  @override
  List<Object?> get props => [
    id,
    imageX,
    imageY,
    latitude,
    longitude,
    createdAt,
  ];
}
