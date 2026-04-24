import 'package:flutter/material.dart';
import '../models/map_transform_state.dart';

/// Виджет-обёртка для карты, который обрабатывает жесты
/// панорамирования, масштабирования и вращения.
class MapInteractionWrapper extends StatefulWidget {
  final Widget child;
  final MapTransformState transformState;
  final Function(MapTransformState) onTransform;
  final bool rotateMode;

  const MapInteractionWrapper({
    super.key,
    required this.child,
    required this.transformState,
    required this.onTransform,
    required this.rotateMode,
  });

  @override
  State<MapInteractionWrapper> createState() => _MapInteractionWrapperState();
}

class _MapInteractionWrapperState extends State<MapInteractionWrapper> {
  late MapTransformState _currentTransform;
  late MapTransformState _startTransform;

  @override
  void initState() {
    super.initState();
    _currentTransform = widget.transformState;
  }

  @override
  void didUpdateWidget(covariant MapInteractionWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transformState != _currentTransform) {
      setState(() {
        _currentTransform = widget.transformState;
      });
    }
  }

  void _onScaleStart(ScaleStartDetails details) {
    _startTransform = _currentTransform;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final scaleDelta = details.scale;
    final rotationDelta = details.rotation;
    final panDelta = details.focalPoint - details.localFocalPoint;

    if (widget.rotateMode) {
      // Режим вращения и масштабирования
      final newRotation = _startTransform.rotationRadians + rotationDelta;
      final newScale = _startTransform.scale * scaleDelta;

      setState(() {
        _currentTransform = _currentTransform.copyWith(
          scale: newScale.clamp(0.1, 10.0), // Ограничиваем масштаб
          rotationRadians: newRotation,
        );
      });
    } else {
      // Режим панорамирования и масштабирования
      final newScale = _startTransform.scale * scaleDelta;
      final newTranslation = _startTransform.translation + panDelta;

      setState(() {
        _currentTransform = _currentTransform.copyWith(
          scale: newScale.clamp(0.1, 10.0),
          translation: newTranslation,
        );
      });
    }

    widget.onTransform(_currentTransform);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      child: Transform.translate(
        offset: _currentTransform.translation,
        child: Transform.rotate(
          angle: _currentTransform.rotationRadians,
          child: Transform.scale(
            scale: _currentTransform.scale,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
