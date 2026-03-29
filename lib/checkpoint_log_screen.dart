
import 'package:flutter/material.dart';
import './models.dart'; // Импортируем наши модели

class CheckpointLogScreen extends StatefulWidget {
  const CheckpointLogScreen({super.key});

  @override
  State<CheckpointLogScreen> createState() => _CheckpointLogScreenState();
}

class _CheckpointLogScreenState extends State<CheckpointLogScreen> {
  // Список треков (пока что пустой, позже будем загружать из SharedPreferences)
  final List<Track> _tracks = [];

  @override
  void initState() {
    super.initState();
    // Здесь будет логика загрузки треков
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Журнал треков'),
      ),
      body: _tracks.isEmpty
          ? const Center(
              child: Text('Здесь пока нет ни одного трека.'),
            )
          : ListView.builder(
              itemCount: _tracks.length,
              itemBuilder: (context, index) {
                final track = _tracks[index];
                return ExpansionTile(
                  title: Text('Трек от ${track.startTime.day}.${track.startTime.month}.${track.startTime.year} ${track.startTime.hour}:${track.startTime.minute}'),
                  children: track.checkpoints.map((cp) {
                    return ListTile(
                      title: Text('КП #${cp.id}'),
                      subtitle: Text(
                          'Координаты: ${cp.latitude.toStringAsFixed(5)}, ${cp.longitude.toStringAsFixed(5)}\n'
                          'Дистанция: ${cp.distanceFromPrevious.toStringAsFixed(1)} м | Азимут: ${cp.azimuthFromPrevious.toStringAsFixed(1)}°'),
                    );
                  }).toList(),
                );
              },
            ),
    );
  }
}
