import 'dart:async';
import 'package:gps_info/gps_info.dart';
import 'sensor_service.dart';

/// Единый менеджер GPS-данных.
/// Подписывается на SensorService ровно один раз и раздаёт данные всем подписчикам через broadcast stream.
/// Автоматически запускает/останавливает платформенный GPS при появлении/исчезновении подписчиков.
class GpsManager {
  bool _isDisposed = false;
  static final GpsManager _instance = GpsManager._();
  factory GpsManager() => _instance;
  GpsManager._();

  final SensorService _sensorService = SensorService();
  final StreamController<GpsData> _controller =
      StreamController<GpsData>.broadcast();
  StreamSubscription<GpsData>? _platformSubscription;
  int _subscriberCount = 0;

  /// Поток GPS-данных для подписки.
  Stream<GpsData> get gpsStream => _controller.stream;

  /// Подписаться на GPS-данные.
  /// При первом подписчике автоматически запускается платформенный GPS.
  /// При отписке последнего подписчика GPS останавливается.
  StreamSubscription<GpsData> subscribe({
    required int intervalSeconds,
    required void Function(GpsData) onData,
    void Function(Object)? onError,
    void Function()? onDone,
  }) {
    _subscriberCount++;
    if (_subscriberCount == 1) {
      _startPlatformListening(intervalSeconds);
    }

    final subscription = gpsStream.listen(
      onData,
      onError: onError,
      onDone: onDone,
    );

    // Оборачиваем подписку, чтобы при отписке уменьшать счётчик
    final wrapped = subscription
      ..onDone(() {
        _subscriberCount--;
        if (_subscriberCount == 0) {
          _stopPlatformListening();
        }
      });

    return wrapped;
  }

  void _startPlatformListening(int intervalSeconds) {
    _platformSubscription = _sensorService.subscribeToGps(
      intervalSeconds: intervalSeconds,
      onData: (data) => _controller.add(data),
    );
  }

  void _stopPlatformListening() {
    _platformSubscription?.cancel();
    _platformSubscription = null;
  }

  /// Принудительно остановить GPS (например, при выходе из приложения).
  void forceStop() {
    _stopPlatformListening();
    _subscriberCount = 0;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    forceStop();
    _controller.close();
  }
}
