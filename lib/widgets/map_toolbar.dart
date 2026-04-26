import 'package:flutter/material.dart';

class MapToolbar extends StatelessWidget {
  final VoidCallback onHereNowPressed;
  final VoidCallback onHereFromClipboard;
  final VoidCallback? onTargetPressed;
  final bool targetEnabled;
  final String targetText;
  final bool followModeEnabled;

  const MapToolbar({
    super.key,
    required this.onHereNowPressed,
    required this.onHereFromClipboard,
    this.onTargetPressed,
    this.targetEnabled = false,
    this.targetText = 'ЦЕЛЬ',
    required this.followModeEnabled,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 24,
      left: 0,
      right: 0,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildButton(
            context: context,
            label: 'Я ЗДЕСЬ',
            icon: Icons.my_location,
            color: Theme.of(context).colorScheme.primary,
            onTap: onHereNowPressed,
            onLongPress: onHereFromClipboard,
            enabled: !followModeEnabled,
          ),
          const SizedBox(width: 20),
          _buildButton(
            context: context,
            label: targetText,
            icon: Icons.flag,
            color: targetEnabled
                ? (targetText == 'ГОУ' ? Colors.red : Colors.amber[700]!)
                : Colors.grey,
            onTap: targetEnabled ? onTargetPressed : null,
            enabled: targetEnabled,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPress: enabled ? onLongPress : null,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: color.withAlpha(220),
            borderRadius: BorderRadius.circular(20),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: Colors.black.withAlpha(60),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 28),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
