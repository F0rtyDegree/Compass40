import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'theme_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _useManualDeclination = false;
  final TextEditingController _declinationController = TextEditingController();
  final TextEditingController _averagingPeriodController =
      TextEditingController();
  final TextEditingController _gpsIntervalController = TextEditingController();
  final TextEditingController _uiUpdatePeriodController =
      TextEditingController();
  double _smoothingFactor = 0.5;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _useManualDeclination = prefs.getBool('useManualDeclination') ?? false;
      _declinationController.text =
          (prefs.getDouble('manualDeclination') ?? '').toString();
      _averagingPeriodController.text =
          (prefs.getInt('averagingPeriod') ?? 500).toString();
      _gpsIntervalController.text =
          (prefs.getInt('gpsUpdateInterval') ?? 1).toString();
      _uiUpdatePeriodController.text =
          (prefs.getInt('uiUpdatePeriod') ?? 250).toString();
      _smoothingFactor = prefs.getDouble('smoothingFactor') ?? 0.5;
      if (_smoothingFactor < 0.01) {
        _smoothingFactor = 0.01;
      }
      if (_smoothingFactor > 0.99) {
        _smoothingFactor = 0.99;
      }
    });
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
    if (period != null) {
      await prefs.setInt('averagingPeriod', period);
    } else {
      await prefs.setInt('averagingPeriod', 500);
    }

    final interval = int.tryParse(_gpsIntervalController.text);
    if (interval != null) {
      await prefs.setInt('gpsUpdateInterval', interval);
    } else {
      await prefs.setInt('gpsUpdateInterval', 1);
    }

    final uiUpdatePeriod = int.tryParse(_uiUpdatePeriodController.text);
    if (uiUpdatePeriod != null) {
      await prefs.setInt('uiUpdatePeriod', uiUpdatePeriod);
    } else {
      await prefs.setInt('uiUpdatePeriod', 250);
    }

    await prefs.setDouble('smoothingFactor', _smoothingFactor);
  }

  Widget _buildTextFieldRow(
      String label,
      TextEditingController controller,
      String hint,
      {
        bool isNumeric = true,
        bool isInt = true,
      }
    ) {
    return Row(
      children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.end,
            keyboardType: isNumeric 
              ? TextInputType.numberWithOptions(decimal: !isInt, signed: true)
              : TextInputType.text,
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onChanged: (value) => _saveSettings(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1-я строка: Тема
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Тема', style: Theme.of(context).textTheme.titleLarge),
                  SegmentedButton<ThemeMode>(
                    segments: const <ButtonSegment<ThemeMode>>[
                      ButtonSegment<ThemeMode>(
                          value: ThemeMode.light, 
                          label: Text('Светлая'), 
                          icon: Icon(Icons.light_mode)),
                      ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark, 
                          label: Text('Темная'),
                          icon: Icon(Icons.dark_mode)),
                    ],
                    selected: <ThemeMode>{themeProvider.themeMode == ThemeMode.system ? ThemeMode.light : themeProvider.themeMode},
                    onSelectionChanged: (Set<ThemeMode> newSelection) {
                      themeProvider.setThemeMode(newSelection.first);
                    },
                    showSelectedIcon: false,
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 2-я строка: Интервал обновления GPS
              _buildTextFieldRow(
                'Интервал обновления GPS (сек):',
                _gpsIntervalController,
                '1',
              ),
              const SizedBox(height: 16),

              // 3-я строка: Магнитное склонение
              Row(
                children: [
                  Text('Магнитное склонение:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _useManualDeclination
                        ? TextField(
                            controller: _declinationController,
                            textAlign: TextAlign.end,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '°',
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                            onChanged: (value) => _saveSettings(),
                          )
                        : const Text('авто', textAlign: TextAlign.end, style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  Switch(
                    value: _useManualDeclination,
                    onChanged: (value) {
                      setState(() {
                        _useManualDeclination = value;
                      });
                      _saveSettings();
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 4-я строка: Усреднение
              _buildTextFieldRow(
                'Усреднение: Период (мс):',
                _averagingPeriodController,
                '500',
              ),
              const SizedBox(height: 16),

              // 5-я и 6-я строки: Сглаживание
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Сглаживание: Фильтр:', style: Theme.of(context).textTheme.titleMedium),
                  Text(_smoothingFactor.toStringAsFixed(2), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey)),
                ],
              ),
              Slider(
                value: _smoothingFactor,
                min: 0.01,
                max: 0.99,
                divisions: 98,
                label: _smoothingFactor.toStringAsFixed(2),
                onChanged: (value) {
                  setState(() {
                    _smoothingFactor = value;
                  });
                },
                onChangeEnd: (value) {
                  _saveSettings();
                },
              ),
              const SizedBox(height: 8),

              // 7-я строка: Частота обновления UI
              _buildTextFieldRow(
                'Частота обновления UI (мс):',
                _uiUpdatePeriodController,
                '250',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
