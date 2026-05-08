import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/help_viewer_screen.dart';
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
  final _gpsAveragingSamplesController = TextEditingController();
  final _rotateModeTimeoutController = TextEditingController();
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
    _gpsAveragingSamplesController.text =
        (prefs.getInt('gpsAveragingSamples') ?? 3).toString();
    _rotateModeTimeoutController.text =
        (prefs.getInt('rotateModeTimeoutMs') ?? 1000).toString();

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

    final gpsSamples = int.tryParse(_gpsAveragingSamplesController.text);
    await prefs.setInt('gpsAveragingSamples', gpsSamples ?? 3);

    final rotateTimeout = int.tryParse(_rotateModeTimeoutController.text);
    await prefs.setInt('rotateModeTimeoutMs', rotateTimeout ?? 1000);
  }



  Widget _buildTextFieldRow(
    String label,
    TextEditingController controller,
    String hint, {
    bool isInt = true,
    String? suffix,
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
              suffixText: suffix,
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
    _gpsAveragingSamplesController.dispose();
    _rotateModeTimeoutController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HelpViewerScreen(
                    helpFilePath: 'assets/help/settings_help.md',
                  ),
                ),
              );
            },
          ),
        ],
      ),
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
                  // === Интерфейс ===
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Интерфейс', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Тема',
                        style: Theme.of(context).textTheme.titleMedium,
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
                  const SizedBox(height: 16),
                  _buildTextFieldRow(
                    'Частота UI:',
                    _uiUpdatePeriodController,
                    '250',
                    suffix: 'мс',
                  ),
                  const SizedBox(height: 24),
                  const Divider(),

                  // === Компас ===
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Компас', style: Theme.of(context).textTheme.titleLarge),
                  ),
                   Row(
                    children: [
                      Text('Режим:', style: Theme.of(context).textTheme.titleMedium),
                      const Spacer(),
                      PopupMenuButton<CompassMode>(
                        onSelected: (mode) {
                          setState(() => _compassMode = mode);
                          _saveSettings();
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: CompassMode.magnetic,
                            child: Text('Магнитный'),
                          ),
                          const PopupMenuItem(
                            value: CompassMode.gps,
                            child: Text('GPS'),
                          ),
                          const PopupMenuItem(
                            value: CompassMode.auto,
                            child: Text('Авто'),
                          ),
                        ],
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _compassMode == CompassMode.magnetic
                                  ? 'Магнитный'
                                  : _compassMode == CompassMode.gps
                                      ? 'GPS'
                                      : 'Авто',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                            const Icon(Icons.arrow_drop_down),
                          ],
                        ),
                      ),
                      if (_compassMode == CompassMode.auto) ...[
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: _autoSwitchSpeedController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.end,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              suffixText: 'км/ч',
                            ),
                            onChanged: (_) => _saveSettings(),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                   _buildTextFieldRow(
                    'Интервал GPS:',
                    _gpsIntervalController,
                    '1',
                    suffix: 'сек',
                  ),
                  const SizedBox(height: 16),
                  _buildTextFieldRow(
                    'Сэмплы GPS:',
                    _gpsAveragingSamplesController,
                    '3',
                    isInt: true,
                    suffix: 'шт',
                  ),
                  const SizedBox(height: 16),
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
                  _buildTextFieldRow(
                    'Стабилизация сенсоров:',
                    _averagingPeriodController,
                    '500',
                    suffix: 'мс',
                  ),
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 24),
                  const Divider(),
                  
                  // === Карта ===
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8.0),
                    child: Text('Карта', style: Theme.of(context).textTheme.titleLarge),
                  ),
                  _buildTextFieldRow(
                    'Сброс режима вращения:',
                    _rotateModeTimeoutController,
                    '1000',
                    suffix: 'мс',
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
