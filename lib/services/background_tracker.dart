// ignore_for_file: avoid_print
import 'package:flutter_background_service/flutter_background_service.dart';

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