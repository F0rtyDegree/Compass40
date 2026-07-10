// ignore_for_file: avoid_print
import 'dart:developer' as developer; 
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/my_app.dart';
import 'theme_provider.dart';

void main() {
   print('=== APP Compass40 START ===');
   developer.log('START', name: 'by.fortydegree.compass40');
   
  runApp(
    ChangeNotifierProvider(
      create: (context) => ThemeProvider(),
      child: const MyApp(),
    ),
  );
}
