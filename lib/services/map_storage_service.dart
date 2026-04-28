import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/map_project.dart';
import '../models/map_transform_state.dart';

class MapStorageService {
  static const String _projectsKey = 'map_projects';
  static const String _currentProjectIdKey = 'current_map_project_id';
  static const String _transformPrefix = 'map_transform_';

  Future<Directory> _getMapsDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final mapsDir = Directory('${appDir.path}/compass40_maps');
    if (!await mapsDir.exists()) {
      await mapsDir.create(recursive: true);
    }
    return mapsDir;
  }

  Future<String> saveImageToAppStorage(String sourcePath) async {
    final mapsDir = await _getMapsDirectory();
    final fileName = DateTime.now().millisecondsSinceEpoch.toString();
    final ext = sourcePath.split('.').last;
    final destPath = '${mapsDir.path}/$fileName.$ext';
    await File(sourcePath).copy(destPath);
    return destPath;
  }

  Future<void> saveProject(MapProject project) async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getString(_projectsKey) ?? '{}';
    final Map<String, dynamic> projects = jsonDecode(projectsJson);

    // Используем toJson для сериализации
    projects[project.id] = project.toJson();

    await prefs.setString(_projectsKey, jsonEncode(projects));
  }

  Future<MapProject?> loadProject(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final projectsJson = prefs.getString(_projectsKey);
    if (projectsJson == null) return null;

    final Map<String, dynamic> projects = jsonDecode(projectsJson);
    final projectData = projects[id];
    if (projectData == null) return null;

    // Используем fromJson для десериализации
    return MapProject.fromJson(projectData as Map<String, dynamic>);
  }


  /// Сохранить transform для проекта
  Future<void> saveTransform(String projectId, MapTransformState t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_transformPrefix$projectId',
      jsonEncode({
        'scale': t.scale,
        'rotation': t.rotationRadians,
        'tx': t.translation.dx,
        'ty': t.translation.dy,
      }),
    );
  }

  /// Загрузить сохранённый transform для проекта
  Future<MapTransformState?> loadTransform(String projectId) async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString('$_transformPrefix$projectId');
    if (json == null) return null;

    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return MapTransformState(
        scale: (m['scale'] as num).toDouble(),
        rotationRadians: (m['rotation'] as num).toDouble(),
        translation: Offset(
          (m['tx'] as num).toDouble(),
          (m['ty'] as num).toDouble(),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> setCurrentProjectId(String? id) async {
    final prefs = await SharedPreferences.getInstance();
    if (id == null) {
      await prefs.remove(_currentProjectIdKey);
    } else {
      await prefs.setString(_currentProjectIdKey, id);
    }
  }

  Future<String?> getCurrentProjectId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_currentProjectIdKey);
  }
}
