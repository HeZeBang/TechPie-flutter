import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../domain/genai_agent_contract.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_activity_line.dart';
import 'genai_icons.dart';
import 'genai_image.dart';
import 'genai_image_actions.dart';
import 'genai_theme.dart';
import 'genai_thinking_view.dart';
import 'genai_tool_result_summary.dart';
import 'genai_web_search_view.dart';
import 'markdown/genai_code_font.dart';

String genAiAgentToolName(String? name) => switch (name) {
      'web_search' => '联网搜索',
      'get_current_time' => '查看当前时间',
      'search_conversation' => '查找对话记录',
      'read_conversation_records' => '读取对话记录',
      'get_semesters' => '查看学期',
      'get_week_schedule' => '查看课表',
      'get_assignments' => '查看作业',
      'reserve_court' => '处理场地预约',
      'generate_image' => '生成图片',
      'inspect_image' => '查看图片',
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
  final Uri Function(String)? imageDisplayUri;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
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
    final color = running
        ? colors.primary
        : hasFailures || stopped
            ? colors.onSurfaceVariant
            : GenAiPalette.of(context).success;
    // Preserve a user's collapse choice while streamed events change.
    // Saved turns start compact; live turns initially show their progress.
    return Padding(
      // Reference .activity: 16px below the line, of which the turn already
      // contributes 6px around the whole activity block.
      padding: const EdgeInsets.only(bottom: 10),
      child: GenAiDisclosure(
        key: const ValueKey('agent-tool-activity-toggle'),
        initiallyExpanded: running,
        titleKey: const ValueKey('agent-tool-activity-heading'),
        title: _title(status),
        color: running ? colors.primary : colors.onSurfaceVariant,
        // Every entry becomes a dot on the rail, like the reference activity body.
        steps: true,
        // The live answer row below already animates; the heading stays still.
        leading: GenAiIcon(
          running
              ? GenAiGlyph.tools
              : hasFailures || stopped
                  ? GenAiGlyph.info
                  : GenAiGlyph.checkCircle,
          color: color,
        ),
        children: [
          if (activity.isEmpty) ...[
            if (legacyReasoning.isNotEmpty || legacyCitations.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  '历史记录未保存步骤顺序',
                  style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant),
                ),
              ),
            if (legacyReasoning.isNotEmpty)
              GenAiThinkingView(reasoning: legacyReasoning, onTapLink: onOpenLink),
            if (legacyCitations.isNotEmpty)
              GenAiWebSearchView(citations: legacyCitations, onOpenLink: onOpenLink ?? (_) {}),
          ],
          for (final event in activity.isEmpty ? events : activity)
            KeyedSubtree(
              key: ValueKey('${event.turn}-${event.call?.id ?? event.kind.name}'),
              child: _activityEntry(context, event),
            ),
        ],
      ),
    );
  }

  /// Distinct tool display names joined by 与, then the step count, as in
  /// the reference "已查看课表与作业 · 3 个步骤" line.
  String _title(String status) {
    final names = <String>[];
    for (final event in events) {
      final name = event.call?.name;
      if (name == null) continue;
      final display = genAiAgentToolName(name);
      if (!names.contains(display)) names.add(display);
    }
    final label = names.isEmpty ? '处理过程' : names.join('与');
    final steps = events.isEmpty ? '' : ' · ${events.length} 个步骤';
    return '$label$steps$status';
  }

  Widget _activityEntry(BuildContext context, GenAiAgentEvent event) {
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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Text(
          running && identical(event, activity.lastOrNull) ? '正在重试请求' : '请求格式有误',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }
    // A decided booking approval is shown as a quiet notice. The decision is
    // read from the recorded outcome, not from extra controller state.
    final outcome = _bookingOutcome(event);
    if (outcome != null) return outcome;
    final result = event.result?['result'];
    if (event.call?.name == 'web_search' &&
        event.result?['ok'] == true &&
        result is Map &&
        result['citations'] is List) {
      return GenAiWebSearchView(
        query: event.call!.arguments['query'] as String?,
        citations: [
          for (final raw in result['citations'] as List)
            if (raw is Map) GenAiWebSearchCitation.fromJson(Map<String, dynamic>.from(raw)),
        ],
        onOpenLink: onOpenLink ?? (_) {},
      );
    }
    return GenAiAgentToolCard(
      event: event,
      stopped: stopped,
      onOpenImages: onOpenImages,
      imageDisplayUri: imageDisplayUri,
    );
  }

  /// Confirmed and cancelled bookings share one notice, derived entirely from
  /// the tool result the runner recorded for this call.
  Widget? _bookingOutcome(GenAiAgentEvent event) {
    if (event.call?.name != 'reserve_court' || event.kind != GenAiAgentEventKind.toolFinished) {
      return null;
    }
    final result = event.result;
    if (result == null) return null;
    final error = result['error'];
    if (error is Map && error['code'] == 'approval_denied') {
      return _GenAiAgentApprovalNotice(
        key: ValueKey('agent-approval-cancelled-${event.call!.id}'),
        confirmed: false,
      );
    }
    final payload = result['result'];
    if (result['ok'] == true && payload is Map && payload['status'] == 'booked') {
      return _GenAiAgentApprovalNotice(
        key: ValueKey('agent-approval-confirmed-${event.call!.id}'),
        confirmed: true,
        summary: genAiToolResultSummary('reserve_court', result),
      );
    }
    return null;
  }
}

/// The decided state of an approval, matching the reference `.notice` row.
class _GenAiAgentApprovalNotice extends StatelessWidget {
  const _GenAiAgentApprovalNotice({
    super.key,
    required this.confirmed,
    this.summary = '',
  });

  final bool confirmed;
  final String summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GenAiPalette.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 680;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        children: [
          GenAiIcon(
            confirmed ? GenAiGlyph.check : GenAiGlyph.close,
            size: 20,
            color: palette.accent,
          ),
          SizedBox(width: narrow ? 10 : 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  confirmed ? '预约完成' : '已取消预约',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: palette.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  confirmed ? (summary.isEmpty ? '预约已提交。' : summary) : '没有提交任何预约。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.muted,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
    this.imageDisplayUri,
  });

  final GenAiAgentEvent event;
  final bool stopped;
  final VoidCallback? onOpenImages;
  final Uri Function(String)? imageDisplayUri;

  @override
  Widget build(BuildContext context) {
    final call = event.call;
    if (call == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final palette = GenAiPalette.of(context);
    final result = event.result;
    final complete = event.kind == GenAiAgentEventKind.toolFinished;
    final failed = result?['ok'] == false || result?['error'] != null;
    final error = result?['error'];
    final unknown = error is Map && error['code'] == 'outcome_unknown' ||
        stopped && !complete && event.kind == GenAiAgentEventKind.toolStarted;
    final payload = result?['result'];
    final summary = genAiToolResultSummary(call.name, result);
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
    final color = unknown || failed
        ? colors.error
        : complete || stopped
            ? colors.onSurfaceVariant
            : colors.primary;
    final body = theme.textTheme.bodySmall?.copyWith(
      color: palette.muted,
      fontSize: 12,
      height: 1.6,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GenAiDisclosure(
          key: ValueKey('agent-tool-${call.id}'),
          dense: true,
          rail: false,
          color: palette.muted,
          leading: GenAiIcon(
            unknown || failed
                ? GenAiGlyph.info
                : complete
                    ? GenAiGlyph.check
                    : GenAiGlyph.more,
            color: color,
          ),
          title: genAiAgentToolName(call.name),
          subtitle: status,
          summary: summary.isEmpty ? null : summary,
          children: [
            if (result?['reused'] == true)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text('复用已有结果', style: body),
              ),
            Padding(
              // Reference .technical: 12px above the soft monospaced block.
              padding: const EdgeInsets.only(top: 12),
              child: GenAiDisclosure(
                dense: true,
                rail: false,
                leading: const GenAiIcon(GenAiGlyph.code),
                title: '技术详情',
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: palette.soft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      const JsonEncoder.withIndent('  ').convert(result ?? call.arguments),
                      contextMenuBuilder: genAiTextSelectionContextMenu,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFamily: kGenAiMonospaceFamily,
                        fontFamilyFallback: kGenAiMonospaceFallback,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (generated)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 6, end: 6, bottom: 8),
            child: images.isEmpty
                ? Text('图片未能直接预览，可查看图片记录。', style: body)
                : Column(
                    children: [
                      for (final uri in images)
                        _GenAiAgentImagePreview(
                          key: ValueKey('agent-image-${call.id}-$uri'),
                          uri: uri,
                        ),
                    ],
                  ),
          ),
        if ((generated || unknown) && call.name == 'generate_image')
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onOpenImages,
              icon: const GenAiIcon(GenAiGlyph.image, size: 17),
              label: const Text('查看图片'),
            ),
          ),
      ],
    );
  }

  List<Uri> _verifiedImages(Map<dynamic, dynamic> payload) {
    final values = payload['images'];
    if (values is! List) return const [];
    final images = <Uri>[];
    for (final value in values) {
      if (value is! String) continue;
      final display = genAiAutomaticImageUri(
        value,
        imageDisplayUri: imageDisplayUri,
      );
      if (display != null && !images.contains(display)) images.add(display);
      if (images.length == 4) break;
    }
    return images;
  }
}

class _GenAiAgentImagePreview extends StatefulWidget {
  const _GenAiAgentImagePreview({
    super.key,
    required this.uri,
  });

  final Uri uri;

  @override
  State<_GenAiAgentImagePreview> createState() => _GenAiAgentImagePreviewState();
}

class _GenAiAgentImagePreviewState extends State<_GenAiAgentImagePreview> {
  DialogRoute<void>? _viewer;

  Widget _image() => GenAiImageActions(
        image: NetworkImage(widget.uri.toString()),
        link: genAiImageUri(widget.uri.path),
        child: Image.network(
          widget.uri.toString(),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text('图片暂时无法预览，请查看图片记录。'),
            ),
          ),
        ),
      );

  void _open() {
    if (_viewer != null) return;
    final route = DialogRoute<void>(
      context: context,
      builder: (context) => genAiThemeScope(
        context,
        Dialog(
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
                left: 8,
                child: IconButton.filledTonal(
                  tooltip: '关闭图片预览',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const GenAiIcon(GenAiGlyph.close),
                ),
              ),
            ],
          ),
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
          onTap: _open,
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
                    child: Center(child: _image()),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// Shows the adapter's immutable prepared action, never model-authored claims.
///
/// The layout follows the design draft's booking slip: a 22px accent glyph,
/// a 15px title with a muted subtitle, then two-column details separated from
/// the header by a rule, and the footer actions.
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

  static const _bookingFields = {'sport', 'court', 'date', 'time', 'price'};

  static String _detailLabel(String key) =>
      const {
        'venue': '场地',
        'prompt': '画面描述',
        'model': '模型',
        'size': '分辨率',
        'quality': '质量',
        'count': '数量',
        'quota': '额度',
        'previous_outcome': '此前操作',
        'date': '日期',
        'sport': '运动',
        'court': '场地',
        'time': '时段',
        'players': '人数',
        'price': '费用',
        'contact': '联系信息',
        'policy': '预约限制',
      }[key] ??
      key;

  static String _detailValue(MapEntry<String, Object?> entry) => entry.key == 'quality'
      ? const {'low': '普通', 'medium': '标准', 'high': '精细'}[entry.value] ?? '${entry.value}'
      : '${entry.value ?? '—'}';

  /// The booking slip leads with 场地 (sport + court), then date, time and
  /// price; every other prepared field follows in its original order.
  static List<MapEntry<String, Object?>> _details(
    bool reservation,
    Map<String, Object?> details,
  ) {
    if (!reservation) return details.entries.toList();
    final venue = [
      details['sport'],
      details['court'],
    ]
        .where((value) => value != null && '$value'.trim().isNotEmpty)
        .map((value) => '$value')
        .join(' · ');
    return [
      if (venue.isNotEmpty) MapEntry<String, Object?>('venue', venue),
      for (final key in const ['date', 'time', 'price'])
        if (details.containsKey(key)) MapEntry<String, Object?>(key, details[key]),
      for (final entry in details.entries)
        if (!_bookingFields.contains(entry.key)) entry,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = GenAiPalette.of(context);
    final reservation = call.name == 'reserve_court';
    final narrow = MediaQuery.sizeOf(context).width < 680;
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: palette.muted,
      fontSize: 11,
    );
    final valueStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: narrow ? 12 : 14,
      height: 1.5,
    );
    final details = _details(reservation, prepared.details);
    return Container(
      key: const ValueKey('agent-approval'),
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: EdgeInsets.all(narrow ? 17 : 20),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: palette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              GenAiIcon(
                reservation ? GenAiGlyph.calendar : GenAiGlyph.image,
                size: 22,
                color: palette.accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      reservation ? '确认预约' : '确认生成图片',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      reservation ? '本次仅预约这一场' : '确认后才会执行，可能扣除学校额度',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: palette.muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (details.isNotEmpty)
            Container(
              padding: const EdgeInsets.only(top: 14, bottom: 18),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: palette.line)),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Reference .booking-detail: two 1fr columns with 13px gaps;
                  // long values such as an image prompt take the full row.
                  final half = (constraints.maxWidth - 13) / 2;
                  final twoColumns = half >= 150;
                  return Wrap(
                    spacing: 13,
                    runSpacing: 13,
                    children: [
                      for (final entry in details)
                        SizedBox(
                          width: twoColumns && _detailValue(entry).length <= 24
                              ? half
                              : constraints.maxWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_detailLabel(entry.key), style: labelStyle),
                              const SizedBox(height: 5),
                              SelectableText(
                                _detailValue(entry),
                                contextMenuBuilder: genAiTextSelectionContextMenu,
                                style: valueStyle,
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                key: const ValueKey('agent-reject'),
                onPressed: onReject,
                style: OutlinedButton.styleFrom(minimumSize: const Size(88, 44)),
                child: const Text('取消'),
              ),
              FilledButton(
                key: const ValueKey('agent-approve'),
                onPressed: onApprove,
                style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
                child: Text(reservation ? '确认这一场' : '确认生成'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
