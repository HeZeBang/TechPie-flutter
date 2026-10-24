import 'dart:async';

import 'package:flutter/material.dart';

class GenAiRecordingBar extends StatelessWidget {
  const GenAiRecordingBar({
    super.key,
    required this.seconds,
    required this.onCancel,
    required this.onComplete,
  });

  final int seconds;
  final VoidCallback onCancel;
  final VoidCallback onComplete;

  @override
  Widget build(BuildContext context) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在录音 $m:$s',
            key: const ValueKey('genai-recording-duration'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: _AudioWaveformVisualizer(),
          ),
          TextButton(
            key: const ValueKey('genai-cancel-recording'),
            onPressed: onCancel,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            key: const ValueKey('genai-finish-recording'),
            onPressed: onComplete,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14),
                SizedBox(width: 4),
                Text('完成', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioWaveformVisualizer extends StatefulWidget {
  const _AudioWaveformVisualizer();

  @override
  State<_AudioWaveformVisualizer> createState() =>
      _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<_AudioWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_controller.repeat(reverse: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        const heights = [0.4, 0.8, 1.0, 0.6, 0.9, 0.5, 0.7];
        return SizedBox(
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(heights.length, (i) {
              final wave = ((heights[i] + (i.isEven ? t : 1 - t) * 0.5) % 1.0)
                  .clamp(0.2, 1.0);
              return Container(
                width: 2.5,
                height: 16 * wave,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
