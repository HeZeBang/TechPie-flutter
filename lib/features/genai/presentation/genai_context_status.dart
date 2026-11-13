import 'package:flutter/material.dart';

import '../domain/genai_context_usage.dart';
import 'genai_icons.dart';

/// The last prepared request's budget, not a per-keystroke token counter.
class GenAiContextStatus extends StatelessWidget {
  const GenAiContextStatus({super.key, required this.usage, this.showLabel = false});

  final GenAiContextUsage? usage;
  final bool showLabel;

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
    if (showLabel) {
      return Text(
        label,
        key: const ValueKey('genai-context-status'),
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: const ValueKey('genai-context-status'),
      container: true,
      label: label,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // The composer gives the phone slot a 24px cell; the desktop slot is
          // wider. Derive the draft's 13px phone / 16px desktop ring from the
          // cell it is actually placed in rather than the window size.
          final compact = constraints.hasBoundedWidth && constraints.maxWidth < 30;
          return SizedBox(
            width: compact ? 24 : 28,
            height: compact ? 42 : 48,
            child: Center(
              child: ExcludeSemantics(
                child: SizedBox.square(
                  dimension: compact ? 13 : 16,
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
                        GenAiIcon(
                          usage.stage == GenAiContextStage.compacting
                              ? GenAiGlyph.fullExit
                              : GenAiGlyph.more,
                          size: compact ? 8 : 10,
                          color: scheme.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
