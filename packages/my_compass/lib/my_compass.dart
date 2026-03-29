import 'dart:async';

import 'package:flutter/services.dart';

class MyCompass {
  static const EventChannel _eventChannel = EventChannel('my_compass/events');
  static Stream<List<double>>? _headingStream;

  static Stream<List<double>> get events {
    _headingStream ??= _eventChannel.receiveBroadcastStream().map((dynamic event) {
      if (event is List) {
        return event.cast<double>();
      }
      // Handle the case where a single double is received for backward compatibility or error
      if (event is double) {
        return [event, 0.0]; // Default accuracy to 0.0
      }
      return [0.0, 0.0]; // Default value in case of unexpected type
    });
    return _headingStream!;
  }
}
