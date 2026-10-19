import 'package:flutter/material.dart';

class RecordButton extends StatefulWidget {
  final ValueNotifier<bool> isRecordingNotifier;
  final ValueNotifier<int> tickNotifier;
  final ValueNotifier<String> tooltipNotifier;
  final VoidCallback onPressed;

  const RecordButton({
    super.key,
    required this.isRecordingNotifier,
    required this.tickNotifier,
    required this.tooltipNotifier,
    required this.onPressed,
  });

  @override
  State<RecordButton> createState() => _RecordButtonState();
}

class _RecordButtonState extends State<RecordButton> {
  double _scale = 1.0;

  @override
  void initState() {
    super.initState();
    widget.tickNotifier.addListener(_onTick);
  }

  @override
  void dispose() {
    widget.tickNotifier.removeListener(_onTick);
    super.dispose();
  }

  void _onTick() {
    if (!widget.isRecordingNotifier.value) return;
    setState(() => _scale = 1.4);
    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) setState(() => _scale = 1.0);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String>(
      valueListenable: widget.tooltipNotifier,
      builder: (context, tooltipText, _) {
        return ValueListenableBuilder<bool>(
          valueListenable: widget.isRecordingNotifier,
          builder: (context, isRecording, _) {
            return Tooltip(
              message: tooltipText,
              showDuration: const Duration(seconds: 5),
              child: IconButton(
                icon: AnimatedScale(
                  scale: isRecording ? _scale : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    isRecording ? Icons.stop : Icons.play_arrow,
                    color: isRecording ? Colors.red : Colors.grey,
                  ),
                ),
                onPressed: widget.onPressed,
              ),
            );
          },
        );
      },
    );
  }
}