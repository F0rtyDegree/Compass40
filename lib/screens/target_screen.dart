import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'help_viewer_screen.dart';

class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  final _azimuthController = TextEditingController();
  final _distanceController = TextEditingController();
  final _coordsController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  void _setTarget() {
    if (_formKey.currentState!.validate()) {
      double azimuth = double.tryParse(_azimuthController.text) ?? 0.0;
      final distance = double.tryParse(_distanceController.text) ?? 0.0;
      azimuth = (azimuth % 360 + 360) % 360;

      // Проверяем, есть ли координаты в поле
      final coordsText = _coordsController.text.trim();
      if (coordsText.isNotEmpty) {
        final parts = coordsText.split(',');
        if (parts.length == 2) {
          final lat = double.tryParse(parts[0].trim());
          final lon = double.tryParse(parts[1].trim());
          if (lat != null && lon != null) {
            Navigator.pop(context, {
              'base_latitude': lat,
              'base_longitude': lon,
              'azimuth': azimuth,
              'distance': distance,
              'useClipboardAsBase': true,
            });
            return;
          }
        }
        // Если координаты есть, но формат неверный - предупреждаем
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Неверный формат координат. Ожидается: широта,долгота',
            ),
          ),
        );
        return;
      }

      // Если поле пустое - используем текущее местоположение
      Navigator.pop(context, {
        'azimuth': azimuth,
        'distance': distance,
        'useClipboardAsBase': false,
      });
    }
  }

  @override
  void dispose() {
    _azimuthController.dispose();
    _distanceController.dispose();
    _coordsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Установить цель'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const HelpViewerScreen(
                    helpFilePath: 'assets/help/target_help.md',
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _distanceController,
                decoration: const InputDecoration(
                  labelText: 'Дистанция (метры)',
                  border: OutlineInputBorder(),
                  hintText: '0 (по умолчанию)',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null; // Пустое поле валидно (будет 0)
                  }
                  final n = double.tryParse(value);
                  if (n == null || n < 0) {
                    return 'Введите корректное положительное число';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _azimuthController,
                decoration: const InputDecoration(
                  labelText: 'Азимут (градусы)',
                  border: OutlineInputBorder(),
                  hintText: 'Введите значение в градусах',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return null;
                  }
                  final n = double.tryParse(value);
                  if (n == null) {
                    return 'Введите корректное число';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _coordsController,
                      decoration: const InputDecoration(
                        labelText: 'Координаты (опционально)',
                        border: OutlineInputBorder(),
                        hintText: 'широта,долгота',
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.paste),
                    tooltip: 'Вставить из буфера обмена',
                    onPressed: () async {
                      final clipboardData = await Clipboard.getData(
                        Clipboard.kTextPlain,
                      );
                      if (clipboardData?.text != null) {
                        _coordsController.text = clipboardData!.text!;
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Буфер обмена пуст')),
                          );
                        }
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Если поле "Координаты" пустое, расчет будет от текущего местоположения',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _setTarget,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 18),
                ),
                child: const Text('Начать ведение к Цели'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}