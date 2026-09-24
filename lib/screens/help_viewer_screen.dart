import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpViewerScreen extends StatelessWidget {
  final String helpFilePath;

  const HelpViewerScreen({super.key, required this.helpFilePath});

  // Markdown грузится при каждом открытии экрана без кэша.
  // Осознанно: файл маленький (несколько КБ), чтение из ассетов —
  // миллисекунды, экран открывается редко. Кэш добавил бы глобальное
  // состояние и инвалидацию ради неощутимой экономии.
  // Возвращаться к вопросу — только если появится реальная задержка.
  Future<String> _loadHelpContent(BuildContext context) async {
    try {
      return await rootBundle.loadString(helpFilePath);
    } catch (e) {
      return '### Ошибка\nНе удалось загрузить файл справки.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Справка'),
      ),
      body: FutureBuilder<String>(
        future: _loadHelpContent(context),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('Ошибка загрузки справки'));
          } else if (snapshot.hasData) {
            return Markdown(data: snapshot.data!);
          } else {
            return const Center(child: Text('Нет данных'));
          }
        },
      ),
    );
  }
}
