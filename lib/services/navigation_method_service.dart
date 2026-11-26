import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_constants.dart';
import 'brouter_service.dart';

class NavigationMethod {
  /// 'azimuth' | 'foot' | 'trekking' | 'car-fast' | 'custom:/path/to/file.brf'
  final String id;
  final String title;
  final bool isAzimuth;
  final bool isCustom;
  final String? profileName;
  final String? customFilePath;

  const NavigationMethod({
    required this.id,
    required this.title,
    this.isAzimuth = false,
    this.isCustom = false,
    this.profileName,
    this.customFilePath,
  });

  static const NavigationMethod azimuth = NavigationMethod(
    id: AppConstants.navMethodAzimuth,
    title: 'По азимуту',
    isAzimuth: true,
  );

  static const List<NavigationMethod> builtInMethods = [
    azimuth,
    NavigationMethod(
      id: 'foot',
      title: 'Пешком (foot)',
      profileName: 'foot',
    ),
    NavigationMethod(
      id: 'trekking',
      title: 'Велосипед (trekking)',
      profileName: 'trekking',
    ),
    NavigationMethod(
      id: 'car-fast',
      title: 'Автомобиль (car-fast)',
      profileName: 'car-fast',
    ),
  ];

  factory NavigationMethod.fromCustomPath(String filePath) {
    final fileName = filePath.split('/').last;
    final dotIndex = fileName.lastIndexOf('.');
    final nameWithoutExt =
        dotIndex > 0 ? fileName.substring(0, dotIndex) : fileName;
    return NavigationMethod(
      id: 'custom:$filePath',
      title: nameWithoutExt,
      isCustom: true,
      customFilePath: filePath,
    );
  }
}

class PersistedTargetData {
  final double latitude;
  final double longitude;
  final String methodId;

  const PersistedTargetData({
    required this.latitude,
    required this.longitude,
    required this.methodId,
  });

  Map<String, dynamic> toJson() => {
        'latitude': latitude,
        'longitude': longitude,
        'methodId': methodId,
      };

  factory PersistedTargetData.fromJson(Map<String, dynamic> json) {
    return PersistedTargetData(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      methodId:
          json['methodId'] as String? ?? AppConstants.navMethodDefault,
    );
  }
}

class NavigationMethodService {
  static Future<List<String>> loadCustomProfilePaths() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(AppConstants.prefCustomBrfProfiles) ?? [];
  }

  static Future<List<NavigationMethod>> getAllMethods() async {
    final customPaths = await loadCustomProfilePaths();
    final customMethods =
        customPaths.map((p) => NavigationMethod.fromCustomPath(p)).toList();
    return [...NavigationMethod.builtInMethods, ...customMethods];
  }

  static Future<List<NavigationMethod>> getAvailableMethods({
    bool? isBrouterInstalled,
  }) async {
    final installed = isBrouterInstalled ?? await BRouterService.isInstalled();
    if (!installed) {
      return [NavigationMethod.azimuth];
    }
    return getAllMethods();
  }

  static Future<NavigationMethod> addCustomProfile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = List<String>.from(
      prefs.getStringList(AppConstants.prefCustomBrfProfiles) ?? [],
    );
    if (!paths.contains(filePath)) {
      paths.add(filePath);
      await prefs.setStringList(AppConstants.prefCustomBrfProfiles, paths);
    }
    return NavigationMethod.fromCustomPath(filePath);
  }

  static Future<void> removeCustomProfile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    final paths = List<String>.from(
      prefs.getStringList(AppConstants.prefCustomBrfProfiles) ?? [],
    );
    paths.remove(filePath);
    await prefs.setStringList(AppConstants.prefCustomBrfProfiles, paths);

    final defaultId = prefs.getString(AppConstants.prefDefaultNavigationMethod);
    if (defaultId == 'custom:$filePath') {
      await prefs.setString(
        AppConstants.prefDefaultNavigationMethod,
        AppConstants.navMethodAzimuth,
      );
    }
  }

  static Future<String> getDefaultMethodId({bool? isBrouterInstalled}) async {
    final installed = isBrouterInstalled ?? await BRouterService.isInstalled();
    if (!installed) return AppConstants.navMethodAzimuth;

    final prefs = await SharedPreferences.getInstance();
    final savedId =
        prefs.getString(AppConstants.prefDefaultNavigationMethod) ??
            AppConstants.navMethodDefault;
    final all = await getAllMethods();
    if (all.any((m) => m.id == savedId)) {
      return savedId;
    }
    return AppConstants.navMethodAzimuth;
  }

  static Future<void> setDefaultMethodId(String methodId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.prefDefaultNavigationMethod, methodId);
  }

  static Future<NavigationMethod> resolveMethodById(
    String methodId, {
    bool? isBrouterInstalled,
  }) async {
    final installed = isBrouterInstalled ?? await BRouterService.isInstalled();
    if (!installed) return NavigationMethod.azimuth;

    final all = await getAllMethods();
    for (final m in all) {
      if (m.id == methodId) return m;
    }
    return NavigationMethod.azimuth;
  }

  // --- Хранение единственной активной цели ---

  static Future<void> saveActiveTarget(PersistedTargetData target) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      AppConstants.prefPersistedActiveTarget,
      jsonEncode(target.toJson()),
    );
  }

  static Future<PersistedTargetData?> loadActiveTarget() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(AppConstants.prefPersistedActiveTarget);
    if (raw == null || raw.isEmpty) return null;
    try {
      return PersistedTargetData.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearActiveTarget() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.prefPersistedActiveTarget);
  }
}
