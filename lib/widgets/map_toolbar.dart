import 'package:flutter/material.dart';

class MapToolbar extends StatelessWidget {
  final VoidCallback onHereNowPressed;
  final VoidCallback onHereFromClipboard;
  final VoidCallback? onTargetPressed;
  final bool targetEnabled;
  final String targetText;

  const MapToolbar({
    super.key,
    required this.onHereNowPressed,
    required this.onHereFromClipboard,
    this.onTargetPressed,
    this.targetEnabled = false,
    this.targetText = 'ЦЕЛЬ',
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // 5 кнопок в строку: (ширина экрана - отступы) / 5
    // Отступы: 16 слева + 16 между кнопками + 16 справа = 48, плюс запас
    final buttonSize = (screenWidth - 64) / 5;
    
    // Защита от слишком мелкого и слишком крупного шрифта
    final iconSize = (buttonSize * 0.35).clamp(20.0, 32.0);
    final fontSize = (buttonSize * 0.12).clamp(10.0, 16.0);
    
    return Positioned(
      bottom: 20,
      left: 16,
      right: 16,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Кнопка "Я ЗДЕСЬ"
          GestureDetector(
            onLongPress: onHereFromClipboard,
            onTap: onHereNowPressed,
            child: Container(
              width: buttonSize,
              height: buttonSize,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.my_location,
                    color: Theme.of(context).colorScheme.onPrimary,
                    size: iconSize,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Я ЗДЕСЬ',
                    style: TextStyle(
                      fontSize: fontSize,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(width: 16),
          
          // Кнопка "ЦЕЛЬ" / "ГОУ"
          Opacity(
            opacity: targetEnabled ? 1.0 : 0.5,
            child: GestureDetector(
              onTap: targetEnabled ? onTargetPressed : null,
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: targetEnabled 
                      ? Colors.amber.withValues(alpha: 0.8)
                      : Colors.grey.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: targetEnabled ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.flag,
                      color: targetEnabled ? Colors.black87 : Colors.black54,
                      size: iconSize,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      targetText,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        color: targetEnabled ? Colors.black87 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}