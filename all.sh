#!/bin/bash

# Configuration
echo "=== pubspec.yaml ===" && cat -n pubspec.yaml
echo ""
echo "=== analysis_options.yaml ===" && cat -n analysis_options.yaml
echo ""

# Main App Files
echo "=== lib/main.dart ===" && cat -n lib/main.dart
echo ""
echo "=== lib/app/my_app.dart ===" && cat -n lib/app/my_app.dart
echo ""

#
echo "=== lib/controllers/home_navigation_actions.dart ===" && cat -n lib/controllers/home_navigation_actions.dart
echo ""
echo "=== lib/controllers/home_logic.dart ===" && cat -n lib/controllers/home_logic.dart
echo ""
echo "=== lib/controllers/home_state.dart ===" && cat -n lib/controllers/home_state.dart
echo ""
echo "=== lib/services/log_service.dart ===" && cat -n lib/services/log_service.dart
echo ""
echo "=== lib/services/sensor_service.dart ===" && cat -n lib/services/sensor_service.dart
echo ""

# Screens
echo "=== lib/screens/home_screen.dart ===" && cat -n lib/screens/home_screen.dart
echo ""
echo "=== lib/about_screen.dart ===" && cat -n lib/about_screen.dart
echo ""
echo "=== lib/log_screen.dart ===" && cat -n lib/log_screen.dart
echo ""
echo "=== lib/settings_screen.dart ===" && cat -n lib/settings_screen.dart
echo ""
echo "=== lib/target_screen.dart ===" && cat -n lib/target_screen.dart
echo ""

# Widgets
echo "=== lib/widgets/compass_section.dart ===" && cat -n lib/widgets/compass_section.dart
echo ""
echo "=== lib/widgets/gps_section.dart ===" && cat -n lib/widgets/gps_section.dart
echo ""
echo "=== lib/widgets/compass_painters.dart ===" && cat -n lib/widgets/compass_painters.dart
echo ""
echo "=== lib/widgets/exit_confirm_dialog.dart ===" && cat -n lib/widgets/exit_confirm_dialog.dart
echo ""


# Utils
echo "=== lib/utils/geo_utils.dart ===" && cat -n lib/utils/geo_utils.dart
echo ""

# Models and Providers
echo "=== lib/log_entry.dart ===" && cat -n lib/log_entry.dart
echo ""
echo "=== lib/theme_provider.dart ===" && cat -n lib/theme_provider.dart
echo ""

# Packages - gps_info
echo "=== packages/gps_info/lib/gps_info.dart ===" && cat -n packages/gps_info/lib/gps_info.dart
echo ""
echo "=== packages/gps_info/lib/gps_data.dart ===" && cat -n packages/gps_info/lib/gps_data.dart
echo ""
echo "=== packages/gps_info/android/src/main/kotlin/com/example/gps_info/GpsInfoPlugin.kt ===" && cat -n packages/gps_info/android/src/main/kotlin/com/example/gps_info/GpsInfoPlugin.kt
echo ""

# Packages - my_compass
echo "=== packages/my_compass/lib/my_compass.dart ===" && cat -n packages/my_compass/lib/my_compass.dart
echo ""
echo "=== packages/my_compass/android/src/main/kotlin/com/example/my_compass/MyCompassPlugin.kt ===" && cat -n packages/my_compass/android/src/main/kotlin/com/example/my_compass/MyCompassPlugin.kt
echo ""

# Android Manifest
echo "=== android/app/src/main/AndroidManifest.xml ===" && cat -n android/app/src/main/AndroidManifest.xml
echo ""
