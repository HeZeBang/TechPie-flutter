import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/genai_workspace_controller.dart';
import 'audio/genai_recording_bar.dart';
import 'genai_icons.dart';
import 'genai_theme.dart';

/// Draft input and responsive controls. Values and callbacks are supplied by
/// the workspace; this widget only owns draft/focus repaint subscriptions.
class GenAiComposer extends StatefulWidget {
  const GenAiComposer({
    super.key,
    required this.draft,
    required this.inputFocus,
    required this.hint,
    required this.wide,
    required this.workspaceWidth,
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
    this.modelSelectorWidth = 0,
    this.horizontalPadding = 24,
  });

  final TextEditingController draft;
  final FocusNode inputFocus;
  final String hint;
  final bool wide;

  /// Width of the surface the composer is laid out in. Every responsive
  /// decision uses this instead of the window's MediaQuery width, so the
  /// composer follows its actual column when a sidebar or split view changes
  /// the available room.
  final double workspaceWidth;
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

  /// Width reserved for [modelSelector] when deciding which modes fit inline.
  final double modelSelectorWidth;
  final double horizontalPadding;

  @override
  State<GenAiComposer> createState() => _GenAiComposerState();
}

class _GenAiComposerState extends State<GenAiComposer> {
  static const _toolListAction = 'tool-list';

  GenAiPalette get _palette => GenAiPalette.of(context);
  ThemeData get _theme => Theme.of(context);
  Color get _accent => _theme.colorScheme.primary;
  Color get _muted => _theme.colorScheme.onSurfaceVariant;
  bool get _canSend =>
      widget.canSubmit && (widget.draft.text.trim().isNotEmpty || widget.attachments.isNotEmpty);

  /// Draft phone composer: icon-only modes, 40 × 42 controls and a 14px
  /// surface radius at or below 680px of workspace width.
  bool get _phone => widget.workspaceWidth <= 680;

  /// The draft's extra-narrow phone tier: 36px-wide controls, no context
  /// ring and an 84px model button.
  bool get _tiny => widget.workspaceWidth < 360;

  /// Inset that puts the "+" glyph's left edge on the textarea's text edge:
  /// the composer surface and the textarea both add their leading padding
  /// before this control, so the glyph needs the textarea's horizontal
  /// padding (4) inside its own tap target.
  static const _moreGlyphInset = 4.0;

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

  bool get _audioBusy => widget.recognizingAudio || widget.recording || widget.startingRecording;

  static const _menuRowPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);

  /// Attachments first, then both modes with their current state, as in the
  /// draft's "+" popover. The mode rows are always present; a capability the
  /// current conversation lacks leaves its row disabled rather than hidden.
  List<PopupMenuEntry<String>> _menuItems() => [
        if (widget.supportsDocuments)
          _menuItem(
            key: const ValueKey('genai-upload-file'),
            value: 'document',
            icon: const GenAiIcon(GenAiGlyph.file),
            label: '上传文档',
          ),
        _menuItem(
          key: const ValueKey('genai-upload-image'),
          value: 'image',
          icon: const GenAiIcon(GenAiGlyph.image),
          label: '上传图片',
        ),
        if (widget.supportsAudio)
          _menuItem(
            key: const ValueKey('genai-upload-audio'),
            value: 'audio',
            icon: const GenAiIcon(GenAiGlyph.audio),
            label: '上传音频',
            enabled: !_audioBusy,
            disabled: _audioBusy,
          ),
        const PopupMenuDivider(height: 9),
        _menuItem(
          key: const ValueKey('genai-thinking-menu-toggle'),
          value: 'thinking',
          icon: const GenAiIcon(GenAiGlyph.brain),
          label: '深度思考',
          selected: widget.thinkingEnabled,
          enabled: widget.supportsThinking,
          disabled: !widget.supportsThinking,
          checkKey: const ValueKey('genai-thinking-menu-check'),
        ),
        _menuItem(
          key: const ValueKey('genai-agent-menu-toggle'),
          value: 'campus',
          icon: const GenAiIcon(GenAiGlyph.tools),
          label: '校园工具',
          selected: widget.agentEnabled,
          enabled: widget.agentAvailable,
          disabled: !widget.agentAvailable,
          checkKey: const ValueKey('genai-agent-menu-check'),
        ),
        if (widget.agentAvailable) ...[
          const PopupMenuDivider(height: 9),
          _menuItem(
            key: const ValueKey('genai-tool-list-menu'),
            value: _toolListAction,
            icon: const GenAiIcon(GenAiGlyph.info),
            label: '查看可用工具',
          ),
        ],
      ];

  /// Draft popover row: 42px minimum height, 8/10 padding, a 17px sprite, a
  /// 10px gap and a 13px label; selection is an accent check on the trailing
  /// edge and an unavailable capability keeps its current-state check.
  PopupMenuItem<String> _menuItem({
    Key? key,
    required String value,
    required Widget icon,
    required String label,
    bool selected = false,
    bool enabled = true,
    bool disabled = false,
    Key? checkKey,
  }) =>
      PopupMenuItem<String>(
        key: key,
        value: value,
        enabled: enabled,
        height: 42,
        padding: _menuRowPadding,
        child: _menuRow(icon, label, selected: selected, disabled: disabled, checkKey: checkKey),
      );

  Widget _menuRow(
    Widget icon,
    String title, {
    bool selected = false,
    bool disabled = false,
    Key? checkKey,
  }) {
    final color = disabled ? _muted.withValues(alpha: .4) : _muted;
    return Row(
      children: [
        IconTheme.merge(
          // The draft keeps leading menu icons muted in every state; only the
          // trailing check carries the accent when a mode is selected.
          data: IconThemeData(size: 17, color: color),
          child: icon,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: disabled ? _muted.withValues(alpha: .5) : _theme.colorScheme.onSurface,
            ),
          ),
        ),
        if (selected) GenAiIcon(GenAiGlyph.check, key: checkKey, color: _accent, size: 17),
      ],
    );
  }

  /// [width] and [height] are the control's fixed tap target; the glyph stays
  /// on the leading edge rather than centred so its left edge lines up with
  /// the textarea text (the draft's centred 40px target leaves a ~6px gap).
  Widget _moreMenu({
    double width = 48,
    double height = 48,
  }) {
    final items = _menuItems();
    const tooltip = '添加附件与更多选项';
    final glyph = GenAiIcon(
      GenAiGlyph.add,
      key: const ValueKey('genai-composer-more-icon'),
      size: 21,
      color: _muted,
    );
    final control = SizedBox(
      width: width,
      height: height,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: _moreGlyphInset),
          child: glyph,
        ),
      ),
    );
    return Tooltip(
      message: tooltip,
      child: Builder(
        builder: (anchorContext) => InkWell(
          key: const ValueKey('genai-composer-more'),
          borderRadius: BorderRadius.circular(8),
          onTap: widget.sending
              ? null
              : () async {
                  final action = await genAiShowMenu<String>(
                    context: context,
                    anchorContext: anchorContext,
                    items: items,
                    semanticLabel: '聊天选项',
                  );
                  if (mounted && action != null) _handleMenuAction(action);
                },
          child: control,
        ),
      ),
    );
  }

  /// The tool list is composer-owned: it only describes what the campus
  /// agent can do, so it does not need the workspace to route an action.
  void _handleMenuAction(String action) {
    if (action == _toolListAction) {
      unawaited(_showToolList());
      return;
    }
    widget.onMenuAction(action);
  }

  Future<void> _showToolList() => genAiShowDialog<void>(
        context: context,
        builder: (dialogContext) => Dialog(
          key: const ValueKey('genai-tool-list-dialog'),
          // The draft dialog is 500px wide, or the screen minus 32px on phones.
          insetPadding: const EdgeInsets.all(16),
          constraints: BoxConstraints(
            maxWidth: 500,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * .9,
          ),
          child: Column(
            key: const ValueKey('genai-tool-list-content'),
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '校园工具',
                        style: _theme.textTheme.titleMedium?.copyWith(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: _theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('genai-tool-list-close'),
                      tooltip: '关闭',
                      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                      padding: EdgeInsets.zero,
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: GenAiIcon(GenAiGlyph.close, size: 18, color: _muted),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, thickness: 1, color: _palette.line),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: _toolRows(),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  /// Compact rows mirror the draft's settings list: a 17px icon, a 13px
  /// title and an 11px description, separated at 17px vertical rhythm.
  List<Widget> _toolRows() {
    const tools = [
      (GenAiIcon(GenAiGlyph.clock), '当前时间', '日期、时区'),
      (GenAiIcon(GenAiGlyph.calendar), '课表与学期', '查看学期、每周课程'),
      (GenAiIcon(GenAiGlyph.file), '作业', '待办与截止时间'),
      (GenAiIcon(GenAiGlyph.calendar), '场馆预约', '查询空场；逐场确认后预约'),
      (GenAiIcon(GenAiGlyph.image), '图片创作', '生成图片；查看和比较历史图片'),
      (GenAiIcon(GenAiGlyph.search), '对话检索', '查找本会话中的记录'),
    ];
    return [
      for (var i = 0; i < tools.length; i++) ...[
        _toolRow(tools[i].$1, tools[i].$2, tools[i].$3),
        if (i != tools.length - 1) Divider(height: 1, color: _palette.line),
      ],
    ];
  }

  Widget _toolRow(Widget icon, String title, String subtitle) => Padding(
        key: ValueKey('genai-tool-row-$title'),
        padding: const EdgeInsets.symmetric(vertical: 17),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconTheme.merge(data: IconThemeData(size: 17, color: _muted), child: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, color: _theme.colorScheme.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 11, color: _muted, height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  static const _modePadding = EdgeInsets.symmetric(horizontal: 4);

  TextStyle get _modeLabelStyle => _theme.textTheme.labelLarge!.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
      );

  /// Reserve the state indicator so toggling does not move adjacent controls.
  double _modeChipWidth(String label, {required bool compact, required bool selected}) {
    if (compact) return 48;
    final painter = TextPainter(
      text: TextSpan(text: label, style: _modeLabelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    // Keep overflow decisions aligned with the mode chip's own row: 4px
    // padding each side, the icon box, a 7px gap and the optional 4px dot
    // preceded by a 5px gap.
    final width = painter.width.ceilToDouble() + (compact ? 20 : 18) + 8 + 7 + 9;
    painter.dispose();
    return width;
  }

  Widget _modeChip({
    required String key,
    required String label,
    required Widget icon,
    required bool selected,
    required bool compact,
    double? phoneWidth,
    required ValueChanged<bool>? onSelected,
  }) {
    // Compact controls keep their size in both states.
    final iconOnly = phoneWidth != null || compact;
    final labelStyle = _modeLabelStyle.copyWith(color: selected ? _accent : _muted);
    final radius = BorderRadius.circular(8);
    return Semantics(
      key: phoneWidth != null ? ValueKey(key) : null,
      label: '$label，${selected ? '已开启' : '已关闭'}',
      excludeSemantics: true,
      toggled: selected,
      onTap: onSelected == null ? null : () => onSelected(!selected),
      child: Tooltip(
        message: iconOnly ? label : '',
        child: Material(
          key: phoneWidth == null ? ValueKey(key) : null,
          color: selected ? _palette.accentSoft : Colors.transparent,
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: onSelected == null ? null : () => onSelected(!selected),
            child: Container(
              height: phoneWidth != null ? 42 : 30,
              width: phoneWidth ?? (iconOnly ? 48 : null),
              padding: phoneWidth != null
                  ? EdgeInsets.zero
                  : iconOnly
                      ? const EdgeInsets.symmetric(horizontal: 6)
                      : _modePadding,
              child: iconOnly
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(size: 18, color: selected ? _accent : _muted),
                          child: KeyedSubtree(key: ValueKey('$key-icon'), child: icon),
                        ),
                        if (selected)
                          Positioned(
                            right: 7,
                            top: 6,
                            child: Container(
                              key: ValueKey('$key-dot'),
                              width: 3,
                              height: 3,
                              decoration: BoxDecoration(color: _accent, shape: BoxShape.circle),
                            ),
                          ),
                      ],
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconTheme.merge(
                          data: IconThemeData(
                            size: compact ? 19 : 17,
                            color: selected ? _accent : _muted,
                          ),
                          child: icon,
                        ),
                        if (!iconOnly) ...[
                          const SizedBox(width: 7),
                          Text(label, style: labelStyle),
                          ...[
                            const SizedBox(width: 5),
                            Container(
                              key: ValueKey('$key-dot'),
                              width: 4,
                              height: 4,
                              decoration: BoxDecoration(
                                color: selected ? _accent : Colors.transparent,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _audioButton() {
    final phone = _phone;
    final width = _tiny ? 36.0 : 40.0;
    return GestureDetector(
      // Keep the semantics structure stable while recording changes the
      // inner button label.
      onLongPress: !widget.supportsAudio
          ? null
          : () {
              if (!widget.sending && !widget.recognizingAudio && !widget.recording) {
                widget.onPickAudio();
              }
            },
      child: SizedBox(
        width: phone ? width : null,
        height: phone ? 42 : null,
        child: IconButton(
          key: const ValueKey('genai-audio-stt'),
          padding: phone ? EdgeInsets.zero : null,
          constraints: phone
              ? BoxConstraints.tightFor(width: width, height: 42)
              : const BoxConstraints(minWidth: 44, minHeight: 48),
          style: phone
              ? IconButton.styleFrom(
                  padding: EdgeInsets.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                )
              : null,
          icon: widget.recognizingAudio
              ? SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: _accent,
                    semanticsLabel: '正在识别语音',
                  ),
                )
              : widget.recording
                  ? GenAiIcon(
                      GenAiGlyph.stop,
                      size: 20,
                      color: _theme.colorScheme.error,
                      semanticLabel: '完成录音并识别',
                    )
                  : GenAiIcon(
                      GenAiGlyph.mic,
                      size: 19,
                      color: _muted,
                      semanticLabel: !widget.supportsRecording ? '选择音频文件' : '语音输入',
                    ),
          onPressed: widget.sending || widget.recognizingAudio
              ? null
              : !widget.supportsRecording
                  ? widget.onPickAudio
                  : widget.recording
                      ? widget.onStopRecording
                      : widget.onStartRecording,
        ),
      ),
    );
  }

  Widget _sendButton() {
    final size = _phone ? 42.0 : 38.0;
    return IconButton.filled(
      key: const ValueKey('genai-send'),
      constraints: BoxConstraints.tightFor(width: size, height: size),
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
        fixedSize: Size(size, size),
        minimumSize: Size(size, size),
        maximumSize: Size(size, size),
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: _accent,
        foregroundColor: _theme.colorScheme.onPrimary,
        disabledBackgroundColor: _palette.soft,
        disabledForegroundColor: _muted,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: widget.sending
          ? const GenAiIcon(GenAiGlyph.stop, size: 20, semanticLabel: '停止生成')
          : const GenAiIcon(GenAiGlyph.arrow, size: 20, semanticLabel: '发送消息'),
    );
  }

  Widget _contextSlot() {
    final phone = _phone;
    return SizedBox(
      width: phone ? 24 : 28,
      height: phone ? 42 : 48,
      child: widget.contextStatus,
    );
  }

  Widget _toolbar() => LayoutBuilder(
        builder: (context, constraints) =>
            _phone ? _phoneToolbar(constraints) : _desktopToolbar(constraints),
      );

  /// Icon-only draft toolbar for the phone tier. At 360px and above the
  /// controls pair with a compact context ring and the model button; below
  /// that the context ring drops out, controls narrow to 36px and wrapped
  /// actions align to the trailing edge.
  Widget _phoneToolbar(BoxConstraints constraints) {
    final width = _tiny ? 36.0 : 40.0;
    final showThinking = widget.supportsThinking;
    final showCampus = widget.agentAvailable && widget.agentEnabled;
    final modes = <Widget>[
      _moreMenu(
        width: width,
        height: 42,
      ),
      if (showThinking)
        _modeChip(
          key: 'genai-thinking-toggle',
          label: '深度思考',
          icon: const GenAiIcon(GenAiGlyph.brain),
          selected: widget.thinkingEnabled,
          compact: true,
          phoneWidth: width,
          onSelected: widget.sending ? null : widget.onThinkingChanged,
        ),
      if (showCampus)
        _modeChip(
          key: 'genai-agent-toggle',
          label: '校园工具',
          icon: const GenAiIcon(GenAiGlyph.tools),
          selected: widget.agentEnabled,
          compact: true,
          phoneWidth: width,
          onSelected: widget.sending ? null : widget.onAgentChanged,
        ),
    ];
    final hasAudio = widget.supportsRecording || widget.supportsAudio;
    final contextWidth = widget.contextStatus == null || _tiny ? 0.0 : 24;
    final otherWidth = contextWidth + (hasAudio ? width : 0) + 42;
    final modesWidth = width + (showThinking ? width + 2 : 0) + (showCampus ? width + 2 : 0);
    // The model name is measured naturally; this row only trims it when the
    // modes and the fixed actions have taken the rest of the line.
    final modelNatural = widget.modelSelector == null ? 0.0 : widget.modelSelectorWidth;
    const inlineGap = 4.0;
    final remaining = constraints.maxWidth - modesWidth - inlineGap - otherWidth;
    final inline = remaining >= (widget.modelSelector == null ? 0.0 : 44.0);
    final stackedLimit = (constraints.maxWidth - otherWidth).clamp(0.0, double.infinity);
    final modelWidth =
        inline ? modelNatural.clamp(0.0, remaining) : modelNatural.clamp(0.0, stackedLimit);
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.modelSelector != null)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: modelWidth),
            child: SizedBox(height: 42, child: widget.modelSelector),
          ),
        if (widget.contextStatus != null && !_tiny) _contextSlot(),
        if (hasAudio) _audioButton(),
        _sendButton(),
      ],
    );
    if (inline) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Wrap(spacing: 2, runSpacing: 2, children: modes),
          actions,
        ],
      );
    }
    // Wrapped toolbar: modes keep the leading edge and the actions group is
    // pushed to the trailing edge, as the draft's <360px rules do.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(spacing: 2, runSpacing: 2, children: modes),
        ),
        const SizedBox(height: 5),
        Align(alignment: AlignmentDirectional.centerEnd, child: actions),
      ],
    );
  }

  Widget _desktopToolbar(BoxConstraints constraints) {
    final hasAudio = widget.supportsRecording || widget.supportsAudio;
    final modelNatural = widget.modelSelector == null ? 0.0 : widget.modelSelectorWidth;
    final otherWidth = (widget.contextStatus != null ? 28.0 : 0.0) + (hasAudio ? 44.0 : 0.0) + 38.0;
    const gap = 8.0;
    // The model keeps its measured width until the row runs out; the "+" target
    // and the fixed actions are reserved first, so no artificial per-tier cap
    // is needed. Anything left over goes back to the modes.
    final singleLineModelLimit =
        (constraints.maxWidth - 48 - otherWidth - gap).clamp(0.0, double.infinity);
    final singleLineModelWidth = modelNatural.clamp(0.0, singleLineModelLimit);
    final available = constraints.maxWidth - singleLineModelWidth - otherWidth - gap;
    // Labels need room beside the model and send; otherwise icons.
    final compact = constraints.maxWidth < 560;
    final thinkingWidth = _modeChipWidth(
      '深度思考',
      compact: compact,
      selected: widget.thinkingEnabled,
    );
    final campusWidth = _modeChipWidth(
      '校园工具',
      compact: compact,
      selected: widget.agentEnabled,
    );
    // Icon-only modes sit on padded 48px targets that already separate them.
    final spacing = compact ? 0.0 : 4.0;
    var showThinking = widget.supportsThinking;
    var showCampus = widget.agentAvailable;
    double modesWidth() =>
        48 +
        (showThinking ? thinkingWidth + spacing : 0) +
        (showCampus ? campusWidth + spacing : 0);
    // Reserve the microphone and Send first. Preserve active modes;
    // hide inactive campus tools before hiding inactive thinking.
    if (modesWidth() > available && showCampus && !widget.agentEnabled) {
      showCampus = false;
    }
    if (modesWidth() > available && !widget.thinkingEnabled) {
      showThinking = false;
    }
    final modes = <Widget>[
      _moreMenu(),
      if (showThinking)
        _modeChip(
          key: 'genai-thinking-toggle',
          label: '深度思考',
          icon: const GenAiIcon(GenAiGlyph.brain),
          selected: widget.thinkingEnabled,
          compact: compact,
          onSelected: widget.sending ? null : widget.onThinkingChanged,
        ),
      if (showCampus)
        _modeChip(
          key: 'genai-agent-toggle',
          label: '校园工具',
          icon: const GenAiIcon(GenAiGlyph.tools),
          selected: widget.agentEnabled,
          compact: compact,
          onSelected: widget.sending ? null : widget.onAgentChanged,
        ),
    ];
    Widget actions(double modelWidth) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.modelSelector != null)
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: modelWidth),
                child: widget.modelSelector,
              ),
            if (widget.contextStatus != null) _contextSlot(),
            if (hasAudio) _audioButton(),
            // The padded target already leaves a visual gap.
            _sendButton(),
          ],
        );
    final widestMode = [
      48.0,
      if (showThinking) thinkingWidth,
      if (showCampus) campusWidth,
    ].reduce((a, b) => a > b ? a : b);
    if (available < widestMode) {
      // At very large text scales, keep active labels readable and let
      // actions use their own row instead of squeezing the labels.
      final stackedModelLimit = (constraints.maxWidth - otherWidth).clamp(0.0, double.infinity);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(spacing: spacing, runSpacing: 2, children: modes),
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: actions(modelNatural.clamp(0.0, stackedModelLimit)),
          ),
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Wrap(
            spacing: spacing,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: modes,
          ),
        ),
        const SizedBox(width: gap),
        actions(singleLineModelWidth),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = _palette;
    final focused = widget.inputFocus.hasFocus;
    final phone = _phone;
    return Align(
      alignment: Alignment.center,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: GenAiPalette.readingWidth + widget.horizontalPadding * 2,
        ),
        padding: EdgeInsets.fromLTRB(
          widget.horizontalPadding,
          phone ? 9 : 12,
          widget.horizontalPadding,
          phone ? 12 : 22,
        ),
        child: Semantics(
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
                padding: phone
                    ? EdgeInsets.fromLTRB(_tiny ? 8 : 10, 12, _tiny ? 8 : 10, 8)
                    : const EdgeInsets.fromLTRB(16, 16, 16, 10),
                decoration: BoxDecoration(
                  color: palette.raised,
                  borderRadius: BorderRadius.circular(phone ? 14 : 17),
                  border: Border.all(
                    color: focused ? Color.lerp(palette.line, palette.accent, .42)! : palette.line,
                  ),
                  boxShadow: _theme.brightness == Brightness.light
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .045),
                            blurRadius: 24,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.recording)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: GenAiRecordingBar(
                          seconds: widget.recordingSeconds,
                          onCancel: widget.onCancelRecording,
                          onComplete: widget.onStopRecording,
                        ),
                      ),
                    if (widget.attachments.isNotEmpty) _attachmentTray(),
                    _input(),
                    _toolbar(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _input() => Focus(
        onKeyEvent: (_, event) {
          if (switch (Theme.of(context).platform) {
                TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => false,
                _ => true,
              } &&
              event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.enter &&
              !HardwareKeyboard.instance.isShiftPressed &&
              !(widget.draft.value.composing.isValid &&
                  !widget.draft.value.composing.isCollapsed)) {
            if (!widget.sending && _canSend) widget.onSend();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: TextField(
          key: const ValueKey('genai-prompt'),
          controller: widget.draft,
          focusNode: widget.inputFocus,
          minLines: 2,
          maxLines: 6,
          textAlignVertical: TextAlignVertical.top,
          strutStyle: StrutStyle(
            fontSize: _phone ? 15 : 14,
            height: 1.65,
            forceStrutHeight: true,
          ),
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: TextStyle(fontSize: _phone ? 15 : 14, height: 1.65, color: _muted),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isCollapsed: true,
            constraints: const BoxConstraints(minHeight: 50),
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          ),
          style: TextStyle(fontSize: _phone ? 15 : 14, height: 1.65),
        ),
      );

  Widget _attachmentTray() {
    final errors = widget.attachments.where((a) => a.error != null).map((a) => a.error!).toSet();
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(
            builder: (context, constraints) => SizedBox(
              height: 48,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.attachments.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) =>
                    _attachmentChip(widget.attachments[i], constraints.maxWidth),
              ),
            ),
          ),
          if (widget.hasFailedUploads) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GenAiIcon(GenAiGlyph.info, size: 14, color: _theme.colorScheme.error),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${errors.join('；')}。请重试或删除失败的附件后发送。',
                    style: TextStyle(fontSize: 12, color: _theme.colorScheme.error, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentChip(GenAiAttachment att, double maxWidth) {
    final error = att.error != null;
    final color = error ? _theme.colorScheme.error : _theme.colorScheme.onSurface;
    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: EdgeInsetsDirectional.only(start: att.isImage ? 4 : 10),
      decoration: BoxDecoration(
        color: error ? _theme.colorScheme.errorContainer.withValues(alpha: .3) : null,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: error ? _theme.colorScheme.error.withValues(alpha: .5) : _palette.line,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _attachmentThumbnail(att),
          const SizedBox(width: 8),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: error ? 180 : 150),
              child: Tooltip(
                message: att.error ?? att.name,
                child: Text(
                  att.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color),
                ),
              ),
            ),
          ),
          if (error)
            IconButton(
              key: ValueKey('genai-retry-attachment-${att.id}'),
              tooltip: '重新上传',
              onPressed: () => widget.onRetryAttachment(att.id),
              constraints: const BoxConstraints.tightFor(width: 48, height: 48),
              icon: GenAiIcon(GenAiGlyph.refresh, size: 17, color: _theme.colorScheme.error),
            ),
          IconButton(
            key: ValueKey('genai-remove-attachment-${att.id}'),
            tooltip: '移除附件',
            onPressed: () => widget.onRemoveAttachment(att.id),
            constraints: const BoxConstraints.tightFor(width: 48, height: 48),
            icon: GenAiIcon(
              GenAiGlyph.close,
              size: 16,
              color: error ? _theme.colorScheme.error : _muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentThumbnail(GenAiAttachment att) {
    if (!att.isImage) {
      if (att.uploading) {
        return SizedBox.square(
          dimension: 14,
          child: CircularProgressIndicator(strokeWidth: 1.5, color: _accent),
        );
      }
      return GenAiIcon(
        att.error != null ? GenAiGlyph.info : GenAiGlyph.file,
        size: 17,
        color: att.error != null ? _theme.colorScheme.error : _accent,
      );
    }
    final bytes = att.bytes.isNotEmpty ? Uint8List.fromList(att.bytes) : null;
    final url = att.imageUrl;
    final Widget image = bytes != null
        ? Image.memory(
            bytes,
            width: 36,
            height: 36,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _thumbnailFallback(),
          )
        : url != null && url.isNotEmpty
            ? Image.network(
                url,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _thumbnailFallback(),
              )
            : _thumbnailFallback();
    return KeyedSubtree(
      key: ValueKey('genai-attachment-thumbnail-${att.id}'),
      child: GestureDetector(
        onTap: () => widget.onPreviewAttachment(att),
        child: Tooltip(
          message: '点击查看大图',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: SizedBox.square(
              dimension: 36,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  image,
                  if (att.uploading)
                    const ColoredBox(
                      color: Color(0x73000000),
                      child: Center(
                        child: SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                      ),
                    )
                  else if (att.error != null)
                    ColoredBox(
                      color: _theme.colorScheme.error.withValues(alpha: .4),
                      child: const Center(
                        child: GenAiIcon(GenAiGlyph.warning, size: 16, color: Colors.white),
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

  Widget _thumbnailFallback() => Container(
        width: 36,
        height: 36,
        color: _palette.accentSoft,
        child: GenAiIcon(GenAiGlyph.image, size: 16, color: _accent),
      );
}
