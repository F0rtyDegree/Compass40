// ignore_for_file: avoid_print
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter/services.dart';

final FlutterBackgroundService _service = FlutterBackgroundService();

void initializeBackgroundService() {
  _service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      notificationChannelId: 'compass40_tracking_channel',
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
  print('🔔 updateNotification called with title: $_currentTitle, content: $_currentContent');
  _notificationChannel.invokeMethod('updateNotification', {
    'title': _currentTitle,
    'content': _currentContent,
  });
}

void startBackgroundService() {
  _service.startService();
}

void stopBackgroundService() {
  _service.invoke('stopService');
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) {
  service.on('stopService').listen((_) {
    service.stopSelf();
  });

  service.on('startRecording').listen((_) {
    print('[BackgroundService] ▶️ Запись (удержание процесса)');
  });

  service.on('stopRecording').listen((_) {
    print('[BackgroundService] ⏹️ Запись остановлена');
  });
}
