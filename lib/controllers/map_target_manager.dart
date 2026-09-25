import 'package:flutter/services.dart';
import '../models/map_target.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';
import '../utils/geo_utils.dart';

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

  // Молча выходим, если нет привязки. Цель без координат бесполезна.
  // Сообщение не показываем: обилие сообщений раздражает, а причина
  // и так очевидна — если карта не привязана, координаты не вычислить.
  /// Создаёт запланированную цель в позиции прицела.
  /// Старая активная цель при этом переводится в passed: ведение
  /// на неё прекращается сразу при первом тапе на кнопку ЦЕЛЬ.
  Future<void> placePlannedTargetAtCrosshair() async {
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

    await _passOldActiveTargets();

    setState(() {
      state.plannedTarget = target;
    });
  }

  /// Помечает текущую активную цель как пройденную и сохраняет проект.
  /// Ведение на неё прекращается.
  Future<void> _passOldActiveTargets() async {
    final project = state.project;
    if (project == null) return;
    final hasActive =
        project.targets.any((t) => t.status == MapTargetStatus.active);
    if (!hasActive) return;

    final updatedTargets = project.targets.map((t) {
      if (t.status == MapTargetStatus.active) {
        return t.copyWith(status: MapTargetStatus.passed);
      }
      return t;
    }).toList();

    final updated = project.copyWith(targets: updatedTargets);
    await storageService.saveProject(updated);
    setState(() {
      state.project = updated;
      state.activeTarget = null;
    });
  }

  void cancelPlannedTarget() {
    setState(() {
      state.plannedTarget = null;
    });
  }

  Future<void> placeTargetFromClipboard() async {
    if (!state.canPlaceTarget) {
      showSnackBar('Сначала привяжите карту');
      return;
    }

    ClipboardData? clipboardData;
    try {
      clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    } catch (_) {
      showSnackBar('Ошибка чтения буфера обмена');
      return;
    }

    if (clipboardData?.text == null || clipboardData!.text!.trim().isEmpty) {
      showSnackBar('Буфер обмена пуст');
      return;
    }

    final geo = parseCoordinates(clipboardData.text!);
    if (geo == null) {
      showSnackBar('Неверный формат. Ожидается: широта,долгота');
      return;
    }
    final lat = geo.latitude;
    final lon = geo.longitude;

    final imagePoint = calibrationService.geoToImagePointFromCurrent(lat, lon);
    if (imagePoint == null) {
      showSnackBar('Не удалось разместить цель на карте');
      return;
    }

    final target = MapTarget(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: imagePoint.dx,
      imageY: imagePoint.dy,
      latitude: lat,
      longitude: lon,
      status: MapTargetStatus.planned,
      createdAt: DateTime.now(),
    );

    await _passOldActiveTargets();

    setState(() {
      state.plannedTarget = target;
    });
//    showSnackBar('Цель установлена из буфера обмена');
  }

  // Молча выходим, если у цели нет координат. Сообщение не показываем.
  // См. комментарий в placePlannedTargetAtCrosshair.
  Future<void> setTargetAndStartNavigation() async {
    final planned = state.plannedTarget;
    if (planned == null || planned.latitude == null || planned.longitude == null) {
      return;
    }
    await _persistAndSetActiveTarget(copyCoords: false);

    if (onStartNavigation != null) {
      await onStartNavigation!(planned.latitude!, planned.longitude!);
//      showSnackBar('Ведение на цель в компасе запущено');
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