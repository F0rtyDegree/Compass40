import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '...';

  @override
  void initState() {
    super.initState();
    _getVersion();
  }

  Future<void> _getVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = packageInfo.version;
      });
    }
  }

  Widget _buildFeatureText(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodyLarge,
          children: [
            TextSpan(
              text: '$title: ',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            TextSpan(text: subtitle),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('О приложении')),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Compass 40°',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'v$_version',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha((255 * 0.6).round()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Это цифровой компас с расширенными возможностями.',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 24),
              Text(
                'Ключевые возможности:',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildFeatureText(
                'Точный компас',
                'Указывает направление в градусах с цветовой индикацией сторон света и подсказками "Розы ветров".',
              ),
              _buildFeatureText(
                'GPS-панель',
                'Отображает вашу скорость, текущие координаты, высоту над уровнем моря и точность GPS-сигнала.',
              ),
              _buildFeatureText(
                'Навигация к цели',
                'Вы можете задать координаты целевой точки, и приложение будет указывать направление и оставшееся расстояние до нее.',
              ),
              _buildFeatureText(
                'Журнал маршрута',
                'Сохраняйте важные точки вашего пути в виде логов, чтобы иметь возможность вернуться к ним позже.',
              ),
              _buildFeatureText(
                'Гибкие настройки',
                'Персонализируйте приложение, выбирая между светлой и темной темами, вводя поправку на магнитное склонение и настраивая плавность анимации компаса.',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
