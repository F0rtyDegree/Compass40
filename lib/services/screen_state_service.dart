// ignore_for_file: avoid_print

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

/// Отслеживает состояние экрана Android.
/// Источник — нативный BroadcastReceiver ACTION_SCREEN_ON / ACTION_SCREEN_OFF.
class ScreenStateService {
  static final ScreenStateService _instance = ScreenStateService._();
  factory ScreenStateService() => _instance;
  ScreenStateService._();

  static const MethodChannel _channel =
      MethodChannel('by.fortydegree.compass40/screen');

  final ValueNotifier<bool> isScreenOn = ValueNotifier<bool>(true);
  bool _listening = false;

  void start() {
    if (_listening) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'on':
          isScreenOn.value = true;
          break;
        case 'off':
          isScreenOn.value = false;
          break;
      }
    });
    _listening = true;
  }

  void stop() {
    if (!_listening) return;
    _channel.setMethodCallHandler(null);
    _listening = false;
  }
}