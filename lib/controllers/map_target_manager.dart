import 'package:flutter/services.dart';
import '../models/map_target.dart';
import '../services/map_calibration_service.dart';
import '../services/map_storage_service.dart';
import '../services/navigation_method_service.dart';
import '../utils/geo_utils.dart';
import 'map_screen_state.dart';

class MapTargetManager {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final MapStorageService storageService;
  final MapCalibrationService calibrationService;
  final Future<void> Function(double lat, double lon)? onStartNavigation;
  final VoidCallback? onCancelNavigation;
  final VoidCallback onRecalculatePreview;
  final Future<void> Function()? onTargetActivatedForRoute;
  final VoidCallback? onTargetClearedForRoute;

  MapTargetManager({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.storageService,
    required this.calibrationService,
    required this.onStartNavigation,
    this.onCancelNavigation,
    required this.onRecalculatePreview,
    this.onTargetActivatedForRoute,
    this.onTargetClearedForRoute,
  });

  /// Короткий тап по кнопке «ЦЕЛЬ» (или выбор способа из меню при active button):
  /// удаляет предыдущий флаг, ставит новый в точку прицела и сразу запускает ведение.
  Future<void> startNewTargetAtCrosshair({String? methodId}) async {
    if (!state.canPlaceTarget) return;
    final crosshair = state.crosshairImagePoint;
    if (crosshair == null) return;

    final geo = calibrationService.imagePointToGeoFromCurrent(crosshair);
    if (geo == null) {
      showSnackBar('Сначала привяжите карту');
      return;
    }

    final resolvedMethodId =
        methodId ?? await NavigationMethodService.getDefaultMethodId();

    await _activateSingleTarget(
      imagePoint: crosshair,
      latitude: geo.latitude,
      longitude: geo.longitude,
      methodId: resolvedMethodId,
    );
  }

  /// «Вставить из буфера» в меню кнопки «ЦЕЛЬ»:
  /// парсит координаты, удаляет предыдущий флаг, ставит новый и запускает ведение способом по умолчанию.
  Future<void> startTargetFromClipboard() async {
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

    final imagePoint = calibrationService.geoToImagePointFromCurrent(
      geo.latitude,
      geo.longitude,
    );
    if (imagePoint == null) {
      showSnackBar('Сначала привяжите карту');
      return;
    }

    final defaultMethodId = await NavigationMethodService.getDefaultMethodId();

    await _activateSingleTarget(
      imagePoint: imagePoint,
      latitude: geo.latitude,
      longitude: geo.longitude,
      methodId: defaultMethodId,
    );
  }

  /// Пересчитывает ведение на текущую активную цель новым способом (из меню в followMode).
  Future<void> recalculateCurrentTargetWithMethod(String methodId) async {
    final active = state.activeTarget;
    if (active == null || active.latitude == null || active.longitude == null) {
      return;
    }

    setState(() {
      state.activeNavigationMethodId = methodId;
    });

    await NavigationMethodService.saveActiveTarget(
      PersistedTargetData(
        latitude: active.latitude!,
        longitude: active.longitude!,
        methodId: methodId,
      ),
    );

    if (onStartNavigation != null) {
      await onStartNavigation!(active.latitude!, active.longitude!);
    }
    await onTargetActivatedForRoute?.call();
  }

  /// Останавливает ведение, удаляет красный флаг, очищает линию маршрута и сохранённую цель.
  Future<void> stopNavigation({bool notifyHome = true}) async {
    final project = state.project;
    if (project != null && project.targets.isNotEmpty) {
      final updatedProject = project.copyWith(targets: []);
      await storageService.saveProject(updatedProject);
      setState(() {
        state.project = updatedProject;
        state.activeTarget = null;
      });
    } else {
      setState(() {
        state.activeTarget = null;
      });
    }

    await NavigationMethodService.clearActiveTarget();
    onTargetClearedForRoute?.call();
    if (notifyHome) {
      onCancelNavigation?.call();
    }
  }

  /// Восстанавливает активную цель при возврате с экрана компаса или после сбоя.
  Future<void> restorePersistedTargetIfAny() async {
    final persisted = await NavigationMethodService.loadActiveTarget();
    if (persisted == null) return;

    final imagePoint = calibrationService.geoToImagePointFromCurrent(
      persisted.latitude,
      persisted.longitude,
    );
    if (imagePoint == null) return;

    final restoredTarget = MapTarget(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: imagePoint.dx,
      imageY: imagePoint.dy,
      latitude: persisted.latitude,
      longitude: persisted.longitude,
      status: MapTargetStatus.active,
      createdAt: DateTime.now(),
    );

    final project = state.project;
    if (project != null) {
      final updatedProject = project.copyWith(targets: [restoredTarget]);
      await storageService.saveProject(updatedProject);
      setState(() {
        state.project = updatedProject;
        state.activeTarget = restoredTarget;
        state.activeNavigationMethodId = persisted.methodId;
      });
    } else {
      setState(() {
        state.activeTarget = restoredTarget;
        state.activeNavigationMethodId = persisted.methodId;
      });
    }

    onRecalculatePreview();
    if (onStartNavigation != null) {
      await onStartNavigation!(persisted.latitude, persisted.longitude);
    }
    await onTargetActivatedForRoute?.call();
  }

  Future<void> _activateSingleTarget({
    required Offset imagePoint,
    required double latitude,
    required double longitude,
    required String methodId,
  }) async {
    final project = state.project;
    if (project == null) return;

    final newTarget = MapTarget(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      imageX: imagePoint.dx,
      imageY: imagePoint.dy,
      latitude: latitude,
      longitude: longitude,
      status: MapTargetStatus.active,
      createdAt: DateTime.now(),
    );

    final updatedProject = project.copyWith(targets: [newTarget]);
    await storageService.saveProject(updatedProject);

    await NavigationMethodService.saveActiveTarget(
      PersistedTargetData(
        latitude: latitude,
        longitude: longitude,
        methodId: methodId,
      ),
    );

    setState(() {
      state.project = updatedProject;
      state.activeTarget = newTarget;
      state.activeNavigationMethodId = methodId;
    });

    onRecalculatePreview();

    if (onStartNavigation != null) {
      await onStartNavigation!(latitude, longitude);
    }
    await onTargetActivatedForRoute?.call();
  }
}
