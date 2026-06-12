import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_transform_state.dart';
import 'map_screen_state.dart';

class MapFollowController {
  final MapScreenState state;
  final void Function(VoidCallback fn) setState;
  final void Function(String message) showSnackBar;
  final double magneticDeclination;

  final Offset Function(Offset screenPoint) screenToImage;
  final Offset Function(Offset imagePoint) imageToScreen;
  final void Function(MapTransformState newTransform) updateTransform;

  bool keepFollowDuringScale = false;
  int rotateModeTimeoutMs = 1000;
  bool isAutoRotating = false;

  MapFollowController({
    required this.state,
    required this.setState,
    required this.showSnackBar,
    required this.magneticDeclination,
    required this.screenToImage,
    required this.imageToScreen,
    required this.updateTransform,
  });

  Future<void> loadRotateModeTimeout() async {
    final prefs = await SharedPreferences.getInstance();
    rotateModeTimeoutMs = prefs.getInt('rotateModeTimeoutMs') ?? 1000;
  }

  void enableFollowMode() {
    if (state.workingPair == null) {
      showSnackBar(
        'Режим сопровождения доступен только после привязки карты (добавьте минимум 2 точки привязки)',
      );
      return;
    }
    state.followRestoreTimer?.cancel();
    setState(() {
      state.followMode = true;
      state.crosshairInCenter = false;
    });
    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();
    centerMapOnUser();
    applyHeadingRotation();
  }

  void disableFollowMode() {
    state.followRestoreTimer?.cancel();
    setState(() {
      state.followMode = false;
      state.crosshairInCenter = true;
    });
    _recalculateCrosshairImagePoint();
    _recalculateUserScreenPoint();
  }

  void toggleFollowMode() {
    if (!state.followMode && state.workingPair == null) {
      showSnackBar('Режим сопровождения доступен только после привязки карты');
      return;
    }
    if (state.followMode) {
      disableFollowMode();
    } else {
      enableFollowMode();
    }
  }

  void centerMapOnUser() {
    final imagePoint = state.currentUserImagePoint;
    if (imagePoint == null || state.viewportSize == null) return;

    final crosshairScreen = _getCrosshairScreenPoint();
    final vp = state.viewportSize!;
    final vpCenter = Offset(vp.width / 2, vp.height / 2);
    final targetTranslation = crosshairScreen - vpCenter;

    final t = state.transformState;
    final imageSize = state.imageSize;
    if (imageSize == null) return;

    final local =
        imagePoint - Offset(imageSize.width / 2, imageSize.height / 2);
    final scaled = local * t.scale;

    final angle = t.rotationRadians;
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    final rotated = Offset(
      scaled.dx * cos - scaled.dy * sin,
      scaled.dx * sin + scaled.dy * cos,
    );

    final newTranslation = targetTranslation - rotated;

    setState(() {
      state.transformState = t.copyWith(translation: newTranslation);
    });

    _recalculateUserScreenPoint();
  }

  void enableRotateMode() {
    setState(() {
      state.rotateMode = true;
    });
    _resetRotateModeTimer();
  }

  void disableRotateMode() {
    state.rotateModeTimer?.cancel();
    setState(() {
      state.rotateMode = false;
    });
  }

  void resetRotateModeTimer() {
    _resetRotateModeTimer();
  }

  void _resetRotateModeTimer() {
    state.rotateModeTimer?.cancel();
    if (!state.rotateMode) return;
    if (rotateModeTimeoutMs <= 0) return;
    state.rotateModeTimer = Timer(
      Duration(milliseconds: rotateModeTimeoutMs),
      () {
        if (state.isDisposed) return;
        setState(() {
          state.rotateMode = false;
          state.rotateModeTimer = null;
        });
      },
    );
  }

  void applyHeadingRotation() {
    if (!state.followMode ||
        state.heading == null ||
        state.workingPair == null) {
      return;
    }

    isAutoRotating = true;

    final magneticHeadingRad = (state.heading!) * (math.pi / 180);
    final declinationRad = magneticDeclination * (math.pi / 180);
    final trueHeadingRad = magneticHeadingRad + declinationRad;

    final targetRotation = -trueHeadingRad + state.mapRotation;

    final current = state.transformState;
    final pivotImage = screenToImage(_getCrosshairScreenPoint());

    final tempTransform = current.copyWith(rotationRadians: targetRotation);
    final oldTransform = state.transformState;
    state.transformState = tempTransform;
    final pivotScreenAfterRotate = imageToScreen(pivotImage);
    state.transformState = oldTransform;

    final delta = _getCrosshairScreenPoint() - pivotScreenAfterRotate;
    final newTranslation = current.translation + delta;

    updateTransform(
      current.copyWith(
        rotationRadians: targetRotation,
        translation: newTranslation,
      ),
    );

    isAutoRotating = false;
  }

  Offset _getCrosshairScreenPoint() {
    if (state.viewportSize == null) return Offset.zero;
    final vp = state.viewportSize!;
    if (state.crosshairInCenter) {
      return Offset(vp.width / 2, vp.height / 2);
    } else {
      return Offset(vp.width / 2, vp.height * 3 / 4);
    }
  }

  void _recalculateCrosshairImagePoint() {
    if (state.imageSize == null || state.viewportSize == null) return;

    final screenPoint = _getCrosshairScreenPoint();
    final imagePoint = screenToImage(screenPoint);

    setState(() {
      state.crosshairScreenPoint = screenPoint;
      state.crosshairImagePoint = imagePoint;
    });
  }

  void _recalculateUserScreenPoint() {
    final imagePoint = state.currentUserImagePoint;
    if (imagePoint == null) return;

    setState(() {
      state.currentUserScreenPoint = imageToScreen(imagePoint);
    });
  }
}
