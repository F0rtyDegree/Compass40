import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'gps_info_method_channel.dart';

abstract class GpsInfoPlatform extends PlatformInterface {
  /// Constructs a GpsInfoPlatform.
  GpsInfoPlatform() : super(token: _token);

  static final Object _token = Object();

  static GpsInfoPlatform _instance = MethodChannelGpsInfo();

  /// The default instance of [GpsInfoPlatform] to use.
  ///
  /// Defaults to [MethodChannelGpsInfo].
  static GpsInfoPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [GpsInfoPlatform] when
  /// they register themselves.
  static set instance(GpsInfoPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
