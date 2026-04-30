import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

class HelpViewerScreen extends StatelessWidget {
  final String helpFilePath;

  const HelpViewerScreen({super.key, required this.helpFilePath});

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
