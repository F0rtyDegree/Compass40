// ignore_for_file: avoid_print
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/services.dart';
import '../utils/app_constants.dart';

final FlutterBackgroundService _service = FlutterBackgroundService();

void initializeBackgroundService() {
  _service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: AppConstants.notificationChannelId,
      foregroundServiceNotificationId: 888,
    ),
    iosConfiguration: IosConfiguration(),
  );
}

final MethodChannel _notificationChannel = MethodChannel(
  'by.fortydegree.compass40/notification',
);

String _currentTitle = '';
String _currentContent = '';

void updateNotification({String? title, String? content}) {
  if (title != null) _currentTitle = title;
  if (content != null) _currentContent = content;
  _notificationChannel.invokeMethod('updateNotification', {
    'title': _currentTitle,
    'content': _currentContent,
  });
}

void startBackgroundService() {
  _service.startService();
}

/// Останавливает фоновый сервис и ждёт, пока Android его обработает.
/// Прямого API «дождаться остановки» у плагина нет. Проверяем isRunning
/// в цикле: обычно сервис останавливается за 100-200 мс. Максимум 10
/// итераций по 100 мс — 1 секунда. Если не остановился, закрываемся
/// всё равно, чтобы приложение не висело.
Future<void> stopBackgroundService() async {
  _service.invoke('stopService');
  for (int i = 0; i < 10; i++) {
    await Future.delayed(const Duration(milliseconds: 100));
    final running = await _service.isRunning();
    if (!running) return;
  }
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  service.on('stopService').listen((_) {
    service.stopSelf();
  });
}
