import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TargetScreen extends StatefulWidget {
  const TargetScreen({super.key});

  @override
  State<TargetScreen> createState() => _TargetScreenState();
}

class _TargetScreenState extends State<TargetScreen> {
  final _azimuthController = TextEditingController();
  final _distanceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // Обычное нажатие: использует текущее местоположение как базу.
  void _setTarget() {
    if (_formKey.currentState!.validate()) {
      final azimuth = double.tryParse(_azimuthController.text) ?? 0.0;
      final distance = double.tryParse(_distanceController.text) ?? 0.0;
      Navigator.pop(context, {
        'azimuth': azimuth,
        'distance': distance,
        'useClipboardAsBase': false, // Явно указываем, что база - не из буфера
      });
    }
  }

  // Долгое нажатие: использует координаты из буфера как базу для расчета.
  Future<void> _setTargetWithClipboardBase() async {
    final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;

    if (clipboardData == null || clipboardData.text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Буфер обмена пуст')),
      );
      return;
    }

    final coords = clipboardData.text!.split(',');
    if (coords.length == 2) {
      final lat = double.tryParse(coords[0].trim());
      final lon = double.tryParse(coords[1].trim());

      if (lat != null && lon != null) {
        // Берем азимут и дистанцию из полей, если пустые - то 0.
        final azimuth = double.tryParse(_azimuthController.text) ?? 0.0;
        final distance = double.tryParse(_distanceController.text) ?? 0.0;
        
        // Возвращаем все данные для расчета на главный экран
        Navigator.pop(context, {
          'base_latitude': lat,
          'base_longitude': lon,
          'azimuth': azimuth,
          'distance': distance,
          'useClipboardAsBase': true, // Явно указываем, что база из буфера
        });

      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный формат координат в буфере обмена')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный формат координат в буфере обмена')),
      );
    }
  }

  @override
  void dispose() {
    _azimuthController.dispose();
    _distanceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Установить цель'),
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
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                  if (value == null || value.isEmpty) return null; // Пустое поле валидно (будет 0)
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
                  hintText: '0-360 (0 по умолчанию)',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (value) {
                   if (value == null || value.isEmpty) return null; // Пустое поле валидно (будет 0)
                  final n = double.tryParse(value);
                  if (n == null) {
                    return 'Введите корректное число';
                  }
                  if (n < 0 || n > 360) {
                    return 'Азимут должен быть в диапазоне 0-360';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 32),
              GestureDetector(
                onLongPress: _setTargetWithClipboardBase, // Долгое нажатие
                child: ElevatedButton(
                  onPressed: _setTarget, // Обычное нажатие
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    textStyle: const TextStyle(fontSize: 18),
                  ),
                  child: const Text('Начать ведение к Цели'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
