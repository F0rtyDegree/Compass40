// ignore_for_file: avoid_print
import 'dart:developer' as developer;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'app/my_app.dart';
import 'theme_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  print('Compass40 START - Requesting permissions');
  developer.log('+++ APP Compass40 START +++', name: 'by.fortydegree.compass40');

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
