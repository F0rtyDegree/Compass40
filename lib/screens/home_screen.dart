import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import 'package:my_compass/my_compass.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:developer' as developer;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:collection/collection.dart';

import '../about_screen.dart';
import '../settings_screen.dart';
import '../theme_provider.dart';
import '../log_entry.dart';
import '../log_screen.dart';
import '../target_screen.dart';
import '../utils/geo_utils.dart';
import '../widgets/compass_section.dart';
import '../widgets/gps_section.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final GpsInfo _gpsInfo = GpsInfo();
  late StreamSubscription<GpsData> _gpsDataSubscription;
  late StreamSubscription<List<double>> _compassSubscription;

  final ValueNotifier<GpsData> _gpsDataNotifier = ValueNotifier(GpsData());
  final ValueNotifier<double> _headingNotifier = ValueNotifier(0);
  final ValueNotifier<double> _accuracyNotifier = ValueNotifier(0);

  double _magneticDeclination = 0.0;
  bool _useManualDeclination = false;

  GpsData? _waypoint;
  final ValueNotifier<double?> _distanceToWaypoint = ValueNotifier(null);
  final ValueNotifier<double?> _bearingToWaypoint = ValueNotifier(null);

  GpsData? _targetCalculationStartPoint;
  Map<String, double>? _target;
  final ValueNotifier<double?> _distanceToTarget = ValueNotifier(null);
  final ValueNotifier<double?> _bearingToTarget = ValueNotifier(null);

  List<LogItem> _logItems = [];
  final List<(double, int)> _headingSamples = [];
  Timer? _uiUpdateTimer;
  int _averagingPeriod = 500;
  int _uiUpdatePeriod = 250;

  double _filteredHeading = 0.0;
  double _smoothingFactor = 0.5;

  static const int _maxSamples = 50;

  @override
  void initState() {
    super.initState();
    Provider.of<ThemeProvider>(context, listen: false).loadTheme();
    _loadAllSettings();
    _loadLogEntries();
    _requestPermissions();
  }

  // ----------------------------------------------------------------------
  // ----------------------- МАГНИТНАЯ СИСТЕМА ----------------------------
  // ----------------------------------------------------------------------

  void _startUiUpdateTimer() {
    _uiUpdateTimer?.cancel();
    _uiUpdateTimer =
        Timer.periodic(Duration(milliseconds: _uiUpdatePeriod), (timer) {
      if (mounted) {
        _updateHeading();
        _calculateWaypointData();
        _calculateTargetData();
      }
    });
  }

  void _updateHeading() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _headingSamples.removeWhere((s) => now - s.$2 > _averagingPeriod);
    if (_headingSamples.isEmpty) return;

    double sinSum = 0, cosSum = 0;
    for (var s in _headingSamples) {
      final a = s.$1 * math.pi / 180;
      sinSum += math.sin(a);
      cosSum += math.cos(a);
    }
    final avgSin = sinSum / _headingSamples.length;
    final avgCos = cosSum / _headingSamples.length;
    final avgHeading = math.atan2(avgSin, avgCos) * 180 / math.pi;

    double diff = avgHeading - _filteredHeading;
    if (diff.abs() > 180) diff += (diff > 0) ? -360 : 360;
    _filteredHeading += _smoothingFactor * diff;
    _filteredHeading = (_filteredHeading + 360) % 360;

    _headingNotifier.value = _filteredHeading;
  }

  Future<void> _loadAllSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;

    setState(() {
      _useManualDeclination = prefs.getBool('useManualDeclination') ?? false;
      if (_useManualDeclination) {
        _magneticDeclination = prefs.getDouble('manualDeclination') ?? 0.0;
      } else {
        _magneticDeclination = 0.0;
      }
      _averagingPeriod = prefs.getInt('averagingPeriod') ?? 500;
      _smoothingFactor = prefs.getDouble('smoothingFactor') ?? 0.5;
      _uiUpdatePeriod = prefs.getInt('uiUpdatePeriod') ?? 250;
    });
    _startUiUpdateTimer();
  }

  void _requestPermissions() async {
    if (await Permission.location.request().isGranted) {
      _subscribeToGpsDataStream();
      _subscribeToCompassStream();
    }
  }

  void _subscribeToGpsDataStream() async {
    final prefs = await SharedPreferences.getInstance();
    final interval = prefs.getInt('gpsUpdateInterval') ?? 1;

    _gpsDataSubscription = _gpsInfo
        .getGpsDataStream(interval * 1000)
        .handleError((error, stack) {
      developer.log('Error in GPS stream',
          name: 'by.fortydegree.testgps', error: error, stackTrace: stack);
    }).listen((gpsData) {
      if (!mounted) return;
      _gpsDataNotifier.value = gpsData;
      if (!_useManualDeclination) {
        setState(() {
          _magneticDeclination = gpsData.magneticDeclination ?? 0.0;
        });
      }
    });
  }

  void _subscribeToCompassStream() {
    _compassSubscription = MyCompass.events.listen((data) {
      if (!mounted || data.isEmpty) return;
      final heading = data[0];
      final accuracy = data.length > 1 ? data[1] : 0.0;
      if (accuracy < 2) return;

      _headingSamples.add((heading, DateTime.now().millisecondsSinceEpoch));
      if (_headingSamples.length > _maxSamples) _headingSamples.removeAt(0);
      _accuracyNotifier.value = accuracy;
      if (_headingSamples.length == 1) {
        _filteredHeading = heading;
        _headingNotifier.value = heading;
      }
    });
  }

  // ----------------------------------------------------------------------
  // Расчёты навигации
  // ----------------------------------------------------------------------

  void _calculateWaypointData() {
    if (_waypoint == null || _gpsDataNotifier.value.latitude == null) return;
    final nowData = _gpsDataNotifier.value;
    _distanceToWaypoint.value = calculateDistance(
      _waypoint!.latitude!,
      _waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
   );
    final trueBearing = calculateTrueBearing(
      _waypoint!.latitude!,
      _waypoint!.longitude!,
      nowData.latitude!,
      nowData.longitude!,
    );
    _bearingToWaypoint.value = (trueBearing - _magneticDeclination + 360) % 360;
  }

  void _calculateTargetData() {
    if (_target == null || _gpsDataNotifier.value.latitude == null) return;
    final nowData = _gpsDataNotifier.value;
    _distanceToTarget.value = calculateDistance(
      nowData.latitude!,
      nowData.longitude!,
      _target!['latitude']!,
      _target!['longitude']!,
    );
    final trueBearing = calculateTrueBearing(
      nowData.latitude!,
      nowData.longitude!,
      _target!['latitude']!,
      _target!['longitude']!,
    );
     _bearingToTarget.value = (trueBearing - _magneticDeclination + 360) % 360;
  }


  // ----------------------------------------------------------------------
  // --- Работа с логами и контрольными точками --------------------------
  // ----------------------------------------------------------------------

  Future<void> _loadLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final String? logJson = prefs.getString('log_items');
    if (mounted) {
      setState(() {
        if (logJson != null) {
          try {
            final List<dynamic> decodedList = jsonDecode(logJson);
            _logItems = decodedList.map((e) => logItemFromJson(e)).toList();
          } catch (e) {
            _logItems = [];
          }
        } else {
          _logItems = [];
        }
      });
    }
  }

  Future<void> _saveLogEntries() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'log_items',
      jsonEncode(_logItems.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _setWaypoint() async {
    final currentGpsData = _gpsDataNotifier.value;
    if (currentGpsData.latitude == null || currentGpsData.longitude == null) {
      return; 
    }

    // Загружаем актуальный список логов
    await _loadLogEntries();

    // Находим последнюю "незавершенную" запись (КП, для которой еще не посчитали дистанцию)
    final lastIncompleteEntry = _logItems.lastWhereOrNull(
      (item) => item is LogEntry && item.distance == null
    ) as LogEntry?;

    // Если такая запись есть, "завершаем" ее
    if (lastIncompleteEntry != null) {
      final distance = calculateDistance(
        lastIncompleteEntry.latitude,
        lastIncompleteEntry.longitude,
        currentGpsData.latitude!,
        currentGpsData.longitude!,
      );
      final bearing = calculateTrueBearing(
        lastIncompleteEntry.latitude,
        lastIncompleteEntry.longitude,
        currentGpsData.latitude!,
        currentGpsData.longitude!,
      );
      // Пересчитываем в магнитный азимут для сохранения
      lastIncompleteEntry.distance = distance;
      lastIncompleteEntry.bearing = (bearing - _magneticDeclination + 360) % 360;
    }

    // Создаем НОВУЮ "незавершенную" запись для ТЕКУЩЕЙ точки
    final existingTrackEntries = _logItems.whereType<LogEntry>();
    final newId = existingTrackEntries.isEmpty
        ? 1
        : existingTrackEntries.map((e) => e.id).reduce(math.max) + 1;

    final newEntry = LogEntry(
      id: newId,
      latitude: currentGpsData.latitude!,
      longitude: currentGpsData.longitude!,
      // distance и bearing остаются null, т.к. это новая точка
    );
    
    setState(() {
      _logItems.add(newEntry);
      _waypoint = currentGpsData; // Обновляем _waypoint для UI
    });

    // Сохраняем весь обновленный список логов
    await _saveLogEntries();
  }

  Future<void> _clearWaypoint() async {
    // Эта функция теперь удаляет последнюю созданную, но не завершенную точку.
    await _loadLogEntries();
    final lastIncompleteEntry = _logItems.lastWhereOrNull(
      (item) => item is LogEntry && item.distance == null
    );

    if (lastIncompleteEntry != null) {
      setState(() {
        _logItems.remove(lastIncompleteEntry);
        // Обновляем _waypoint на предпоследнюю точку или null
        final previousEntry = _logItems.lastWhereOrNull((item) => item is LogEntry) as LogEntry?;
        if (previousEntry != null) {
            _waypoint = GpsData(latitude: previousEntry.latitude, longitude: previousEntry.longitude);
        } else {
            _waypoint = null;
        }
        _distanceToWaypoint.value = null;
        _bearingToWaypoint.value = null;
      });
      await _saveLogEntries();
    } else {
       // Если незавершенных нет, просто чистим UI
       setState(() {
        _waypoint = null;
        _distanceToWaypoint.value = null;
        _bearingToWaypoint.value = null;
      });
    }
  }
  
  // Функция для логгирования создания цели, если понадобится
  Future<void> _addTargetCreationLogEntry({
    required double baseLatitude,
    required double baseLongitude,
    required double azimuth,
    required double distance,
    required double targetLatitude,
    required double targetLongitude,
  }) async {
    await _loadLogEntries();
    final newId = _logItems.whereType<TargetCreationLogEntry>().isNotEmpty
        ? _logItems
                .whereType<TargetCreationLogEntry>()
                .map((e) => e.id)
                .reduce(math.max) +
            1
        : 1;
    final entry = TargetCreationLogEntry(
      id: newId,
      baseLatitude: baseLatitude,
      baseLongitude: baseLongitude,
      azimuth: azimuth,
      distance: distance,
      targetLatitude: targetLatitude,
      targetLongitude: targetLongitude,
    );
    setState(() => _logItems.add(entry));
    await _saveLogEntries();
  }


  // ----------------------------------------------------------------------
  // --- Сервисная информация и цвета ------------------------------------
  // ----------------------------------------------------------------------

  String _getAccuracyText(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return 'Низкая (калибруйте)';
      case 1:
        return 'Средняя';
      case 2:
        return 'Высокая';
      case 3:
        return 'Отличная';
      default:
        return 'Неизвестно';
    }
  }

  Color _getAccuracyStatusColor(double accuracy) {
    switch (accuracy.toInt()) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  void dispose() {
    _uiUpdateTimer?.cancel();
    _gpsDataSubscription.cancel();
    _compassSubscription.cancel();
    _gpsDataNotifier.dispose();
    _headingNotifier.dispose();
    _accuracyNotifier.dispose();
    _distanceToWaypoint.dispose();
    _bearingToWaypoint.dispose();
    _distanceToTarget.dispose();
    _bearingToTarget.dispose();
    super.dispose();
  }

  String _getCardinalDirection(double heading) {
    if (heading >= 337.5 || heading < 22.5) return 'Север';
    if (heading >= 22.5 && heading < 67.5) return 'С-Восток';
    if (heading >= 67.5 && heading < 112.5) return 'Восток';
    if (heading >= 112.5 && heading < 157.5) return 'Ю-Восток';
    if (heading >= 157.5 && heading < 202.5) return 'Юг';
    if (heading >= 202.5 && heading < 247.5) return 'Ю-Запад';
    if (heading >= 247.5 && heading < 292.5) return 'Запад';
    if (heading >= 292.5 && heading < 337.5) return 'С-Запад';
    return '--';
  }

  // ----------------------------------------------------------------------
  // -----------------------  UI  ----------------------------------------
  // ----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compass 40°'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              ).then((_) => _loadAllSettings());
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const AboutScreen()),
              );
            },
          )
        ],
      ),
      body: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          CompassSection(
            headingNotifier: _headingNotifier,
            accuracyNotifier: _accuracyNotifier,
            bearingToTarget: _bearingToTarget,
            bearingToWaypoint: _bearingToWaypoint,
            logItems: _logItems,
            setWaypoint: _setWaypoint,
            clearWaypoint: _clearWaypoint,
            onVerticalDragEnd: (details) async {
              if (details.primaryVelocity! < 0) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (c) => LogScreen(logItems: _logItems)),
                ).then((_) => _loadLogEntries());
              } else if (details.primaryVelocity! > 0) {
                _targetCalculationStartPoint = _gpsDataNotifier.value;
                final result = await Navigator.push<Map<String, dynamic>>(
                  context,
                  MaterialPageRoute(builder: (context) => const TargetScreen()),
                );
                if (result == null) return;

                final useClipboardAsBase = result['useClipboardAsBase'] as bool? ?? false;
                double startLat, startLon;
                if (useClipboardAsBase) {
                  startLat = result['base_latitude'] as double;
                  startLon = result['base_longitude'] as double;
                } else {
                  if (_targetCalculationStartPoint?.latitude == null) return;
                  startLat = _targetCalculationStartPoint!.latitude!;
                  startLon = _targetCalculationStartPoint!.longitude!;
                }

                final magneticAzimuth = result['azimuth'] as double;
                final trueBearing = (magneticAzimuth + _magneticDeclination + 360) % 360;
                final coords = calculateTargetCoordinates(
                  startLat: startLat,
                  startLon: startLon,
                  distanceMeters: result['distance'] as double,
                  trueBearingDegrees: trueBearing,
                );
                setState(() => _target = coords);

                await _addTargetCreationLogEntry(
                  baseLatitude: startLat,
                  baseLongitude: startLon,
                  azimuth: magneticAzimuth,
                  distance: result['distance'] as double,
                  targetLatitude: coords['latitude']!,
                  targetLongitude: coords['longitude']!,
                );
              }
            },
            getCardinalDirection: _getCardinalDirection,
            getAccuracyStatusColor: _getAccuracyStatusColor,
            getAccuracyText: _getAccuracyText,

          ),
          GpsSection(
            gpsDataNotifier: _gpsDataNotifier,
            accuracyNotifier: _accuracyNotifier,
            distanceToTarget: _distanceToTarget,
            bearingToTarget: _bearingToTarget,
            distanceToWaypoint: _distanceToWaypoint,
            bearingToWaypoint: _bearingToWaypoint,
            waypoint: _waypoint,
            target: _target,
            logItems: _logItems,
            magneticDeclination: _magneticDeclination,
          ),
        ],
      ),
    );
  }
}
