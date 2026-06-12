import 'package:flutter/services.dart';
import '../models/map_target.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';

class MapTargetManager {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final MapCalibrationService calibrationService;
  final Future<void> Function(double lat, double lon)? onStartNavigation;
  final VoidCallback onRecalculatePreview;

  MapTargetManager({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.calibrationService,
    required this.onStartNavigation,
    required this.onRecalculatePreview,
  });

  void placePlannedTargetAtCrosshair() {
    if (!state.canPlaceTarget) return;
    if (state.crosshairImagePoint == null) return;

    final geo = calibrationService.imagePointToGeoFromCurrent(
      state.crosshairImagePoint!,
    );

    final target = MapTarget(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: state.crosshairImagePoint!.dx,
      imageY: state.crosshairImagePoint!.dy,
      latitude: geo?.latitude,
      longitude: geo?.longitude,
      status: MapTargetStatus.planned,
      createdAt: DateTime.now(),
    );

    setState(() {
      state.plannedTarget = target;
    });
  }

  void cancelPlannedTarget() {
    setState(() {
      state.plannedTarget = null;
    });
  }

  Future<void> setTargetAndStartNavigation() async {
    final planned = state.plannedTarget;
    if (planned == null || planned.latitude == null || planned.longitude == null) {
      return;
    }
    await _persistAndSetActiveTarget(copyCoords: false);

    if (onStartNavigation != null) {
      await onStartNavigation!(planned.latitude!, planned.longitude!);
      showSnackBar('Ведение на цель в компасе запущено');
    }
  }

  Future<void> _persistAndSetActiveTarget({required bool copyCoords}) async {
    final planned = state.plannedTarget;
    if (planned == null) return;

    final project = state.project;
    if (project == null) return;

    if (planned.latitude == null || planned.longitude == null) {
      showSnackBar('Координаты цели не определены — добавьте привязку');
      return;
    }

    if (copyCoords) {
      final lat = planned.latitude!.toStringAsFixed(6);
      final lon = planned.longitude!.toStringAsFixed(6);
      await Clipboard.setData(ClipboardData(text: '$lat, $lon'));
      showSnackBar('Координаты цели скопированы в буфер обмена');
    }

    final updatedTargets = project.targets.map((t) {
      if (t.status == MapTargetStatus.active) {
        return t.copyWith(status: MapTargetStatus.passed);
      }
      return t;
    }).toList();

    final activeTarget = planned.copyWith(status: MapTargetStatus.active);
    updatedTargets.add(activeTarget);

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
      state.activeTarget = activeTarget;
      state.plannedTarget = null;
    });

    onRecalculatePreview();
  }

  Future<void> markActiveTargetAsPassed() async {
    final active = state.activeTarget;
    if (active == null) return;

    final project = state.project;
    if (project == null) return;

    final updatedTargets = project.targets.map((t) {
      if (t.id == active.id) {
        return t.copyWith(status: MapTargetStatus.passed);
      }
      return t;
    }).toList();

    final updatedProject = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updatedProject);

    setState(() {
      state.project = updatedProject;
      state.activeTarget = null;
    });
  }
}