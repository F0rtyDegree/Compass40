import 'package:equatable/equatable.dart';

enum MapTargetStatus { planned, active, passed }

class MapTarget extends Equatable {
  final String id;
  final double imageX;
  final double imageY;
  final double? latitude;
  final double? longitude;
  final MapTargetStatus status;
  final DateTime createdAt;

  const MapTarget({
    required this.id,
    required this.imageX,
    required this.imageY,
    this.latitude,
    this.longitude,
    required this.status,
    required this.createdAt,
  });

  @override
  List<Object?> get props => [id, imageX, imageY, latitude, longitude, status, createdAt];
}