import 'package:equatable/equatable.dart';
import 'map_anchor.dart';

class MapWorkingPair extends Equatable {
  final MapAnchor latest;
  final MapAnchor reference;

  const MapWorkingPair({required this.latest, required this.reference});

  @override
  List<Object?> get props => [latest, reference];
}
