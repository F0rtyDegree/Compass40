import 'package:flutter/material.dart';

class MapZoomButtons extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final bool rotateMode;
  final VoidCallback onToggleRotateMode;
  final VoidCallback onResetRotation;
  final bool visible;

  const MapZoomButtons({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.rotateMode,
    required this.onToggleRotateMode,
    required this.onResetRotation,
    this.visible = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Positioned(
      right: 12,
      top: MediaQuery.of(context).size.height / 2 - 90,
      child: Column(
        children: [
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
