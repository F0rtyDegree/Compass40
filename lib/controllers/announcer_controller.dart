/// Мост между интентом ACTION_ANNOUNCE_TARGET и активным HomeLogic.
/// Не знает о HomeLogic напрямую — регистрируется колбэк.
class AnnouncerController {
  static final AnnouncerController _instance = AnnouncerController._();
  factory AnnouncerController() => _instance;
  AnnouncerController._();

  Future<void> Function({int? period})? _handler;

  void register(Future<void> Function({int? period}) handler) {
    _handler = handler;
  }

  void unregister() {
    _handler = null;
  }

  Future<void> announce({int? period}) async {
    await _handler?.call(period: period);
  }
}