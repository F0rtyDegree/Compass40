import 'package:equatable/equatable.dart';
import 'package:flutter/widgets.dart';
import 'map_anchor.dart';
import 'map_target.dart';

class MapProject extends Equatable {
  final String id;
  final String imagePath;
  final List<MapAnchor> anchors;
  final List<MapTarget> targets;
  final List<Offset> userPath; // Путь пользователя

  const MapProject({
    required this.id,
    required this.imagePath,
    required this.anchors,
    required this.targets,
    this.userPath = const [],
  });

  MapProject copyWith({
    String? id,
    String? imagePath,
    List<MapAnchor>? anchors,
    List<MapTarget>? targets,
    List<Offset>? userPath,
  }) {
    return MapProject(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      anchors: anchors ?? this.anchors,
      targets: targets ?? this.targets,
      userPath: userPath ?? this.userPath,
    );
  }

  // --- Serialization ---

  factory MapProject.fromJson(Map<String, dynamic> json) {
    return MapProject(
      id: json['id'] as String,
      imagePath: json['imagePath'] as String,
      anchors: (json['anchors'] as List)
          .map((i) => MapAnchor.fromJson(i as Map<String, dynamic>))
          .toList(),
      targets: (json['targets'] as List)
          .map((i) => MapTarget.fromJson(i as Map<String, dynamic>))
          .toList(),
      userPath: ((json['userPath'] as List?) ?? [])
          .map((p) => Offset(p['dx'] as double, p['dy'] as double))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'imagePath': imagePath,
      'anchors': anchors.map((a) => a.toJson()).toList(),
      'targets': targets.map((t) => t.toJson()).toList(),
      'userPath': userPath.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
    };
  }


  @override
  List<Object?> get props => [id, imagePath, anchors, targets, userPath];
}
