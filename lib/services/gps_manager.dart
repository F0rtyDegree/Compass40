import 'dart:async';
import 'package:gps_info/gps_info.dart';
import 'sensor_service.dart';

/// Единый менеджер GPS-данных.
///
/// ВНИМАНИЕ: класс — синглтон. Таких в проекте несколько
/// (GpsManager, SensorService, CompassService, GpsCompassService,
/// TrackRecorder, MapScreenController). Это осознанное решение.
/// Синглтоны затрудняют интеграционные тесты, но:
///   - все юнит-тесты (калибровка, трансформации, утилиты) работают
///     без них и не испытывают проблем;
///   - для проверки функционала, требующего подмены зависимостей,
///     используется отдельное mock-приложение;
///   - рефакторинг на DI затрагивает все сервисы и их вызовы,
///     риск сломать работающее выше пользы.
/// Не переделывать без явной необходимости.

/// Подписывается на SensorService ровно один раз и раздаёт данные всем
/// потребителям через broadcast stream.
/// Запускается вручную через [start], останавливается через [stop].
class GpsManager {
  static final GpsManager _instance = GpsManager._();
  factory GpsManager() => _instance;
  GpsManager._();

  final SensorService _sensorService = SensorService();
  final StreamController<GpsData> _controller =
      StreamController<GpsData>.broadcast();
  StreamSubscription<GpsData>? _platformSubscription;
  bool _isRunning = false;
  bool _isDisposed = false;

  /// Поток GPS-данных для подписки.
  Stream<GpsData> get gpsStream => _controller.stream;

  /// Запустить GPS. Повторный вызов без предшествующего [stop] игнорируется.
  void start(int intervalSeconds) {
    if (_isRunning) return;
    _platformSubscription = _sensorService.subscribeToGps(
      intervalSeconds: intervalSeconds,
      onData: (data) => _controller.add(data),
    );
    _isRunning = true;
  }

  /// Остановить GPS.
  void stop() {
    if (!_isRunning) return;
    _platformSubscription?.cancel();
    _platformSubscription = null;
    _isRunning = false;
  }

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    stop();
    _controller.close();
  }
}