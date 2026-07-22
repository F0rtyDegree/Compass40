// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'app/my_app.dart';
import 'theme_provider.dart';
import 'services/background_tracker.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _createNotificationChannel() async {
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'compass40_tracking_channel', // id
    'Compass40 трекер',           // название
    description: 'Уведомление о записи трека в фоне',
    importance: Importance.low,
  );

  await _notificationsPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(channel);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Compass40 START');
  
  // Создаём канал уведомлений ДО запуска сервиса
  await _createNotificationChannel();

  // Инициализация фонового сервиса
  initializeBackgroundService();
  startBackgroundService();

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
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('Storage permission is required to run this app.'),
        ),
      ),
    ));
  }
}