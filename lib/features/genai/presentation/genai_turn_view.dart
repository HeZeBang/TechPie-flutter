import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../application/genai_workspace_controller.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import 'genai_agent_widgets.dart';
import 'genai_copy.dart';
import 'genai_hover_region.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';
import 'genai_thinking_view.dart';
import 'genai_web_search_view.dart';
import 'markdown/genai_markdown.dart';

/// Everything a turn needs from the workspace, so the turn stays a plain view.
final class GenAiTurnActions {
  const GenAiTurnActions({
    required this.copy,
    required this.openLink,
    required this.changeTurn,
    required this.retry,
    required this.exportConversation,
    required this.openImages,
    required this.showImage,
    required this.imageDisplayUri,
    required this.markdownImage,
    required this.toggleTts,
    required this.approve,
    required this.reject,
  });

  final void Function(String text, String message) copy;
  final void Function(String? link) openLink;
  final void Function(int index, String action) changeTurn;
  final void Function(int index) retry;
  final VoidCallback exportConversation;
  final VoidCallback openImages;
  final void Function({Uint8List? bytes, String? url}) showImage;
  final Uri Function(String) imageDisplayUri;
  final MarkdownImageBuilder markdownImage;
  final void Function(int index, String answer) toggleTts;
  final void Function(GenAiPendingAgentApproval pending) approve;
  final void Function(GenAiPendingAgentApproval pending) reject;
}

/// Per-frame workspace facts a turn renders; values, not controller access.
final class GenAiTurnContext {
  const GenAiTurnContext({
    required this.index,
    required this.count,
    required this.sending,
    required this.connected,
    required this.touch,
    required this.pendingApproval,
    required this.latestVisual,
    required this.supportsPlayback,
    required this.playingTtsIndex,
    required this.loadingTts,
    this.workspaceWidth = 960,
  });

  final int index;
  final int count;
  final bool sending;
  final bool connected;
  final bool touch;
  final GenAiPendingAgentApproval? pendingApproval;
  final (String, int)? latestVisual;
  final bool supportsPlayback;
  final int? playingTtsIndex;
  final bool loadingTts;
  final double workspaceWidth;

  bool get compact => workspaceWidth < 960;
  bool get phone => workspaceWidth <= 680;
  bool get isLast => index == count - 1;
}

/// Draft popover rows: 42 px minimum, 10/8 px padding, 13 px labels,
/// 17 px muted icons and a 10 px gap. The shared route paints each native
/// row's 7 px hover plate through `genAiMenuEntry`; a danger label keeps the
/// accent while its icon stays muted, as the draft specifies.
PopupMenuItem<String> _turnMenuItem(
  GenAiPalette palette,
  String value,
  Widget icon,
  String label, {
  bool enabled = true,
  bool danger = false,
}) =>
    PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          IconTheme.merge(
            data: IconThemeData(size: 17, color: palette.muted),
            child: icon,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: danger ? palette.accent : null),
          ),
        ],
      ),
    );

/// One exchange: a quiet user bubble with hover actions, then the answer with
/// its activity line, content, status notes and a compact action row.
class GenAiTurnView extends StatelessWidget {
  const GenAiTurnView({
    super.key,
    required this.turn,
    required this.context,
    required this.actions,
  });

  final GenAiConversationTurn turn;
  final GenAiTurnContext context;
  final GenAiTurnActions actions;

  bool get _incomplete => const [
        GenAiChatPhase.cancelled,
        GenAiChatPhase.interrupted,
        GenAiChatPhase.failed,
        GenAiChatPhase.needsLogin,
      ].contains(turn.phase);

  @override
  Widget build(BuildContext buildContext) {
    final palette = GenAiPalette.of(buildContext);
    if (turn.isHistoryGap) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Text(
          '部分历史记录无法读取，上下文已在此处断开。',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.muted, fontSize: 12),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UserMessage(turn: turn, turnContext: context, actions: actions),
          Semantics(
            container: true,
            // Keep selectable text semantics from covering embedded visuals.
            explicitChildNodes: true,
            label: turn.isAgent ? '校园工具回复' : 'AI 回复',
            child: _answer(buildContext, palette),
          ),
        ],
      ),
    );
  }

  Widget _answer(BuildContext buildContext, GenAiPalette palette) {
    final index = context.index;
    final pending = context.isLast && turn.isAgent ? context.pendingApproval : null;
    final note = TextStyle(color: palette.muted, fontSize: 12.5, height: 1.7);
    final hasActivity = turn.agentEvents.isNotEmpty ||
        turn.agentActivity.isNotEmpty ||
        turn.reasoning.isNotEmpty ||
        turn.citations.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (turn.isAgent && hasActivity)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GenAiAgentToolActivity(
              key: ValueKey(turn.id),
              events: turn.agentEvents.values.toList(),
              activity: turn.agentActivity,
              thinking: turn.isAgentThinking,
              legacyReasoning: turn.reasoning,
              legacyCitations: turn.citations,
              onOpenLink: actions.openLink,
              running: context.sending && context.isLast,
              stopped: _incomplete,
              imageDisplayUri: actions.imageDisplayUri,
              onOpenImages: context.sending ? null : actions.openImages,
            ),
          ),
        if (pending != null)
          GenAiAgentApprovalCard(
            call: pending.call,
            prepared: pending.prepared,
            onApprove: () => actions.approve(pending),
            onReject: () => actions.reject(pending),
          ),
        if (!turn.isAgent && turn.citations.isNotEmpty)
          GenAiWebSearchView(citations: turn.citations, onOpenLink: actions.openLink),
        if (!turn.isAgent &&
            (turn.reasoning.isNotEmpty ||
                turn.phase == GenAiChatPhase.streaming && turn.answer.isEmpty))
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GenAiThinkingView(
              reasoning: turn.reasoning,
              isThinking: turn.phase == GenAiChatPhase.streaming && turn.answer.isEmpty,
              durationMs: turn.thinkingDurationMs,
              onTapLink: actions.openLink,
            ),
          ),
        if (turn.answer.isEmpty &&
            !_incomplete &&
            turn.reasoning.isEmpty &&
            (!turn.isAgent || context.pendingApproval == null))
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: Row(
              children: [
                SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: palette.accent),
                ),
                const SizedBox(width: 10),
                Text(turn.isAgent ? turn.agentStatus : '正在思考…', style: note),
              ],
            ),
          ),
        if (turn.answer.isNotEmpty)
          GenAiMarkdown(
            data: turn.answer,
            selectable: true,
            compact: context.phone,
            interactiveVisuals: true,
            latestVisual: context.latestVisual,
            visualAnswerId: turn.id,
            imageBuilder: actions.markdownImage,
            onTapLink: (_, href, __) => actions.openLink(href),
          ),
        if (turn.isAgent)
          GenAiAgentImages(
            events: turn.agentEvents.values,
            imageDisplayUri: actions.imageDisplayUri,
          ),
        if (_incomplete)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: _failureNotice(palette),
          ),
        if (turn.finishReason == GenAiFinishReason.length)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('已达到本次回复的长度限制', style: note),
          ),
        if (turn.finishReason == GenAiFinishReason.contentFilter)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('平台已结束本次回复', style: note),
          ),
        _answerActions(buildContext, palette, index),
      ],
    );
  }

  bool get _campusFailure =>
      context.isLast && turn.failure?.kind == GenAiFailureKind.campusNetworkRequired;

  Widget _failureNotice(GenAiPalette palette) {
    if (turn.phase == GenAiChatPhase.cancelled && turn.failure == null) {
      return Text('已停止', style: TextStyle(fontSize: 13, color: palette.muted));
    }
    final title = _campusFailure
        ? '暂时无法连接校园 GenAI'
        : turn.isAgent && turn.failure?.kind == GenAiFailureKind.protocol && turn.answer.isNotEmpty
            ? '回复未验证，可以继续整理。'
            : turn.failure != null
                ? genAiFailureText(turn.failure!)
                : turn.isAgent && turn.agentStatus.isNotEmpty
                    ? turn.agentStatus
                    : '已停止';
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.5,
            color: palette.text,
          ),
        ),
        if (_campusFailure) ...[
          const SizedBox(height: 4),
          Text(
            '请连接校园网或校园 VPN 后重试。',
            style: TextStyle(fontSize: 12, height: 1.6, color: palette.muted),
          ),
        ],
      ],
    );
    final retry = _campusFailure && context.connected
        ? OutlinedButton(
            key: ValueKey('genai-retry-${context.index}'),
            onPressed: context.sending ? null : () => actions.retry(context.index),
            child: const Text('重试', style: TextStyle(fontSize: 12)),
          )
        : null;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GenAiIcon(GenAiGlyph.info, size: 18, color: palette.accent),
          SizedBox(width: context.phone ? 10 : 14),
          Expanded(
            child: context.phone && retry != null
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [text, const SizedBox(height: 10), retry],
                  )
                : text,
          ),
          if (!context.phone && retry != null) ...[const SizedBox(width: 14), retry],
        ],
      ),
    );
  }

  Widget _answerActions(BuildContext hostContext, GenAiPalette palette, int index) {
    final playing = context.playingTtsIndex == index;
    final retry = _incomplete && !_campusFailure && context.isLast && context.connected;
    final actionSize = context.phone ? 40.0 : 32.0;
    final canRegenerate = context.isLast &&
        context.connected &&
        !context.sending &&
        !_incomplete &&
        turn.phase == GenAiChatPhase.completed &&
        turn.answer.isNotEmpty;
    if (turn.answer.isEmpty && !retry) return const SizedBox(height: 4);
    IconButton action({
      required Key key,
      required String tooltip,
      required Widget icon,
      required VoidCallback? onPressed,
    }) =>
        IconButton(
          key: key,
          tooltip: tooltip,
          icon: icon,
          color: palette.muted,
          iconSize: 16,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          constraints: BoxConstraints.tightFor(width: actionSize, height: actionSize),
          onPressed: onPressed,
        );
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          if (turn.answer.isNotEmpty) ...[
            action(
              key: ValueKey('genai-copy-$index'),
              tooltip: '复制回复',
              icon: const GenAiIcon(GenAiGlyph.copy),
              onPressed: () => actions.copy(turn.answer, '已复制回复'),
            ),
            if (context.supportsPlayback)
              action(
                key: ValueKey('genai-tts-$index'),
                tooltip: playing ? '停止播放' : '语音播报',
                icon: context.loadingTts && playing
                    ? SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.5, color: palette.accent),
                      )
                    : GenAiIcon(
                        playing ? GenAiGlyph.stop : GenAiGlyph.speaker,
                        color: playing ? palette.accent : null,
                      ),
                onPressed: () => actions.toggleTts(index, turn.answer),
              ),
            SizedBox.square(
              dimension: actionSize,
              child: Builder(
                builder: (anchorContext) => IconButton(
                  key: ValueKey('genai-answer-menu-$index'),
                  tooltip: '回答操作',
                  icon: GenAiIcon(GenAiGlyph.more, color: palette.muted),
                  iconSize: 16,
                  color: palette.muted,
                  padding: EdgeInsets.zero,
                  style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                  constraints: BoxConstraints.tightFor(width: actionSize, height: actionSize),
                  onPressed: () => unawaited(
                    _openAnswerMenu(anchorContext, hostContext, index, canRegenerate),
                  ),
                ),
              ),
            ),
          ],
          if (retry)
            TextButton.icon(
              key: ValueKey('genai-retry-$index'),
              onPressed: context.sending ? null : () => actions.retry(index),
              style: TextButton.styleFrom(foregroundColor: palette.muted),
              icon: const GenAiIcon(GenAiGlyph.refresh, size: 16),
              label: const Text('重试', style: TextStyle(fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  /// The anchored popover outlives the action row: hover can hide it while the
  /// menu is still open. The turn's own element is therefore the unit of
  /// currency — a rebuild that changed the turn, its index or its answer (or a
  /// disposed turn) drops the late choice instead of acting on stale state.
  Future<void> _openAnswerMenu(
    BuildContext anchorContext,
    BuildContext hostContext,
    int index,
    bool canRegenerate,
  ) async {
    final answer = turn.answer;
    final palette = GenAiPalette.of(hostContext);
    final value = await genAiShowMenu<String>(
      context: hostContext,
      anchorContext: anchorContext,
      items: [
        _turnMenuItem(
          palette,
          'retry',
          const GenAiIcon(GenAiGlyph.refresh),
          '重新生成',
          enabled: canRegenerate,
        ),
        _turnMenuItem(
          palette,
          'export',
          const GenAiIcon(GenAiGlyph.download),
          '导出对话',
        ),
      ],
      minWidth: 220,
      gap: 7,
      semanticLabel: '回答操作',
    );
    if (value == null || !hostContext.mounted) return;
    final host = hostContext.widget;
    if (host is! GenAiTurnView ||
        !identical(host.actions, actions) ||
        host.turn.id != turn.id ||
        host.context.index != index ||
        host.turn.answer != answer) {
      return;
    }
    if (value == 'retry') {
      final canRetryNow = canRegenerate &&
          host.context.isLast &&
          host.context.connected &&
          !host.context.sending &&
          !host._incomplete &&
          host.turn.phase == GenAiChatPhase.completed &&
          host.turn.answer.isNotEmpty;
      if (!canRetryNow) return;
      actions.retry(index);
    } else if (value == 'export') {
      actions.exportConversation();
    }
  }
}

class _UserMessage extends StatelessWidget {
  const _UserMessage({required this.turn, required this.turnContext, required this.actions});

  final GenAiConversationTurn turn;
  final GenAiTurnContext turnContext;
  final GenAiTurnActions actions;

  @override
  Widget build(BuildContext hostContext) {
    final palette = GenAiPalette.of(hostContext);
    final index = turnContext.index;
    return GenAiHoverRegion(
      always: turnContext.touch || turnContext.compact,
      builder: (context, revealed) {
        final bubble = LayoutBuilder(
          builder: (context, constraints) => Container(
            key: ValueKey('genai-user-bubble-${turn.id}'),
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth * (turnContext.compact ? .9 : .86),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: palette.soft,
              borderRadius: const BorderRadiusDirectional.only(
                topStart: Radius.circular(16),
                topEnd: Radius.circular(16),
                bottomStart: Radius.circular(16),
                bottomEnd: Radius.circular(4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                ..._attachments(context, palette),
                Semantics(
                  container: true,
                  child: SelectableText(
                    turn.prompt,
                    style: TextStyle(
                      fontSize: turnContext.phone ? 13 : 14,
                      height: 1.7,
                      color: palette.text,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
        final buttons = _actions(palette, index, hostContext);
        if (turnContext.compact) {
          // Compact layouts keep the actions beside the bubble, bottom-aligned,
          // rather than in a separate row below it.
          return Padding(
            padding: EdgeInsets.only(bottom: turnContext.phone ? 24 : 25),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: bubble),
                const SizedBox(width: 6),
                buttons,
              ],
            ),
          );
        }
        // The fixed strip is the draft's 32px message margin. Actions are
        // positioned inside it, so revealing them never moves the bubble or the
        // answer, and they stay hit-testable and focusable.
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [bubble, const SizedBox(height: 32)],
            ),
            if (revealed) Positioned(right: 0, bottom: 2, child: buttons),
          ],
        );
      },
    );
  }

  Widget _actions(GenAiPalette palette, int index, BuildContext hostContext) => Row(
        key: ValueKey('genai-user-actions-${turn.id}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!turnContext.compact)
            IconButton(
              key: ValueKey('genai-turn-edit-${turn.id}'),
              tooltip: '编辑消息',
              icon: const GenAiIcon(GenAiGlyph.edit),
              iconSize: 15,
              color: palette.muted,
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              onPressed: turnContext.sending ? null : () => actions.changeTurn(index, 'edit'),
            ),
          _menu(palette, hostContext),
        ],
      );

  Widget _menu(GenAiPalette palette, BuildContext hostContext) {
    final items = <PopupMenuEntry<String>>[
      _turnMenuItem(palette, 'copy', const GenAiIcon(GenAiGlyph.copy), '复制内容'),
      _turnMenuItem(palette, 'edit', const GenAiIcon(GenAiGlyph.edit), '编辑并重新发送'),
      if (!turnContext.isLast)
        _turnMenuItem(palette, 'revert', const GenAiIcon(GenAiGlyph.undo), '回退到此处'),
      _turnMenuItem(
        palette,
        'delete',
        const GenAiIcon(GenAiGlyph.delete),
        '删除此轮及后续',
        danger: true,
      ),
    ];
    final enabled = !turnContext.sending && !turn.isHistoryGap;
    return SizedBox.square(
      dimension: 28,
      child: Builder(
        builder: (anchorContext) => IconButton(
          key: ValueKey('genai-turn-menu-${turn.id}'),
          tooltip: '消息操作',
          icon: GenAiIcon(GenAiGlyph.more, size: 16, color: palette.muted),
          iconSize: 18,
          color: palette.muted,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: enabled ? () => unawaited(_openMenu(anchorContext, hostContext, items)) : null,
        ),
      ),
    );
  }

  /// The shared menu can outlive the row that opened it, so a late choice is
  /// applied only while this message's own element is still mounted and still
  /// describes the same turn at the same index, and while the actions it
  /// offered are still allowed.
  Future<void> _openMenu(
    BuildContext anchorContext,
    BuildContext hostContext,
    List<PopupMenuEntry<String>> items,
  ) async {
    final prompt = turn.prompt;
    final index = turnContext.index;
    final value = await genAiShowMenu<String>(
      context: hostContext,
      anchorContext: anchorContext,
      items: items,
      minWidth: 200,
      gap: 7,
      semanticLabel: '消息操作',
    );
    if (value == null || !hostContext.mounted) return;
    final host = hostContext.widget;
    if (host is! _UserMessage ||
        !identical(host.actions, actions) ||
        host.turn.id != turn.id ||
        host.turn.prompt != prompt ||
        host.turnContext.index != index ||
        host.turnContext.sending ||
        host.turn.isHistoryGap) {
      return;
    }
    if (value == 'copy') {
      actions.copy(prompt, '已复制内容');
      return;
    }
    if (value == 'revert' && host.turnContext.isLast) return;
    actions.changeTurn(index, value);
  }

  List<Widget> _attachments(BuildContext context, GenAiPalette palette) {
    Widget framed(Widget image, VoidCallback onTap) => ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: GestureDetector(onTap: onTap, child: image),
        );
    final images = <Widget>[
      if (turn.attachedImageBytesList.isNotEmpty)
        for (final bytes in turn.attachedImageBytesList)
          framed(
            Image.memory(bytes, height: 180, fit: BoxFit.contain, errorBuilder: _broken),
            () => actions.showImage(bytes: bytes),
          )
      else
        for (final url in turn.attachedImageUrls) _remoteAttachment(context, url),
    ];
    return [
      if (images.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: images,
          ),
        ),
      if (turn.attachedFileNames.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              for (final name in turn.attachedFileNames)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: palette.line, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      GenAiIcon(GenAiGlyph.file, size: 17, color: palette.accent),
                      const SizedBox(width: 8),
                      Text(name, style: TextStyle(fontSize: 12, color: palette.text)),
                    ],
                  ),
                ),
            ],
          ),
        ),
    ];
  }

  Widget _remoteAttachment(BuildContext context, String url) {
    try {
      final displayUrl = actions.imageDisplayUri(url).toString();
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: GestureDetector(
          onTap: () => actions.showImage(url: displayUrl),
          child: Image.network(displayUrl, height: 180, fit: BoxFit.contain, errorBuilder: _broken),
        ),
      );
    } on GenAiFailure catch (error) {
      return _broken(context, error, null);
    } on FormatException catch (error) {
      return _broken(context, error, null);
    }
  }

  static Widget _broken(BuildContext context, Object _, StackTrace? __) => Container(
        padding: const EdgeInsets.all(8),
        color: GenAiPalette.of(context).hover,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GenAiIcon(GenAiGlyph.brokenImage, size: 16),
            SizedBox(width: 4),
            Text('图片无法加载', style: TextStyle(fontSize: 11)),
          ],
        ),
      );
}
