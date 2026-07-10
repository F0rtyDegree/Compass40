// ignore_for_file: avoid_print
import '../utils/app_storage_info.dart';
import 'package:flutter/material.dart';

Future<bool?> showExitConfirmDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Вы уверены?'),
      content: const Text('Вы хотите закрыть приложение?'),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Нет'),
        ),
        TextButton(
          onPressed: () async {
            final totalMB = await getTotalAppStorageMB();
            print(
              'APP STOP (all size: ~${totalMB.toStringAsFixed(1)} MB)',
            );
            if (context.mounted) {
              Navigator.of(context).pop(true);
            }
          },
          child: const Text('Да'),
        ),
      ],
    ),
  );
}
