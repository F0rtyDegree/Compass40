import 'package:flutter/material.dart';

class MapActionButtons extends StatelessWidget {
  final VoidCallback onHereNowPressed;
  final VoidCallback onHereFromClipboard;
  final VoidCallback? onTargetPressed;
  final VoidCallback? onTargetLongPressed;
  final String targetText;
  final bool targetEnabled;
  final bool hereEnabled;

  const MapActionButtons({
    super.key,
    required this.onHereNowPressed,
    required this.onHereFromClipboard,
    this.onTargetPressed,
    this.onTargetLongPressed,
    this.targetText = 'ЦЕЛЬ',
    this.targetEnabled = false,
    this.hereEnabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSquareButton(
          label: targetText,
          icon: Icons.flag,
          color: targetText == 'ГОУ' ? Colors.red : Colors.amber[700]!,
          onTap: onTargetPressed,
          onLongPress: onTargetLongPressed,
          enabled: targetEnabled,
        ),
        const SizedBox(height: 12),
        _buildSquareButton(
          label: 'Я ЗДЕСЬ',
          icon: Icons.my_location,
          color: Theme.of(context).colorScheme.primary,
          onTap: onHereNowPressed,
          onLongPress: onHereFromClipboard,
          enabled: hereEnabled,
          longPressEnabled: true,
        ),
      ],
    );
  }

  Widget _buildSquareButton({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
    bool enabled = true,
    // Короткий тап подчиняется enabled, длинный — longPressEnabled.
    // Для кнопки Я ЗДЕСЬ это значит: в follow mode короткий тап заблокирован
    // (якорь ложится в прицел, а прицел смещён), длинный доступен всегда,
    // потому что меню Я ЗДЕСЬ (буфер, GPX, ФотоСевер, КП) от прицела не зависит.
    // При рефакторинге не связывать longPressEnabled с enabled без причины.
    bool longPressEnabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        onLongPress: longPressEnabled ? onLongPress : null,
        child: Container(
          width: 75,
          height: 75,
          decoration: BoxDecoration(
            color: color.withAlpha(80),
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
              Icon(icon, color: Colors.white, size: 30),
              const SizedBox(height: 2),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
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