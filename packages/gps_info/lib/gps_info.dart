import 'dart:async';
import 'package:flutter/services.dart';
import 'package:gps_info/gps_data.dart';

export 'gps_data.dart'; // Экспортируем модель

class GpsInfo {
  static const EventChannel _gpsDataChannel = EventChannel(
    'com.example.gps_info/gps_data_stream',
  );

  Stream<GpsData> getGpsDataStream([int? interval]) {
    return _gpsDataChannel
        .receiveBroadcastStream(interval)
        .map<GpsData>(
          (dynamic data) => GpsData.fromMap(data as Map<dynamic, dynamic>),
        );
  }
}
