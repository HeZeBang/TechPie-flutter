import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_demo_image.dart';
import 'genai_thinking_view.dart';
import 'genai_web_search_view.dart';

String genAiAgentToolName(String? name) => switch (name) {
      'web_search' => '联网搜索',
      'get_current_time' => '查看当前时间',
      'get_semesters' => '查看学期',
      'get_week_schedule' => '查看课表',
      'get_assignments' => '查看作业',
      'reserve_court' => '处理场地预约',
      'generate_image' => '生成图片',
      _ => name ?? '工具',
    };

/// Groups one turn's tool activity without hiding its approval controls.
class GenAiAgentToolActivity extends StatelessWidget {
  const GenAiAgentToolActivity({
    super.key,
    required this.events,
    required this.running,
    required this.stopped,
    this.activity = const [],
    this.thinking = false,
    this.legacyReasoning = '',
    this.legacyCitations = const [],
    this.onOpenLink,
    this.onOpenImages,
    this.demo = false,
    this.imageDisplayUri,
  });

  final List<GenAiAgentEvent> events;
  final bool running;
  final bool stopped;
  final List<GenAiAgentEvent> activity;
  final bool thinking;
  final String legacyReasoning;
  final List<GenAiWebSearchCitation> legacyCitations;
  final void Function(String)? onOpenLink;
  final VoidCallback? onOpenImages;
  final bool demo;
  final Uri Function(String)? imageDisplayUri;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final hasFailures = events.any(
      (event) => event.result?['ok'] == false || event.result?['error'] != null,
    );
    final status = running
        ? ' · 进行中'
        : stopped
            ? ' · 已停止'
            : hasFailures
                ? ' · 有未完成项'
                : '';
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: .4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        key: const ValueKey('agent-tool-activity-toggle'),
        // Preserve a user's collapse choice while streamed events change.
        // Saved turns start compact; live turns initially show their progress.
        initiallyExpanded: running,
        maintainState: true,
        dense: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        leading:
            Icon(Icons.auto_awesome_outlined, size: 16, color: colors.primary),
        title: Text(
          '处理过程 · ${events.length} 次工具调用$status',
          key: const ValueKey('agent-tool-activity-heading'),
          style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        children: [
          if (activity.isEmpty) ...[
            if (legacyReasoning.isNotEmpty || legacyCitations.isNotEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('历史记录未保存步骤顺序', style: TextStyle(fontSize: 11)),
              ),
            if (legacyReasoning.isNotEmpty)
              GenAiThinkingView(
                reasoning: legacyReasoning,
                onTapLink: onOpenLink,
              ),
            if (legacyCitations.isNotEmpty)
              GenAiWebSearchView(
                citations: legacyCitations,
                onOpenLink: onOpenLink ?? (_) {},
              ),
          ],
          for (final event in activity.isEmpty ? events : activity)
            Container(
              key: ValueKey(
                '${event.turn}-${event.call?.id ?? event.kind.name}',
              ),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.only(left: 10),
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: colors.outlineVariant)),
              ),
              child: _activityEntry(event),
            ),
        ],
      ),
    );
  }

  Widget _activityEntry(GenAiAgentEvent event) {
    if (event.kind == GenAiAgentEventKind.reasoningDelta) {
      return GenAiThinkingView(
        reasoning: event.text ?? '',
        autoExpandWhileThinking: false,
        isThinking: running && thinking && identical(event, activity.last),
        onTapLink: onOpenLink,
      );
    }
    if (event.kind == GenAiAgentEventKind.protocolError) {
      return Padding(
        padding: const EdgeInsets.all(8),
        child: Text(
          running && identical(event, activity.lastOrNull)
              ? '正在修正工具请求'
              : '工具请求格式不匹配，已请求重试',
          style: const TextStyle(fontSize: 12),
        ),
      );
    }
    final result = event.result?['result'];
    if (event.call?.name == 'web_search' &&
        event.result?['ok'] == true &&
        result is Map &&
        result['citations'] is List) {
      return GenAiWebSearchView(
        query: event.call!.arguments['query'] as String?,
        citations: [
          for (final raw in result['citations'] as List)
            if (raw is Map)
              GenAiWebSearchCitation.fromJson(Map<String, dynamic>.from(raw)),
        ],
        onOpenLink: onOpenLink ?? (_) {},
      );
    }
    return GenAiAgentToolCard(
      event: event,
      stopped: stopped,
      onOpenImages: onOpenImages,
      demo: demo,
      imageDisplayUri: imageDisplayUri,
    );
  }
}

/// Inline tool progress and results, sharing the main chat's scoped theme.
class GenAiAgentToolCard extends StatelessWidget {
  const GenAiAgentToolCard({
    super.key,
    required this.event,
    required this.stopped,
    this.onOpenImages,
    this.demo = false,
    this.imageDisplayUri,
  });

  final GenAiAgentEvent event;
  final bool stopped;
  final VoidCallback? onOpenImages;
  final bool demo;
  final Uri Function(String)? imageDisplayUri;

  @override
  Widget build(BuildContext context) {
    final call = event.call;
    if (call == null) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final result = event.result;
    final complete = event.kind == GenAiAgentEventKind.toolFinished;
    final failed = result?['ok'] == false || result?['error'] != null;
    final error = result?['error'];
    final unknown = error is Map && error['code'] == 'outcome_unknown' ||
        stopped && !complete && event.kind == GenAiAgentEventKind.toolStarted;
    final payload = result?['result'];
    final generated = complete &&
        !failed &&
        result?['ok'] == true &&
        call.name == 'generate_image' &&
        payload is Map &&
        payload['status'] == 'generated';
    final images = generated ? _verifiedImages(payload) : const <Uri>[];
    final status = unknown
        ? '结果待核实 · 请先查看记录'
        : complete
            ? failed
                ? '未完成 · 查看原因'
                : '已完成'
            : stopped
                ? '已停止 · 未执行'
                : event.kind == GenAiAgentEventKind.approvalRequired
                    ? '等待你的确认'
                    : '处理中';
    return Card(
      margin: const EdgeInsets.only(top: 8),
      elevation: 0,
      color: colors.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExpansionTile(
            key: ValueKey('agent-tool-${call.id}'),
            dense: true,
            leading: Icon(
              unknown || failed
                  ? Icons.info_outline
                  : complete
                      ? Icons.check_circle_outline
                      : Icons.more_horiz,
              size: 20,
            ),
            title: Text(genAiAgentToolName(call.name)),
            subtitle: Text(status),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              if (result?['reused'] == true)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('已复用之前的结果，没有重复执行。'),
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  const JsonEncoder.withIndent('  ')
                      .convert(result ?? call.arguments),
                  style: const TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
          if (generated)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: images.isEmpty
                  ? const Text('图片未能直接预览，可查看图片记录。')
                  : Column(
                      children: [
                        for (final uri in images)
                          _GenAiAgentImagePreview(
                            key: ValueKey('agent-image-${call.id}-$uri'),
                            uri: uri,
                            demo: demo &&
                                uri.pathSegments.any(
                                  (part) => part.startsWith('techpie-preview'),
                                ),
                          ),
                      ],
                    ),
            ),
          if ((complete || unknown) && call.name == 'generate_image')
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: onOpenImages,
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('查看图片'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Uri> _verifiedImages(Map<dynamic, dynamic> payload) {
    final values = payload['images'];
    if (values is! List) return const [];
    final images = <Uri>[];
    for (final value in values) {
      if (value is! String) continue;
      try {
        final raw = Uri.parse(value.trim());
        if (raw.userInfo.isNotEmpty ||
            raw.hasQuery ||
            raw.hasFragment ||
            raw.pathSegments.any((part) => part == '..' || part == '.')) {
          continue;
        }
        String canonicalInput = value;
        if (raw.hasAuthority && raw.host != 'genaipic.shanghaitech.edu.cn') {
          final resolve = imageDisplayUri;
          if (resolve == null) continue;
          final expected = resolve(
            'https://genaipic.shanghaitech.edu.cn/sys/common/static/techpie-agent-origin-check.png',
          );
          // API results can already have the app's local preview proxy origin.
          // Only that exact configured origin and static-image route are valid.
          if ((raw.scheme != 'https' && raw.scheme != 'http') ||
              raw.origin != expected.origin ||
              !raw.path.startsWith('/sys/common/static/')) {
            continue;
          }
          canonicalInput = Uri(
            scheme: 'https',
            host: 'genaipic.shanghaitech.edu.cn',
            path: raw.path,
          ).toString();
        }
        final canonical = genAiImageUri(canonicalInput);
        final display =
            imageDisplayUri?.call(canonical.toString()) ?? canonical;
        if (!images.contains(display)) images.add(display);
        if (images.length == 4) break;
      } catch (_) {
        // Invalid or unrecognized URLs never trigger remote image requests.
      }
    }
    return images;
  }
}

class _GenAiAgentImagePreview extends StatefulWidget {
  const _GenAiAgentImagePreview({
    super.key,
    required this.uri,
    required this.demo,
  });

  final Uri uri;
  final bool demo;

  @override
  State<_GenAiAgentImagePreview> createState() =>
      _GenAiAgentImagePreviewState();
}

class _GenAiAgentImagePreviewState extends State<_GenAiAgentImagePreview> {
  DialogRoute<void>? _viewer;

  Widget _image() => widget.demo
      ? const GenAiDemoImage()
      : Image.network(
          widget.uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('图片暂时无法预览，请查看图片记录。'),
            ),
          ),
        );

  void _open() {
    if (_viewer != null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: InteractiveViewer(maxScale: 4, child: _image()),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                tooltip: '关闭图片预览',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    );
    _viewer = route;
    unawaited(
      Navigator.of(context).push(route).whenComplete(() {
        if (identical(_viewer, route)) _viewer = null;
      }),
    );
  }

  @override
  void dispose() {
    final route = _viewer;
    _viewer = null;
    if (route != null) {
      // A session change removes the result card; close its viewer too. Defer
      // navigator mutation until the current widget teardown has finished.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (route.isActive) route.navigator?.removeRoute(route);
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Semantics(
          button: true,
          label: '放大生成的图片',
          child: Tooltip(
            message: '点击放大',
            child: InkWell(
              onTap: _open,
              borderRadius: BorderRadius.circular(10),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: SizedBox(
                    height: 240,
                    width: double.infinity,
                    child: _image(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Shows the adapter's immutable prepared action, never model-authored claims.
class GenAiAgentApprovalCard extends StatelessWidget {
  const GenAiAgentApprovalCard({
    super.key,
    required this.call,
    required this.prepared,
    this.onApprove,
    required this.onReject,
  });

  final GenAiAgentToolCall call;
  final GenAiAgentPreparedTool prepared;
  final VoidCallback? onApprove;
  final VoidCallback onReject;

  static String _detailLabel(String key) =>
      const {
        'prompt': '画面描述',
        'model': '模型',
        'size': '分辨率',
        'quality': '质量',
        'count': '数量',
        'quota': '额度',
        'date': '日期',
        'sport': '运动',
        'court': '场地',
        'time': '时间',
        'players': '人数',
        'price': '费用',
        'contact': '联系信息',
      }[key] ??
      key;

  static String _detailValue(MapEntry<String, Object?> entry) =>
      entry.key == 'quality'
          ? const {'low': '普通', 'medium': '标准', 'high': '精细'}[entry.value] ??
              '${entry.value}'
          : '${entry.value ?? '—'}';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      key: const ValueKey('agent-approval'),
      margin: const EdgeInsets.symmetric(vertical: 8),
      elevation: 0,
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              (prepared.summary ?? genAiAgentToolName(call.name))
                  .replaceAll(' · low', ' · 普通')
                  .replaceAll(' · medium', ' · 标准')
                  .replaceAll(' · high', ' · 精细'),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    for (final entry in prepared.details.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 72,
                              child: Text(
                                _detailLabel(entry.key),
                                style: TextStyle(
                                  color: colors.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: SelectableText(
                                _detailValue(entry),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const ValueKey('agent-reject'),
                    onPressed: onReject,
                    child: const Text('拒绝'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    key: const ValueKey('agent-approve'),
                    onPressed: onApprove,
                    child: const Text('确认执行'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
