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
  final List<int> pathJumpIndices; // Индексы, где были "скачки" пути
  final List<Map<String, String>>? cachedGpxPoints;
  // ✅ Новые поля для ФотоСевера
  final double photoSeverLineMeters;
  final double photoSeverLinePixels;
  final double photoSeverNorthAngle;
  final List<String> pinnedAnchorIds;
  final bool manualMode;
  final String calibrationMode;

  const MapProject({
    required this.id,
    required this.imagePath,
    required this.anchors,
    required this.targets,
    this.userPath = const [],
    this.pathJumpIndices = const [],
    this.photoSeverLineMeters = 0.0,
    this.photoSeverLinePixels = 0.0,
    this.photoSeverNorthAngle = 0.0,
    this.cachedGpxPoints,
    this.pinnedAnchorIds = const [],
    this.manualMode = false,
    this.calibrationMode = 'affine',
  });

  MapProject copyWith({
    String? id,
    String? imagePath,
    List<MapAnchor>? anchors,
    List<MapTarget>? targets,
    List<Offset>? userPath,
    List<int>? pathJumpIndices,
    double? photoSeverLineMeters,
    double? photoSeverLinePixels,
    double? photoSeverNorthAngle,
    List<Map<String, String>>? cachedGpxPoints,
    List<String>? pinnedAnchorIds,
    bool? manualMode,
    String? calibrationMode,
  }) {
    return MapProject(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      anchors: anchors ?? this.anchors,
      targets: targets ?? this.targets,
      userPath: userPath ?? this.userPath,
      pathJumpIndices: pathJumpIndices ?? this.pathJumpIndices,
      photoSeverLineMeters: photoSeverLineMeters ?? this.photoSeverLineMeters,
      photoSeverLinePixels: photoSeverLinePixels ?? this.photoSeverLinePixels,
      photoSeverNorthAngle: photoSeverNorthAngle ?? this.photoSeverNorthAngle,
      cachedGpxPoints: cachedGpxPoints ?? this.cachedGpxPoints,
      pinnedAnchorIds: pinnedAnchorIds ?? this.pinnedAnchorIds,
      manualMode: manualMode ?? this.manualMode,
      calibrationMode: calibrationMode ?? this.calibrationMode,
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
      pathJumpIndices: ((json['pathJumpIndices'] as List?) ?? [])
          .cast<int>()
          .toList(),
      pinnedAnchorIds:
          (json['pinnedAnchorIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      manualMode: json['manualMode'] as bool? ?? false,
      calibrationMode: json['calibrationMode'] as String? ?? 'affine',
      photoSeverLineMeters:
          (json['photoSeverLineMeters'] as num?)?.toDouble() ?? 0.0,
      photoSeverLinePixels:
          (json['photoSeverLinePixels'] as num?)?.toDouble() ?? 0.0,
      photoSeverNorthAngle:
          (json['photoSeverNorthAngle'] as num?)?.toDouble() ?? 0.0,
      cachedGpxPoints: (json['cachedGpxPoints'] as List<dynamic>?)
          ?.map((e) => Map<String, String>.from(e as Map))
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
      'pathJumpIndices': pathJumpIndices,
      'pinnedAnchorIds': pinnedAnchorIds,
      'manualMode': manualMode,
      'calibrationMode': calibrationMode,
      'photoSeverLineMeters': photoSeverLineMeters,
      'photoSeverLinePixels': photoSeverLinePixels,
      'photoSeverNorthAngle': photoSeverNorthAngle,
      'cachedGpxPoints': cachedGpxPoints,
    };
  }

  @override
  List<Object?> get props => [
    id,
    imagePath,
    anchors,
    targets,
    userPath,
    pathJumpIndices,
      photoSeverLineMeters,
    photoSeverLinePixels,
    photoSeverNorthAngle,
    cachedGpxPoints,
    pinnedAnchorIds,
    manualMode,
    calibrationMode,
  ];
}
