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

  @override
  List<Object?> get props => [id, imageX, imageY, latitude, longitude, createdAt];
}