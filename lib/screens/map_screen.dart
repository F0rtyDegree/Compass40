import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import '../services/map_storage_service.dart';
import '../controllers/map_screen_state.dart';
import '../controllers/map_screen_logic.dart';
import '../widgets/map_crosshair.dart';
import '../widgets/map_toolbar.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapStorageService _storageService = MapStorageService();
  final MapScreenState _state = MapScreenState();
  late final MapScreenLogic _logic;
  
  @override
  void initState() {
    super.initState();
    _logic = MapScreenLogic(
      state: _state,
      hostState: this,
      storageService: _storageService,
      gpsInfo: GpsInfo(),
    );
    _logic.init();
  }
  
  @override
  void dispose() {
    _logic.dispose();
    super.dispose();
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Спорткарта'),
        centerTitle: true,
        actions: [
          if (_state.imagePath != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => _logic.closeMap(),
              tooltip: 'Закрыть карту',
            ),
        ],
      ),
      body: _state.imagePath == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.map, size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('Нет загруженной карты'),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: () => _logic.pickImage(),
                    icon: const Icon(Icons.add_photo_alternate),
                    label: const Text('Выбрать фото карты'),
                  ),
                ],
              ),
            )
          : _state.imageSize == null
              ? const Center(child: CircularProgressIndicator())
              : Stack(
                  children: [
                    InteractiveViewer(
                      minScale: 0.1,
                      maxScale: 8.0,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: Image.file(
                        File(_state.imagePath!),
                        fit: BoxFit.contain,
                      ),
                    ),
                    const MapCrosshair(),
                    
                    // Счётчик привязок
                    if (_state.project != null && _state.project!.anchors.isNotEmpty)
                      Positioned(
                        top: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Привязок: ${_state.project!.anchors.length}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                      
                    // Тулбар с кнопками
                    MapToolbar(
                      onHereNowPressed: () => _logic.addAnchorFromCurrentGps(),
                      onHereFromClipboard: () => _logic.addAnchorFromClipboard(),
                      // Временно неактивна, пока нет логики целей
                      onTargetPressed: null,
                      targetEnabled: false,
                      targetText: 'ЦЕЛЬ',
                    ),
                  ],
                ),
    );
  }
}