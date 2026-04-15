import 'package:flutter/widgets.dart';
import 'package:equatable/equatable.dart';

class MapTransformState extends Equatable {
  final double scale;
  final double rotationRadians;
  final Offset translation;

  const MapTransformState({
    this.scale = 1.0,
    this.rotationRadians = 0.0,
    this.translation = Offset.zero,
  });

  MapTransformState copyWith({
    double? scale,
    double? rotationRadians,
    Offset? translation,
  }) {
    return MapTransformState(
      scale: scale ?? this.scale,
      rotationRadians: rotationRadians ?? this.rotationRadians,
      translation: translation ?? this.translation,
    );
  }

  @override
  List<Object?> get props => [scale, rotationRadians, translation];
}