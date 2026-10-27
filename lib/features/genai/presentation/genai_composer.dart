import 'dart:ui' show SemanticsRole;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/genai_workspace_controller.dart';
import 'audio/genai_recording_bar.dart';

/// Draft input and responsive controls. Values and callbacks are supplied by
/// the workspace; this widget only owns draft/focus repaint subscriptions.
class GenAiComposer extends StatefulWidget {
  const GenAiComposer({
    super.key,
    required this.draft,
    required this.inputFocus,
    required this.hint,
    required this.wide,
    required this.keyboardOpen,
    required this.sending,
    required this.thinkingEnabled,
    this.supportsThinking = true,
    required this.agentAvailable,
    required this.agentEnabled,
    required this.recognizingAudio,
    required this.attachments,
    required this.hasPendingUploads,
    required this.hasFailedUploads,
    required this.canSubmit,
    required this.supportsRecording,
    required this.supportsAudio,
    required this.supportsDocuments,
    required this.recording,
    required this.startingRecording,
    required this.recordingSeconds,
    required this.onSend,
    required this.onStop,
    required this.onThinkingChanged,
    required this.onAgentChanged,
    required this.onMenuAction,
    required this.onPickAudio,
    required this.onStartRecording,
    required this.onStopRecording,
    required this.onCancelRecording,
    required this.onRetryAttachment,
    required this.onRemoveAttachment,
    required this.onPreviewAttachment,
    this.contextStatus,
    this.modelSelector,
  });

  final TextEditingController draft;
  final FocusNode inputFocus;
  final String hint;
  final bool wide;
  final bool keyboardOpen;
  final bool sending;
  final bool thinkingEnabled;
  final bool supportsThinking;
  final bool agentAvailable;
  final bool agentEnabled;
  final bool recognizingAudio;
  final List<GenAiAttachment> attachments;
  final bool hasPendingUploads;
  final bool hasFailedUploads;
  final bool canSubmit;
  final bool supportsRecording;
  final bool supportsAudio;
  final bool supportsDocuments;
  final bool recording;
  final bool startingRecording;
  final int recordingSeconds;
  final VoidCallback onSend;
  final VoidCallback onStop;
  final ValueChanged<bool> onThinkingChanged;
  final ValueChanged<bool> onAgentChanged;
  final ValueChanged<String> onMenuAction;
  final VoidCallback onPickAudio;
  final VoidCallback onStartRecording;
  final VoidCallback onStopRecording;
  final VoidCallback onCancelRecording;
  final ValueChanged<String> onRetryAttachment;
  final ValueChanged<String> onRemoveAttachment;
  final ValueChanged<GenAiAttachment> onPreviewAttachment;
  final Widget? contextStatus;
  final Widget? modelSelector;

  @override
  State<GenAiComposer> createState() => _GenAiComposerState();
}

class _GenAiComposerState extends State<GenAiComposer> {
  ThemeData get _theme => Theme.of(context);
  Color get _accent => _theme.colorScheme.primary;
  Color get _muted => _theme.colorScheme.onSurfaceVariant;
  Color get _border => _theme.colorScheme.outlineVariant;
  bool get _canSend =>
      widget.canSubmit && (widget.draft.text.trim().isNotEmpty || widget.attachments.isNotEmpty);

  @override
  void initState() {
    super.initState();
    widget.draft.addListener(_changed);
    widget.inputFocus.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant GenAiComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.draft != widget.draft) {
      oldWidget.draft.removeListener(_changed);
      widget.draft.addListener(_changed);
    }
    if (oldWidget.inputFocus != widget.inputFocus) {
      oldWidget.inputFocus.removeListener(_changed);
      widget.inputFocus.addListener(_changed);
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.draft.removeListener(_changed);
    widget.inputFocus.removeListener(_changed);
    super.dispose();
  }

  Widget _composerMoreMenu({
    bool collapsedThinking = false,
    bool collapsedCampus = false,
  }) {
    final items = <PopupMenuEntry<String>>[
      if (collapsedThinking)
        PopupMenuItem<String>(
          key: const ValueKey('genai-thinking-menu-toggle'),
          value: 'thinking',
          child: _composerMenuRow(Icons.psychology_outlined, '深度思考'),
        ),
      if (collapsedCampus)
        PopupMenuItem<String>(
          key: const ValueKey('genai-agent-menu-toggle'),
          value: 'campus',
          child: _composerMenuRow(
            Icons.auto_awesome_outlined,
            '校园工具',
          ),
        ),
      if (widget.supportsDocuments)
        PopupMenuItem<String>(
          key: const ValueKey('genai-upload-file'),
          value: 'document',
          child: _composerMenuRow(
            Icons.description_outlined,
            '上传文档',
          ),
        ),
      PopupMenuItem<String>(
        key: const ValueKey('genai-upload-image'),
        value: 'image',
        child: _composerMenuRow(
          Icons.image_outlined,
          '上传图片',
        ),
      ),
      if (widget.supportsAudio)
        PopupMenuItem<String>(
          value: 'audio',
          enabled: !widget.recognizingAudio && !widget.recording && !widget.startingRecording,
          child: _composerMenuRow(
            Icons.audio_file_outlined,
            '上传音频',
            disabled: widget.recognizingAudio || widget.recording || widget.startingRecording,
          ),
        ),
    ];
    const tooltip = '添加附件';
    final icon = Icon(Icons.add, size: 20, color: _muted);
    // Flutter's popup route does not avoid viewInsets. A scrollable sheet
    // keeps every action reachable while the software keyboard is visible.
    if (widget.keyboardOpen) {
      return IconButton(
        key: const ValueKey('genai-composer-more'),
        tooltip: tooltip,
        icon: icon,
        onPressed: widget.sending
            ? null
            : () async {
                final action = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  showDragHandle: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                  ),
                  builder: (context) => Padding(
                    padding: MediaQuery.viewInsetsOf(context),
                    child: SafeArea(
                      top: false,
                      child: Semantics(
                        role: SemanticsRole.menu,
                        explicitChildNodes: true,
                        label: '聊天选项',
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: items,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                if (mounted && action != null) widget.onMenuAction(action);
              },
      );
    }
    return PopupMenuButton<String>(
      key: const ValueKey('genai-composer-more'),
      constraints: const BoxConstraints(minWidth: 228),
      position: PopupMenuPosition.over,
      tooltip: tooltip,
      enabled: !widget.sending,
      icon: icon,
      onSelected: widget.onMenuAction,
      itemBuilder: (_) => items,
    );
  }

  Widget _composerMenuRow(
    IconData icon,
    String title, {
    bool selected = false,
    bool disabled = false,
  }) =>
      Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: (selected ? _accent : _muted).withValues(alpha: disabled ? .04 : .1),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              icon,
              size: 18,
              color: disabled
                  ? _muted.withValues(alpha: .4)
                  : selected
                      ? _accent
                      : _muted,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: disabled ? _muted.withValues(alpha: .5) : _theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, color: _accent, size: 18),
        ],
      );

  static const _modePadding = EdgeInsets.symmetric(horizontal: 4);
  static const _modeLabelPadding = EdgeInsets.symmetric(horizontal: 4, vertical: 2);

  TextStyle get _modeLabelStyle => _theme.textTheme.labelLarge!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  double _modeChipWidth(String label) {
    final painter = TextPainter(
      text: TextSpan(text: label, style: _modeLabelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Keep overflow decisions aligned with the actual icon and control padding.
    final width =
        painter.width.ceilToDouble() + 20 + _modePadding.horizontal + _modeLabelPadding.horizontal;
    painter.dispose();
    return width;
  }

  Widget _modeChip({
    required String key,
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool>? onSelected,
  }) =>
      FilterChip(
        key: ValueKey(key),
        label: Text(
          label,
          style: _modeLabelStyle.copyWith(color: selected ? _accent : _muted),
        ),
        avatar: Icon(
          selected ? Icons.check_rounded : icon,
          size: 18,
          color: selected ? _accent : _muted,
        ),
        avatarBoxConstraints: const BoxConstraints.tightFor(width: 20, height: 20),
        selected: selected,
        onSelected: onSelected,
        showCheckmark: false,
        padding: _modePadding,
        labelPadding: _modeLabelPadding,
        visualDensity: VisualDensity.standard,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        side: BorderSide(
          color: selected ? _accent.withValues(alpha: .28) : Colors.transparent,
        ),
        // Resolve both states explicitly so a host chip theme cannot make an
        // inactive mode look selected. Keep selection visible while sending.
        color: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Color.alphaBlend(
                  _accent.withValues(alpha: .1),
                  _theme.colorScheme.surfaceContainerLow,
                )
              : Colors.transparent,
        ),
      );

  Widget _composerToolbar() => LayoutBuilder(
        builder: (context, constraints) {
          final hasAudio = widget.supportsRecording || widget.supportsAudio;
          final modelWidth = widget.modelSelector == null ? 0.0 : 180.0;
          final actionWidth = modelWidth +
              (modelWidth > 0 ? 8 : 0) +
              (widget.contextStatus != null ? 32 : 0) +
              (hasAudio ? 48 : 0) +
              6 +
              48;
          final available = constraints.maxWidth - actionWidth - 8;
          final thinkingWidth = _modeChipWidth('深度思考');
          final campusWidth = _modeChipWidth('校园工具');
          var showThinking = widget.supportsThinking;
          var showCampus = widget.agentAvailable;
          double modesWidth() =>
              48 + (showThinking ? thinkingWidth + 6 : 0) + (showCampus ? campusWidth + 6 : 0);
          // Reserve the microphone and Send first. Preserve active modes;
          // hide inactive campus tools before hiding inactive thinking.
          if (modesWidth() > available && showCampus && !widget.agentEnabled) {
            showCampus = false;
          }
          if (modesWidth() > available && !widget.thinkingEnabled) {
            showThinking = false;
          }
          final primary = <Widget>[
            SizedBox(
              width: 48,
              height: 48,
              child: _composerMoreMenu(
                collapsedThinking: widget.supportsThinking && !showThinking,
                collapsedCampus: widget.agentAvailable && !showCampus,
              ),
            ),
            if (showThinking)
              _modeChip(
                key: 'genai-thinking-toggle',
                label: '深度思考',
                icon: Icons.psychology_outlined,
                selected: widget.thinkingEnabled,
                onSelected: widget.sending ? null : widget.onThinkingChanged,
              ),
            if (showCampus)
              _modeChip(
                key: 'genai-agent-toggle',
                label: '校园工具',
                icon: Icons.auto_awesome_outlined,
                selected: widget.agentEnabled,
                onSelected: widget.sending ? null : widget.onAgentChanged,
              ),
          ];
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.modelSelector != null) ...[
                SizedBox(width: modelWidth, child: widget.modelSelector),
                const SizedBox(width: 8),
              ],
              if (widget.contextStatus != null)
                SizedBox(width: 32, height: 48, child: widget.contextStatus),
              if (widget.supportsRecording || widget.supportsAudio)
                GestureDetector(
                  // Keep the semantics structure stable while
                  // recording changes the inner button label.
                  onLongPress: !widget.supportsAudio
                      ? null
                      : () {
                          if (!widget.sending && !widget.recognizingAudio && !widget.recording) {
                            widget.onPickAudio();
                          }
                        },
                  child: IconButton(
                    key: const ValueKey('genai-audio-stt'),
                    constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                    icon: widget.recognizingAudio
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _accent,
                              semanticsLabel: '正在识别语音',
                            ),
                          )
                        : widget.recording
                            ? const Icon(
                                Icons.stop_circle_outlined,
                                size: 19,
                                color: Colors.redAccent,
                                semanticLabel: '完成录音并识别',
                              )
                            : Icon(
                                Icons.mic_none,
                                size: 18,
                                color: _muted,
                                semanticLabel: !widget.supportsRecording
                                    ? '选择音频文件'
                                    : widget.supportsAudio
                                        ? '麦克风录音，长按选择音频文件'
                                        : '麦克风录音',
                              ),
                    onPressed: widget.sending || widget.recognizingAudio
                        ? null
                        : !widget.supportsRecording
                            ? widget.onPickAudio
                            : widget.recording
                                ? widget.onStopRecording
                                : widget.onStartRecording,
                    visualDensity: VisualDensity.standard,
                  ),
                ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('genai-send'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: widget.hasPendingUploads
                    ? '等待附件上传完成'
                    : widget.hasFailedUploads
                        ? '请重试或移除失败附件'
                        : null,
                onPressed: widget.sending
                    ? widget.onStop
                    : _canSend
                        ? () => widget.onSend()
                        : null,
                style: IconButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: _theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  widget.sending ? Icons.stop_rounded : Icons.arrow_upward_rounded,
                  size: 21,
                  semanticLabel: widget.sending ? '停止生成' : '发送消息',
                ),
              ),
            ],
          );
          final modes = primary;
          final widestMode = [
            48.0,
            if (showThinking) thinkingWidth,
            if (showCampus) campusWidth,
          ].reduce((a, b) => a > b ? a : b);
          if (available < widestMode) {
            // At very large text scales, keep active labels readable and let
            // actions use their own row instead of squeezing the labels.
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(spacing: 6, runSpacing: 2, children: modes),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: modes,
                ),
              ),
              const SizedBox(width: 8),
              actions,
            ],
          );
        },
      );

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 848),
          padding: EdgeInsets.fromLTRB(
            widget.wide ? 24 : 14,
            12,
            widget.wide ? 24 : 14,
            12,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                container: true,
                label: '输入消息',
                onTap: widget.inputFocus.requestFocus,
                child: TextFieldTapRegion(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    excludeFromSemantics: true,
                    onTap: widget.inputFocus.requestFocus,
                    child: AnimatedContainer(
                      key: const ValueKey('genai-composer-surface'),
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.fromLTRB(16, 10, 12, 8),
                      decoration: BoxDecoration(
                        color: _theme.colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color:
                              widget.inputFocus.hasFocus ? _accent.withValues(alpha: .45) : _border,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .04),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.recording)
                            GenAiRecordingBar(
                              seconds: widget.recordingSeconds,
                              onCancel: widget.onCancelRecording,
                              onComplete: widget.onStopRecording,
                            ),
                          if (widget.attachments.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 44,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      itemCount: widget.attachments.length,
                                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                                      itemBuilder: (context, i) {
                                        final att = widget.attachments[i];
                                        final isError = att.error != null;
                                        return Container(
                                          padding: EdgeInsets.fromLTRB(
                                            att.isImage ? 5 : 8,
                                            4,
                                            8,
                                            4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: isError
                                                ? _theme.colorScheme.errorContainer
                                                    .withValues(alpha: .35)
                                                : _accent.withValues(alpha: .08),
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(
                                              color: isError
                                                  ? _theme.colorScheme.error.withValues(alpha: .5)
                                                  : _accent.withValues(alpha: .2),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              _buildAttachmentThumbnail(att, context),
                                              const SizedBox(width: 8),
                                              ConstrainedBox(
                                                constraints: BoxConstraints(
                                                  maxWidth: isError ? 180 : 140,
                                                ),
                                                child: Tooltip(
                                                  message: att.error ?? att.name,
                                                  child: Text(
                                                    att.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w500,
                                                      color: isError
                                                          ? _theme.colorScheme.error
                                                          : _accent,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              if (isError) ...[
                                                const SizedBox(width: 4),
                                                InkWell(
                                                  key: ValueKey(
                                                    'genai-retry-attachment-${att.id}',
                                                  ),
                                                  onTap: () => widget.onRetryAttachment(att.id),
                                                  borderRadius: BorderRadius.circular(10),
                                                  child: Tooltip(
                                                    message: '重新上传',
                                                    child: Icon(
                                                      Icons.refresh_rounded,
                                                      size: 14,
                                                      color: _theme.colorScheme.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(width: 4),
                                              InkWell(
                                                key: ValueKey(
                                                  'genai-remove-attachment-${att.id}',
                                                ),
                                                onTap: () => widget.onRemoveAttachment(att.id),
                                                borderRadius: BorderRadius.circular(10),
                                                child: Tooltip(
                                                  message: '移除附件',
                                                  child: Icon(
                                                    Icons.close,
                                                    size: 13,
                                                    color:
                                                        isError ? _theme.colorScheme.error : _muted,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                  if (widget.hasFailedUploads) ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.error_outline,
                                          size: 13,
                                          color: _theme.colorScheme.error,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            '${widget.attachments.where((a) => a.error != null).map((a) => a.error!).toSet().join('；')}。请重试或删除失败的附件后发送。',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _theme.colorScheme.error,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          Focus(
                            onKeyEvent: (_, event) {
                              if (event is KeyDownEvent &&
                                  event.logicalKey == LogicalKeyboardKey.enter &&
                                  !HardwareKeyboard.instance.isShiftPressed &&
                                  !(widget.draft.value.composing.isValid &&
                                      !widget.draft.value.composing.isCollapsed)) {
                                widget.onSend();
                                return KeyEventResult.handled;
                              }
                              return KeyEventResult.ignored;
                            },
                            child: TextField(
                              key: const ValueKey('genai-prompt'),
                              controller: widget.draft,
                              focusNode: widget.inputFocus,
                              minLines: 1,
                              maxLines: 6,
                              keyboardType: TextInputType.multiline,
                              textInputAction: TextInputAction.newline,
                              decoration: InputDecoration(
                                hintText: widget.hint,
                                hintStyle: const TextStyle(fontSize: 14.5),
                                border: InputBorder.none,
                                enabledBorder: InputBorder.none,
                                focusedBorder: InputBorder.none,
                                filled: false,
                                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              style: const TextStyle(fontSize: 15.5, height: 1.6),
                            ),
                          ),
                          _composerToolbar(),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildAttachmentThumbnail(
    GenAiAttachment att,
    BuildContext context,
  ) {
    if (!att.isImage) {
      if (att.uploading) {
        return SizedBox(
          width: 14,
          height: 14,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: _accent,
          ),
        );
      }
      if (att.error != null) {
        return Icon(
          Icons.error_outline,
          size: 16,
          color: _theme.colorScheme.error,
        );
      }
      return Icon(
        Icons.description_outlined,
        size: 16,
        color: _accent,
      );
    }

    final bytes = att.bytes.isNotEmpty ? Uint8List.fromList(att.bytes) : null;
    final url = att.imageUrl;

    Widget imageContent;
    if (bytes != null) {
      imageContent = Image.memory(
        bytes,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildThumbnailFallback(context),
      );
    } else if (url != null && url.isNotEmpty) {
      imageContent = Image.network(
        url,
        width: 32,
        height: 32,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildThumbnailFallback(context),
      );
    } else {
      imageContent = _buildThumbnailFallback(context);
    }

    return KeyedSubtree(
      key: ValueKey('genai-attachment-thumbnail-${att.id}'),
      child: GestureDetector(
        onTap: () => widget.onPreviewAttachment(att),
        child: Tooltip(
          message: '点击查看大图',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                fit: StackFit.expand,
                alignment: Alignment.center,
                children: [
                  imageContent,
                  if (att.uploading)
                    Container(
                      color: Colors.black.withValues(alpha: .45),
                      child: const Center(
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    )
                  else if (att.error != null)
                    Container(
                      color: _theme.colorScheme.error.withValues(alpha: .4),
                      child: const Center(
                        child: Icon(
                          Icons.warning_amber_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThumbnailFallback(BuildContext context) => Container(
        width: 32,
        height: 32,
        color: _accent.withValues(alpha: .12),
        child: Icon(Icons.image_outlined, size: 16, color: _accent),
      );
}
