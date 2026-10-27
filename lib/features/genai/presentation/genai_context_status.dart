import 'package:flutter/material.dart';

import '../domain/genai_context_usage.dart';

/// The last prepared request's budget, not a per-keystroke token counter.
class GenAiContextStatus extends StatelessWidget {
  const GenAiContextStatus({super.key, required this.usage});

  final GenAiContextUsage? usage;

  @override
  Widget build(BuildContext context) {
    final usage = this.usage;
    final busy = usage != null && usage.stage != GenAiContextStage.ready;
    final percent =
        usage == null ? null : (100 * usage.estimatedInputUnits / usage.allowedInputUnits).ceil();
    final label = switch (usage?.stage) {
      null => '上下文 · 此历史记录未保存估算',
      GenAiContextStage.preparing => '正在准备上下文',
      GenAiContextStage.compacting => usage!.totalChunks > 0
          ? '正在整理上下文 · ${usage.completedChunks}/${usage.totalChunks}'
          : '正在整理上下文',
      GenAiContextStage.ready => '${usage!.compacted ? '已整理上下文' : '上下文'} · 估算 $percent%',
    };
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('genai-context-status'),
      container: true,
      label: label,
      child: SizedBox.square(
        dimension: 48,
        child: Center(
          child: ExcludeSemantics(
            child: SizedBox.square(
              dimension: 20,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: busy
                          ? null
                          : usage == null
                              ? 0.0
                              : (usage.estimatedInputUnits / usage.allowedInputUnits)
                                  .clamp(0.0, 1.0),
                      strokeWidth: 3,
                      color: scheme.onSurfaceVariant,
                      backgroundColor: scheme.onSurfaceVariant.withValues(alpha: .15),
                    ),
                  ),
                  if (busy)
                    Icon(
                      usage.stage == GenAiContextStage.compacting
                          ? Icons.compress_rounded
                          : Icons.more_horiz_rounded,
                      size: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
