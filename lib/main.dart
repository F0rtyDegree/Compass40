// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app/my_app.dart';
import 'theme_provider.dart';
import 'services/background_tracker.dart';

import 'package:flutter/services.dart';
import 'package:compass40/controllers/map_screen_controller.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _handleIntent(MethodCall call) async {
  switch (call.method) {
    case 'by.fortydegree.compass40.ACTION_ZOOM_IN':
      MapScreenController().zoomIn();
      break;
    case 'by.fortydegree.compass40.ACTION_ZOOM_OUT':
      MapScreenController().zoomOut();
      break;
    case 'by.fortydegree.compass40.ACTION_TOGGLE_FOLLOW':
      MapScreenController().toggleFollowMode();
      break;
    case 'by.fortydegree.compass40.ACTION_NEXT_CALIBRATION_MODE':
      MapScreenController().nextCalibrationMode();
      break;
  }
}

Future<void> _createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'compass40_tracking_channel', // id
    'Compass40 трекер', // название
    description: 'Уведомление о записи трека в фоне',
    importance: Importance.low,
  );

  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannel(channel);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('🎥 Compass40 START');

  // Создаём канал уведомлений ДО запуска сервиса
  await _createNotificationChannel();

  // Инициализация фонового сервиса
  initializeBackgroundService();
  startBackgroundService();

  // Даём сервису время создать уведомление, затем обновляем
  await Future.delayed(const Duration(milliseconds: 300));
  updateNotification(title: 'Режим - Компас', content: 'Поехали !!!');

  // Регистрируем обработчик интентов
  const MethodChannel intentChannel = MethodChannel(
    'by.fortydegree.compass40/intent',
  );
  intentChannel.setMethodCallHandler(_handleIntent);

  var status = await Permission.storage.status;
  if (!status.isGranted) {
    status = await Permission.storage.request();
  }

  var manageStatus = await Permission.manageExternalStorage.status;
  if (!manageStatus.isGranted) {
    manageStatus = await Permission.manageExternalStorage.request();
  }

  if (status.isGranted || manageStatus.isGranted) {
    print("Storage Permission Granted");
    runApp(
      ChangeNotifierProvider(
        create: (context) => ThemeProvider(),
        child: const MyApp(),
      ),
    );
  } else {
    print("Storage Permission Denied");
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text('Storage permission is required to run this app.'),
          ),
        ),
      ),
    );
  }
}
