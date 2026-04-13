import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'my_compass_platform_interface.dart';

/// An implementation of [MyCompassPlatform] that uses method channels.
class MethodChannelMyCompass extends MyCompassPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('my_compass');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
