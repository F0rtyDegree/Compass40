import 'package:equatable/equatable.dart';
import 'map_anchor.dart';
import 'map_target.dart';

class MapProject extends Equatable {
  final String id;
  final String imagePath;
  final List<MapAnchor> anchors;
  final List<MapTarget> targets;

  const MapProject({
    required this.id,
    required this.imagePath,
    required this.anchors,
    required this.targets,
  });

  MapProject copyWith({
    String? id,
    String? imagePath,
    List<MapAnchor>? anchors,
    List<MapTarget>? targets,
  }) {
    return MapProject(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      anchors: anchors ?? this.anchors,
      targets: targets ?? this.targets,
    );
  }

  @override
  List<Object?> get props => [id, imagePath, anchors, targets];
}
