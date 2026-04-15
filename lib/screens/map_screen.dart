import 'dart:io';
import 'package:flutter/material.dart';
import '../services/map_storage_service.dart';
import '../controllers/map_screen_state.dart';
import '../models/map_project.dart';
import 'package:image_picker/image_picker.dart';
import '../widgets/map_crosshair.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final MapStorageService _storageService = MapStorageService();
  final MapScreenState _state = MapScreenState();
  
  @override
  void initState() {
    super.initState();
    _loadLastProject();
  }
  
  Future<void> _loadLastProject() async {
    final projectId = await _storageService.getCurrentProjectId();
    if (projectId != null) {
      final project = await _storageService.loadProject(projectId);
      if (project != null && mounted) {
        setState(() {
          _state.project = project;
          _state.imagePath = project.imagePath;
        });
        _loadImageSize();
      }
    }
  }
  
  Future<void> _pickImage() async {
  try {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);
    
    if (image != null && mounted) {
      final savedPath = await _storageService.saveImageToAppStorage(image.path);
      final projectId = DateTime.now().millisecondsSinceEpoch.toString();
      final project = MapProject(
        id: projectId,
        imagePath: savedPath,
        anchors: [],
        targets: [],
      );
      await _storageService.saveProject(project);
      await _storageService.setCurrentProjectId(projectId);
      setState(() {
        _state.project = project;
        _state.imagePath = savedPath;
      });
      _loadImageSize();
    }
  } catch (e) {
    debugPrint('Error picking image: $e');
  }
}
  
  Future<void> _loadImageSize() async {
    if (_state.imagePath == null) return;
    final file = File(_state.imagePath!);
    if (!await file.exists()) return;
    
    final decoded = await decodeImageFromList(await file.readAsBytes());
    if (mounted) {
      setState(() {
        _state.imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Спорткарта'),
        centerTitle: true,
        actions: [
          if (_state.imagePath == null)
            IconButton(
              icon: const Icon(Icons.add_photo_alternate),
              onPressed: _pickImage,
              tooltip: 'Выбрать карту',
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
              onPressed: _pickImage,
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
              LayoutBuilder(
              builder: (context, constraints) {
                return InteractiveViewer(
                  minScale: 0.1,
                  maxScale: 4.0,
                  constrained: false,
                  // ignore: sized_box_for_whitespace
                  child: Container(
                    width: constraints.maxWidth * 2.2,
                    height: constraints.maxHeight * 2.2,
                    child: Image.file(
                      File(_state.imagePath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                );
              },
            ),
              const MapCrosshair(),
            ],
          ),
    );
  }
}