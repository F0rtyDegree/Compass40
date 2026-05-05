import 'package:flutter/material.dart';

class MapZoomButtons extends StatelessWidget {
  final VoidCallback onHereNowPressed;
  final VoidCallback onHereFromClipboard;
  final VoidCallback? onTargetPressed;
  final VoidCallback? onTargetLongPressed;
  final String targetText;
  final bool targetEnabled;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool rotateMode;
  final VoidCallback onToggleRotateMode;
  final VoidCallback onResetRotation;
  final bool visible;
  final bool hereEnabled;

  const MapZoomButtons({
    super.key,
    required this.onHereNowPressed,
    required this.onHereFromClipboard,
    this.onTargetPressed,
    this.onTargetLongPressed,
    this.targetText = 'ЦЕЛЬ',
    this.targetEnabled = false,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.rotateMode,
    required this.onToggleRotateMode,
    required this.onResetRotation,
    this.visible = true,
    this.hereEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      top: MediaQuery.of(context).size.height / 2 - 150,
      child: Column(
        children: [
          // Кнопка цели (условно, если привязка есть)
          _buildSquareButton(
            label: targetText,
            icon: Icons.flag,
            color: targetText == 'ГОУ' ? Colors.red : Colors.amber[700]!,
            onTap: onTargetPressed,
            onLongPress: onTargetLongPressed,
            enabled: targetEnabled,
          ),
          const SizedBox(height: 12),
          // Кнопка "Я ЗДЕСЬ"
          _buildSquareButton(
            label: 'Я ЗДЕСЬ',
            icon: Icons.my_location,
            color: Theme.of(context).colorScheme.primary,
            onTap: onHereNowPressed,
            onLongPress: onHereFromClipboard,
            enabled: hereEnabled,
          ),
          const SizedBox(height: 12),
          // Стандартные кнопки масштаба и поворота
          _buildButton(icon: Icons.add, onPressed: onZoomIn),
          const SizedBox(height: 12),
          _buildRotateButton(context),
          const SizedBox(height: 12),
          _buildButton(icon: Icons.remove, onPressed: onZoomOut),
        ],
      ),
    );
  }

  Widget _buildRotateButton(BuildContext context) {
    return GestureDetector(
      onTap: onToggleRotateMode,
      onLongPress: onResetRotation,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(rotateMode ? 180 : 60),
          shape: BoxShape.circle,
          border: rotateMode
              ? Border.all(color: Colors.orange, width: 2)
              : null,
        ),
        child: Icon(
          Icons.rotate_right,
          color: rotateMode ? Colors.orange : Colors.white.withAlpha(230),
          size: 28,
        ),
      ),
    );
  }

  // Новая квадратная кнопка для действий "Я ЗДЕСЬ" и "ЦЕЛЬ"
  Widget _buildSquareButton({
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
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withAlpha(220),
            borderRadius: BorderRadius.circular(12),
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
              Icon(icon, color: Colors.white, size: 24),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(60),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: Colors.white.withAlpha(230), size: 28),
        ),
      ),
    );
  }
}