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

  MapTarget copyWith({
    String? id,
    double? imageX,
    double? imageY,
    double? latitude,
    double? longitude,
    MapTargetStatus? status,
    DateTime? createdAt,
  }) {
    return MapTarget(
      id: id ?? this.id,
      imageX: imageX ?? this.imageX,
      imageY: imageY ?? this.imageY,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  List<Object?> get props => [
    id,
    imageX,
    imageY,
    latitude,
    longitude,
    status,
    createdAt,
  ];
}
