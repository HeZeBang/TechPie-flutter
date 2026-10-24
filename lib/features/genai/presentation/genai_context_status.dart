import 'package:flutter/material.dart';

import '../../../widgets/adaptive_alert_dialog.dart';
import '../domain/genai_context_usage.dart';

/// The last prepared request's budget, not a per-keystroke token counter.
class GenAiContextStatus extends StatelessWidget {
  const GenAiContextStatus({super.key, required this.usage});

  final GenAiContextUsage usage;

  @override
  Widget build(BuildContext context) {
    final busy = usage.stage != GenAiContextStage.ready;
    final percent = (100 * usage.estimatedInputUnits / usage.allowedInputUnits).ceil();
    final label = switch (usage.stage) {
      GenAiContextStage.preparing => '正在准备上下文',
      GenAiContextStage.compacting => usage.totalChunks > 0
          ? '正在整理上下文 · ${usage.completedChunks}/${usage.totalChunks}'
          : '正在整理上下文',
      GenAiContextStage.ready => '${usage.compacted ? '已整理上下文' : '上下文'} · 估算 $percent%',
    };
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      key: const ValueKey('genai-context-status'),
      tooltip: label,
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      onPressed: () async {
        await _showDetails(context, percent);
      },
      icon: ExcludeSemantics(
        child: SizedBox.square(
          dimension: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox.expand(
                child: CircularProgressIndicator(
                  value: busy
                      ? null
                      : (usage.estimatedInputUnits / usage.allowedInputUnits).clamp(0.0, 1.0),
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
    );
  }

  Future<void> _showDetails(BuildContext context, int percent) async {
    final phase = usage.stage == GenAiContextStage.ready
        ? '本轮最近一次请求约占可用输入预算的 $percent%。'
        : '正在准备本轮请求，必要时会整理较早的历史记录。';
    final before = (100 * usage.originalInputUnits / usage.allowedInputUnits).ceil();
    await showAdaptiveAlertDialog<void>(
      context: context,
      title: '上下文预算',
      message: '$phase'
          '${usage.compacted ? '\n整理前约为 $before%，整理后约为 $percent%。' : ''}'
          '\n\n估算包含历史消息、工具结果和附件，并预留回复空间。'
          '这里显示的是保守的本地估算，不是实际 Token 用量或计费额度；编辑草稿不会更新它。'
          '\n\n整理会优先保留用户原始记录和工具结果。原始对话仍可在历史中查看。',
      actions: const [AdaptiveAlertAction<void>(label: '知道了', isDefault: true)],
    );
  }
}
