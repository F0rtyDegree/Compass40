import 'dart:io';
import 'package:flutter/material.dart';
import 'package:gps_info/gps_info.dart';
import 'package:image_picker/image_picker.dart';
import '../models/map_project.dart';
import '../services/map_storage_service.dart';
import 'map_screen_state.dart';

class MapScreenLogic {
  final MapScreenState state;
  final State hostState;
  final MapStorageService storageService;
  final GpsInfo gpsInfo;

  MapScreenLogic({
    required this.state,
    required this.hostState,
    required this.storageService,
    required this.gpsInfo,
  });

  bool get mounted => hostState.mounted;

  void setState(VoidCallback fn) {
    if (mounted) {
      // ignore: invalid_use_of_protected_member
      hostState.setState(fn);
    }
  }

  Future<void> init() async {
    await _loadLastProject();
  }

  void dispose() {}

  Future<void> _loadLastProject() async {
    final projectId = await storageService.getCurrentProjectId();
    if (projectId != null) {
      final project = await storageService.loadProject(projectId);
      if (project != null && mounted) {
        setState(() {
          state.project = project;
          state.imagePath = project.imagePath;
        });
        _loadImageSize();
      }
    }
  }

  Future<void> _loadImageSize() async {
    if (state.imagePath == null) return;
    final file = File(state.imagePath!);
    if (!await file.exists()) return;
    
    final decoded = await decodeImageFromList(await file.readAsBytes());
    if (mounted) {
      setState(() {
        state.imageSize = Size(decoded.width.toDouble(), decoded.height.toDouble());
      });
    }
  }

  Future<void> pickImage() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      
      if (image != null && mounted) {
        final savedPath = await storageService.saveImageToAppStorage(image.path);
        final projectId = DateTime.now().millisecondsSinceEpoch.toString();
        final project = MapProject(
          id: projectId,
          imagePath: savedPath,
          anchors: [],
          targets: [],
        );
        await storageService.saveProject(project);
        await storageService.setCurrentProjectId(projectId);
        setState(() {
          state.project = project;
          state.imagePath = savedPath;
          state.imageSize = null;
        });
        _loadImageSize();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
    }
  }

  Future<void> closeMap() async {
    await storageService.setCurrentProjectId(null);
    if (mounted) {
      setState(() {
        state.project = null;
        state.imagePath = null;
        state.imageSize = null;
      });
    }
  }

  Future<void> addAnchorFromCurrentGps() async {
    // Заглушка
    _showSnackBar('Добавление привязки по GPS (в разработке)');
  }

  Future<void> addAnchorFromClipboard() async {
    // Заглушка
    _showSnackBar('Добавление привязки из буфера (в разработке)');
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(hostState.context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}