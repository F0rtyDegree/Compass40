import 'package:compass40/controllers/map_screen_logic.dart';

class MapScreenController {
  static final MapScreenController _instance = MapScreenController._();
  factory MapScreenController() => _instance;
  MapScreenController._();

  MapScreenLogic? _logic;

  void register(MapScreenLogic logic) {
    _logic = logic;
  }

  void unregister() {
    _logic = null;
  }

  void zoomIn() {
    _logic?.zoomIn();
  }

  void zoomOut() {
    _logic?.zoomOut();
  }

  void toggleFollowMode() {
    _logic?.toggleFollowMode();
  }
}