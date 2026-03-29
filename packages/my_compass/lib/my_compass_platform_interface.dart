import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'my_compass_method_channel.dart';

abstract class MyCompassPlatform extends PlatformInterface {
  /// Constructs a MyCompassPlatform.
  MyCompassPlatform() : super(token: _token);

  static final Object _token = Object();

  static MyCompassPlatform _instance = MethodChannelMyCompass();

  /// The default instance of [MyCompassPlatform] to use.
  ///
  /// Defaults to [MethodChannelMyCompass].
  static MyCompassPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MyCompassPlatform] when
  /// they register themselves.
  static set instance(MyCompassPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
