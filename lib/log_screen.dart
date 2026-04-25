import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_entry.dart';

class LogScreen extends StatefulWidget {
  final List<LogItem> logItems;

  const LogScreen({super.key, required this.logItems});

  @override
  State<LogScreen> createState() => _LogScreenState();
  
}

class _LogScreenState extends State<LogScreen> {
  int? _copiedEntryId;
  String? _copiedEntryType;
  String? _copiedLine;

  Future<void> _clearLogAndExit() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('log_items');
    if (mounted) {
      Navigator.of(context).pop({'logCleared': true});
    }
  }

  void _copyAllToClipboard() {
    final allText = widget.logItems.reversed
        .map((entry) {
          if (entry is LogEntry) {
            final distanceText = entry.distance != null
                ? '${entry.distance!.round()}m'
                : '--m';
            final bearingText = entry.bearing != null
                ? '${entry.bearing!.round()}°'
                : '--°';
            return '${entry.id} ${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)} $distanceText $bearingText';
          } else if (entry is TargetCreationLogEntry) {
            final startText =
                'Старт: ${entry.baseLatitude.toStringAsFixed(6)},${entry.baseLongitude.toStringAsFixed(6)} ${entry.distance.round()}м ${entry.azimuth.round()}°';
            final targetText =
                'ЦЕЛЬ: ${entry.targetLatitude.toStringAsFixed(6)},${entry.targetLongitude.toStringAsFixed(6)}';
            return '$startText\n$targetText';
          } else if (entry is MapAnchorLogEntry) {
  final distanceText = entry.distanceFromPrevious != null
      ? ' ${entry.distanceFromPrevious!.round()}m'
      : ' ---';
  return 'ТП: ${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)}$distanceText ${entry.timeStr}';
}
          return '';
        })
        .join('\n');

    Clipboard.setData(ClipboardData(text: allText));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Журнал скопирован в буфер обмена'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _handleTap(LogItem entry, {String? line}) {
    String textToCopy = '';
    int? entryId;
    String entryType = '';

    if (entry is LogEntry) {
      textToCopy =
          '${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)}';
      entryId = entry.id;
      entryType = 'track';
    } else if (entry is TargetCreationLogEntry) {
      if (line == 'start') {
        textToCopy =
            '${entry.baseLatitude.toStringAsFixed(6)},${entry.baseLongitude.toStringAsFixed(6)}';
      } else {
        textToCopy =
            '${entry.targetLatitude.toStringAsFixed(6)},${entry.targetLongitude.toStringAsFixed(6)}';
      }
      entryId = entry.id;
      entryType = 'target';
    } else if (entry is MapAnchorLogEntry) {
      textToCopy = '${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)}';
      entryId = entry.id;  // ✅ сохраняем id
      entryType = 'anchor';
    }

    if (textToCopy.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: textToCopy));
      if (mounted) {
        setState(() {
          _copiedEntryId = entryId;
          _copiedEntryType = entryType;
          _copiedLine = line;
        });
        Timer(const Duration(milliseconds: 200), () {
          if (mounted) {
            setState(() {
              _copiedEntryId = null;
              _copiedEntryType = null;
              _copiedLine = null;
            });
          }
        });
      }
    }
  }

  Widget _buildLogItemWidget(LogItem entry) {
    final originalTextColor =
        Theme.of(context).textTheme.bodyLarge?.color ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white70
            : Colors.black87);
    final invertedTextColor = Theme.of(context).scaffoldBackgroundColor;

    if (entry is LogEntry) {
      final isCopied =
          entry.id == _copiedEntryId && _copiedEntryType == 'track';
      // --- Исправлено ---
      final distanceText = entry.distance != null
          ? '${entry.distance!.round()}m'
          : '--m';
      final bearingText = entry.bearing != null
          ? '${entry.bearing!.round()}°'
          : '--°';
      final text =
          '${entry.id} ${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)} $distanceText $bearingText';
      // --- Конец исправления ---
      return InkWell(
        onTap: () => _handleTap(entry),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          color: isCopied ? originalTextColor : Colors.transparent,
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 16,
              color: isCopied ? invertedTextColor : originalTextColor,
            ),
          ),
        ),
      );
    } else if (entry is TargetCreationLogEntry) {
      final isStartCopied =
          entry.id == _copiedEntryId &&
          _copiedEntryType == 'target' &&
          _copiedLine == 'start';
      final isTargetCopied =
          entry.id == _copiedEntryId &&
          _copiedEntryType == 'target' &&
          _copiedLine == 'target';

      final startText =
          'Старт: ${entry.baseLatitude.toStringAsFixed(6)},${entry.baseLongitude.toStringAsFixed(6)} ${entry.distance.round()}м ${entry.azimuth.round()}°';
      final targetText =
          'ЦЕЛЬ: ${entry.targetLatitude.toStringAsFixed(6)},${entry.targetLongitude.toStringAsFixed(6)}';
      final baseStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: originalTextColor,
      );
      final copiedStyle = TextStyle(
        fontFamily: 'monospace',
        fontSize: 14,
        color: invertedTextColor,
        fontWeight: FontWeight.bold,
      );

      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Theme.of(context).dividerColor, width: 1),
          ),
          color: Colors.blueAccent.withAlpha(30),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => _handleTap(entry, line: 'start'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                color: isStartCopied ? originalTextColor : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  startText,
                  style: isStartCopied ? copiedStyle : baseStyle,
                ),
              ),
            ),
            const SizedBox(height: 4),
            InkWell(
              onTap: () => _handleTap(entry, line: 'target'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: double.infinity,
                color: isTargetCopied ? originalTextColor : Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Text(
                  targetText,
                  style: isTargetCopied ? copiedStyle : baseStyle,
                ),
              ),
            ),
          ],
        ),
      );
      } else if (entry is MapAnchorLogEntry) {
        final isCopied = _copiedEntryId == entry.id && _copiedEntryType == 'anchor';  // ✅ проверяем по id
        final distanceText = entry.distanceFromPrevious != null
            ? ' ${entry.distanceFromPrevious!.round()}m'
            : ' ---';
        final text = 'ТП: ${entry.latitude.toStringAsFixed(6)},${entry.longitude.toStringAsFixed(6)}$distanceText ${entry.timeStr}';
        
        return InkWell(
          onTap: () => _handleTap(entry),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
            color: isCopied ? originalTextColor : Colors.transparent,
            child: Text(
              text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 16,
                color: isCopied ? invertedTextColor : originalTextColor,
              ),
            ),
          ),
        );
      }
    return const SizedBox.shrink();
  }

  @override
  Widget build(BuildContext context) {
    final reversedItems = widget.logItems.reversed.toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all),
            onPressed: _copyAllToClipboard,
            tooltip: 'Копировать все',
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever),
            onPressed: () async {
              final bool? confirm = await showDialog<bool>(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: const Text('Очистить журнал?'),
                    content: const Text('Все записи будут удалены.'),
                    actions: <Widget>[
                      TextButton(
                        child: const Text('Отмена'),
                        onPressed: () => Navigator.of(context).pop(false),
                      ),
                      TextButton(
                        child: const Text(
                          'Очистить',
                          style: TextStyle(color: Colors.red),
                        ),
                        onPressed: () => Navigator.of(context).pop(true),
                      ),
                    ],
                  );
                },
              );

              if (confirm == true) {
                await _clearLogAndExit();
              }
            },
            tooltip: 'Очистить журнал',
          ),
        ],
      ),
      body: reversedItems.isEmpty
          ? const Center(child: Text('Журнал пуст.'))
          : ListView.builder(
              itemCount: reversedItems.length,
              itemBuilder: (context, index) {
                final entry = reversedItems[index];
                return _buildLogItemWidget(entry);
              },
            ),
    );
  }
}
