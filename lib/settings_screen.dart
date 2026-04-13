import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';
import 'controllers/home_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<void> _settingsFuture;
  bool _useManualDeclination = false;
  final _declinationController = TextEditingController();
  final _averagingPeriodController = TextEditingController();
  final _gpsIntervalController = TextEditingController();
  final _uiUpdatePeriodController = TextEditingController();
  final _autoSwitchSpeedController = TextEditingController();
  double _smoothingFactor = 0.5;
  CompassMode _compassMode = CompassMode.magnetic;

  @override
  void initState() {
    super.initState();
    _settingsFuture = _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    _useManualDeclination = prefs.getBool('useManualDeclination') ?? false;
    _declinationController.text = (prefs.getDouble('manualDeclination') ?? '')
        .toString();
    _averagingPeriodController.text = (prefs.getInt('averagingPeriod') ?? 500)
        .toString();
    _gpsIntervalController.text = (prefs.getInt('gpsUpdateInterval') ?? 1)
        .toString();
    _uiUpdatePeriodController.text = (prefs.getInt('uiUpdatePeriod') ?? 250)
        .toString();
    _autoSwitchSpeedController.text =
        (prefs.getDouble('autoSwitchSpeedKmh') ?? 3.0).toString();

    double smoothingFactor = prefs.getDouble('smoothingFactor') ?? 0.5;
    smoothingFactor = smoothingFactor.clamp(0.01, 0.99);
    _smoothingFactor = smoothingFactor;

    final modeIndex = prefs.getInt('compassMode') ?? 0;
    _compassMode = CompassMode.values[modeIndex];
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool('useManualDeclination', _useManualDeclination);

    final declination = double.tryParse(_declinationController.text);
    if (declination != null) {
      await prefs.setDouble('manualDeclination', declination);
    } else {
      await prefs.remove('manualDeclination');
    }

    final period = int.tryParse(_averagingPeriodController.text);
    await prefs.setInt('averagingPeriod', period ?? 500);

    final interval = int.tryParse(_gpsIntervalController.text);
    await prefs.setInt('gpsUpdateInterval', interval ?? 1);

    final uiPeriod = int.tryParse(_uiUpdatePeriodController.text);
    await prefs.setInt('uiUpdatePeriod', uiPeriod ?? 250);

    await prefs.setDouble('smoothingFactor', _smoothingFactor);
    await prefs.setInt('compassMode', _compassMode.index);

    final autoSpeed = double.tryParse(_autoSwitchSpeedController.text);
    await prefs.setDouble('autoSwitchSpeedKmh', autoSpeed ?? 3.0);
  }

  Widget _buildTextFieldRow(
    String label,
    TextEditingController controller,
    String hint, {
    bool isInt = true,
  }) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.end,
            keyboardType: TextInputType.numberWithOptions(
              decimal: !isInt,
              signed: true,
            ),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (_) => _saveSettings(),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _declinationController.dispose();
    _averagingPeriodController.dispose();
    _gpsIntervalController.dispose();
    _uiUpdatePeriodController.dispose();
    _autoSwitchSpeedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: FutureBuilder(
        future: _settingsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox.shrink();
          }
          if (snapshot.hasError) {
            return const Center(child: Text('Ошибка загрузки настроек'));
          }

          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Тема
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Тема',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Светлая'),
                            icon: Icon(Icons.light_mode),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Темная'),
                            icon: Icon(Icons.dark_mode),
                          ),
                        ],
                        selected: {
                          themeProvider.themeMode == ThemeMode.system
                              ? ThemeMode.light
                              : themeProvider.themeMode,
                        },
                        onSelectionChanged: (s) =>
                            themeProvider.setThemeMode(s.first),
                        showSelectedIcon: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ✅ Режим компаса
                  Text(
                    'Режим компаса',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<CompassMode>(
                    segments: const [
                      ButtonSegment(
                        value: CompassMode.magnetic,
                        label: Text('Магнитный'),
                        icon: Icon(Icons.explore),
                      ),
                      ButtonSegment(
                        value: CompassMode.gps,
                        label: Text('GPS'),
                        icon: Icon(Icons.satellite_alt),
                      ),
                      ButtonSegment(
                        value: CompassMode.auto,
                        label: Text('Авто'),
                        icon: Icon(Icons.auto_mode),
                      ),
                    ],
                    selected: {_compassMode},
                    onSelectionChanged: (s) {
                      setState(() => _compassMode = s.first);
                      _saveSettings();
                    },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 16),

                  // ✅ Скорость автопереключения
                  if (_compassMode == CompassMode.auto) ...[
                    _buildTextFieldRow(
                      'Скорость авто (км/ч):',
                      _autoSwitchSpeedController,
                      '3.0',
                      isInt: false,
                    ),
                    const SizedBox(height: 16),
                  ],

                  // GPS интервал
                  _buildTextFieldRow(
                    'Интервал GPS (сек):',
                    _gpsIntervalController,
                    '1',
                  ),
                  const SizedBox(height: 16),

                  // Магнитное склонение
                  Row(
                    children: [
                      Text(
                        'Магнитное склонение:',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _useManualDeclination
                            ? TextField(
                                controller: _declinationController,
                                textAlign: TextAlign.end,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                      signed: true,
                                    ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '°',
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => _saveSettings(),
                              )
                            : const Text(
                                'авто',
                                textAlign: TextAlign.end,
                                style: TextStyle(color: Colors.grey),
                              ),
                      ),
                      const SizedBox(width: 8),
                      Switch(
                        value: _useManualDeclination,
                        onChanged: (v) {
                          setState(() => _useManualDeclination = v);
                          _saveSettings();
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Усреднение
                  _buildTextFieldRow(
                    'Усреднение (мс):',
                    _averagingPeriodController,
                    '500',
                  ),
                  const SizedBox(height: 16),

                  // Сглаживание
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        'плавная',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'Стрелка',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        'быстрая',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  Slider(
                    value: _smoothingFactor,
                    min: 0.01,
                    max: 0.99,
                    divisions: 98,
                    label: _smoothingFactor.toStringAsFixed(2),
                    onChanged: (v) => setState(() => _smoothingFactor = v),
                    onChangeEnd: (_) => _saveSettings(),
                  ),
                  const SizedBox(height: 8),

                  // Частота UI
                  _buildTextFieldRow(
                    'Частота UI (мс):',
                    _uiUpdatePeriodController,
                    '250',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
