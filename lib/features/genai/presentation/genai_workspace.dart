import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../utils/platform.dart';
import '../../../widgets/adaptive_feedback.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_agent_contract.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'audio/genai_audio_player.dart';
import 'audio/genai_audio_recorder.dart';
import 'audio/genai_workspace_media.dart';
import 'genai_chat_copy.dart';
import 'genai_composer.dart';
import 'genai_context_status.dart';
import 'genai_conversation_menu.dart';
import 'genai_copy.dart';
import 'genai_history_controller.dart';
import 'genai_history_sidebar.dart';
import 'genai_icons.dart';
import 'genai_image.dart';
import 'genai_model_picker.dart';
import 'genai_theme.dart';
import 'genai_tools_page.dart';
import 'genai_turn_edit_dialog.dart';
import 'genai_turn_view.dart';
import 'genai_web_input_scope.dart';
import 'picker/genai_picker.dart';
import 'visuals/genai_visual_syntax.dart';

typedef GenAiLoginAction = Future<GenAiCredential?> Function(
  BuildContext context,
);

class GenAiWorkspace extends StatefulWidget {
  const GenAiWorkspace({
    super.key,
    required this.controller,
    required this.login,
    this.campusBound = false,
    this.onSignIn,
    this.onBindCampus,
    this.onCampusLogin,
    this.picker,
    this.audioPlayer,
    this.audioRecorder,
  });

  final GenAiWorkspaceController controller;
  final GenAiLoginAction login;
  final bool campusBound;
  final VoidCallback? onSignIn;
  final VoidCallback? onBindCampus;
  final VoidCallback? onCampusLogin;
  final GenAiPicker? picker;
  final GenAiAudioPlayer? audioPlayer;
  final GenAiAudioRecorder? audioRecorder;

  @override
  State<GenAiWorkspace> createState() => _GenAiWorkspaceState();
}

typedef _WorkspaceScope = (GenAiWorkspaceController, int, int);

class _GenAiWorkspaceState extends State<GenAiWorkspace> {
  final _draft = TextEditingController();
  final _inputFocus = FocusNode();
  // Keep composing state and keyboard focus when the empty view becomes a thread.
  final _composerKey = GlobalKey();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _scroll = ScrollController();
  bool _followingLatest = true;
  bool _showImages = false;
  bool _sidebarHidden = false;

  /// Whether the compact shell's history drawer is open. It is a local
  /// overlay rather than a route, so web visuals cannot detect it through
  /// [ModalRoute]; this flag is published to them through [GenAiWebInputScope].
  bool _drawerOpen = false;
  int _scrollRevision = 0;
  late final GenAiHistoryController _history;
  late final GenAiWorkspaceMedia _media;
  int _chatCopyIndex = DateTime.now().millisecondsSinceEpoch % genAiChatCopy.length;
  late String _copyGroupId;
  int _copyChangeRevision = 0;
  ({String hint, String title}) get _chatCopy => genAiChatCopy[_chatCopyIndex];
  Timer? _refresh;
  bool _openingLogin = false;
  GenAiCancellation? _deletionCheck;
  late int _draftSessionRevision;
  GenAiOwner? _draftOwner;
  Object? _draftAccountScope;
  GenAiWorkspaceController get _state => widget.controller;
  _WorkspaceScope get _scope => (_state, _state.sessions.revision, _state.conversationRevision);
  bool _isCurrent(_WorkspaceScope scope) => mounted && scope == _scope;

  /// The full surface width and the width of the chat column that remains
  /// after the sidebar. Both come from the layout, never from MediaQuery, so
  /// the workspace keeps its own breakpoints in an embedded or split view.
  /// These cached values are only valid after the first layout and are read
  /// by descendants or user callbacks after layout, not by overlay geometry.
  /// Dialogs use their own route's MediaQuery because they occupy the screen.
  double _stageWidth = GenAiPalette.wideBreakpoint;
  double _workspaceWidth = GenAiPalette.wideBreakpoint;

  late ThemeData _theme;
  GenAiPalette get _palette => GenAiPalette.of(context);
  bool get _canSend =>
      _state.connected &&
      _state.selectedModel != null &&
      !_state.sending &&
      !_state.hasPendingUploads &&
      !_state.hasFailedUploads &&
      (_draft.text.trim().isNotEmpty || _state.attachments.isNotEmpty);

  /// Touch layouts keep hover-only actions visible. The OHOS fork reports
  /// its own TargetPlatform, which the stock enum cannot name.
  bool get _platformTouch =>
      isOhos() ||
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS || TargetPlatform.fuchsia => true,
        _ => false,
      };

  /// Below the 960 px workspace breakpoint the shell is the compact one, so
  /// its controls behave as touch targets even on a desktop platform.
  bool get _touch => _platformTouch || _stageWidth < GenAiPalette.wideBreakpoint;

  /// Command on Apple platforms, Control elsewhere; never both, so Control+N
  /// keeps its macOS text-editing meaning.
  bool get _apple => switch (defaultTargetPlatform) {
        TargetPlatform.macOS || TargetPlatform.iOS => true,
        _ => false,
      };

  bool _searchOpen = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_scrolled);
    _history = GenAiHistoryController(_state);
    _media = GenAiWorkspaceMedia(
      workspace: _state,
      picker: widget.picker,
      audioPlayer: widget.audioPlayer,
      audioRecorder: widget.audioRecorder,
      onMessage: (message) => showAdaptiveFeedback(
        context: context,
        message: message,
        style: AdaptiveFeedbackStyle.error,
      ),
      onTranscription: (text, {required requestFocus}) {
        final current = _draft.text;
        _draft.text = current.isEmpty ? text : '$current $text';
        _draft.selection = TextSelection.collapsed(offset: _draft.text.length);
        if (requestFocus) _inputFocus.requestFocus();
      },
    )..addListener(_mediaChanged);
    _draftOwner = _state.sessions.owner;
    _draftAccountScope = _state.accountScope;
    _draftSessionRevision = _state.sessions.revision;
    _copyGroupId = _state.groupId;
    _state.addListener(_changed);
    unawaited(_state.restore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _theme = genAiTheme(Theme.of(context));
  }

  @override
  void didUpdateWidget(covariant GenAiWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    oldWidget.controller.cancelAgentForPageExit();
    _media.bindWorkspace(_state);
    _history.bindWorkspace(_state);
    _deletionCheck?.cancel();
    _deletionCheck = null;
    _draftOwner = _state.sessions.owner;
    _draftAccountScope = _state.accountScope;
    _draftSessionRevision = _state.sessions.revision;
    _copyGroupId = _state.groupId;
    _followingLatest = true;
    _scrollRevision++;
    _copyChangeRevision++;
    if (_state.turns.isEmpty) {
      _chatCopyIndex = (_chatCopyIndex + 1) % genAiChatCopy.length;
    }
    _draft.clear();
    _state.addListener(_changed);
    unawaited(_state.restore());
  }

  void _mediaChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    if (_copyGroupId != _state.groupId) {
      _followingLatest = true;
      _scrollRevision++;
      final controller = _state;
      final groupId = _copyGroupId = controller.groupId;
      final revision = ++_copyChangeRevision;
      if (controller.turns.isEmpty) {
        // Opening a saved chat briefly notifies an empty replacement group,
        // then restores its turns in the same synchronous operation. Wait for
        // that operation to finish before treating this as a fresh empty chat.
        scheduleMicrotask(() {
          if (!mounted ||
              revision != _copyChangeRevision ||
              !identical(controller, _state) ||
              controller.groupId != groupId ||
              controller.turns.isNotEmpty) {
            return;
          }
          setState(() {
            _chatCopyIndex = (_chatCopyIndex + 1) % genAiChatCopy.length;
          });
        });
      }
    }
    if (_draftOwner != _state.sessions.owner ||
        _draftAccountScope != _state.accountScope ||
        _draftSessionRevision != _state.sessions.revision) {
      _draftAccountScope = _state.accountScope;
      _draftSessionRevision = _state.sessions.revision;
      _draftOwner = _state.sessions.owner;
      _showImages = false;
      _draft.clear();
      _deletionCheck?.cancel();
      _deletionCheck = null;
    }
    if (!_state.sending || _state.pendingAgentApproval != null) {
      _refresh?.cancel();
      _refresh = null;
      _paint();
    } else {
      _refresh ??= Timer(const Duration(milliseconds: 40), () {
        _refresh = null;
        if (mounted) _paint();
      });
    }
  }

  void _scrolled() {
    final following = _scroll.position.extentBefore < 120;
    if (following != _followingLatest && mounted) {
      setState(() => _followingLatest = following);
    }
  }

  void _paint() {
    setState(() {});
    if (_followingLatest) _scrollToEnd(followingOnly: true);
  }

  void _scrollToEnd({bool followingOnly = false}) {
    final scope = _scope;
    final revision = _scrollRevision;
    if (!followingOnly) setState(() => _followingLatest = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isCurrent(scope) || !_scroll.hasClients) return;
      // A drag beginning after this frame was scheduled must win over follow.
      if (followingOnly && (!_followingLatest || revision != _scrollRevision)) {
        return;
      }
      _scroll.jumpTo(_scroll.position.minScrollExtent);
    });
  }

  void _stop() {
    if (!_state.sending) return;
    _state.stop();
    _inputFocus.requestFocus();
    showAdaptiveFeedback(context: context, message: '已停止');
  }

  Future<void> _login() async {
    if (_openingLogin || _state.connecting || _state.sessions.owner == null) {
      return;
    }
    final controller = _state;
    final revision = controller.sessions.revision;
    setState(() => _openingLogin = true);
    try {
      final credential = await widget.login(context);
      if (!mounted ||
          credential == null ||
          !identical(controller, _state) ||
          revision != controller.sessions.revision) {
        return;
      }
      await controller.connect(credential);
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '无法完成 GenAI 登录，请重试',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _openingLogin = false);
    }
  }

  void _closeDrawer() {
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      _scaffoldKey.currentState!.closeDrawer();
    }
  }

  Future<void> _openConversation(GenAiConversationSummary item) async {
    if (_state.sending) return;
    _closeDrawer();
    final sameConversation = item.id == _state.groupId;
    if (sameConversation && _state.archiveFailure == null) {
      setState(() => _showImages = false);
      return;
    }
    final controller = _state;
    final revision = controller.sessions.revision;
    final accountScope = controller.accountScope;
    final cancellation = GenAiCancellation();
    bool current() =>
        mounted &&
        identical(controller, _state) &&
        controller.sessions.revision == revision &&
        controller.accountScope == accountScope;
    try {
      final opened = await controller.openConversation(item.id, cancellation);
      if (!opened || !current() || controller.groupId != item.id) return;
      setState(() => _showImages = false);
      if (!sameConversation) _draft.clear();
      _scrollToEnd();
    } catch (_) {
      if (mounted && current()) {
        showAdaptiveFeedback(
          context: context,
          message: '加载对话失败',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final controller = _state;
    final revision = controller.sessions.revision;
    final accountScope = controller.accountScope;
    bool current() =>
        mounted &&
        identical(controller, _state) &&
        controller.sessions.revision == revision &&
        controller.accountScope == accountScope;
    final confirmed = await genAiShowDialog<bool>(
      context: context,
      builder: (dialogContext) => genAiThemeScope(
        dialogContext,
        AnimatedBuilder(
          animation: controller,
          builder: (_, __) => GenAiDialogFrame(
            title: Text(current() ? '删除此对话？' : '账号已切换'),
            content: Text(current() ? '这将删除此对话的本机和学校记录，无法撤销。' : '请在当前账号下重新打开对话操作。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: !current()
                    ? null
                    : () {
                        if (current()) Navigator.pop(dialogContext, true);
                      },
                child: const Text('删除'),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !current()) return;
    final cancellation = GenAiCancellation();
    try {
      await controller.deleteConversation(id, cancellation);
      if (mounted && current()) _history.remove(id);
    } catch (_) {
      if (mounted && current()) {
        showAdaptiveFeedback(
          context: context,
          message: '删除对话失败',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    }
  }

  Future<void> _checkDeletions() async {
    if (_deletionCheck != null) return;
    final controller = _state;
    final scope = controller.accountScope;
    final revision = controller.sessions.revision;
    final cancellation = GenAiCancellation();
    setState(() => _deletionCheck = cancellation);
    bool current() =>
        mounted &&
        identical(controller, _state) &&
        controller.accountScope == scope &&
        controller.sessions.revision == revision;
    try {
      await controller.reconcilePendingDeletions(cancellation);
      if (current() && !cancellation.isCancelled) await _history.load();
    } catch (error) {
      if (mounted && current() && !cancellation.isCancelled) {
        showAdaptiveFeedback(
          context: context,
          message: genAiFailureText(
            error is GenAiFailure ? error : const GenAiFailure(GenAiFailureKind.transport),
          ),
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (identical(_deletionCheck, cancellation) && mounted) {
        setState(() => _deletionCheck = null);
      }
    }
  }

  /// Image creation lives inside the workspace at every width, so the drawer,
  /// header and draft behave the same as in chat.
  void _openImages() {
    if (!_state.connected || _state.sending) return;
    _closeDrawer();
    _inputFocus.unfocus();
    setState(() => _showImages = true);
  }

  Future<void> _openUsage() async {
    if (!_state.connected) return;
    _closeDrawer();
    final controller = _state;
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => genAiThemeScope(
        dialogContext,
        _usageDialog(dialogContext, controller),
      ),
    );
  }

  /// The draft opens usage as a 500 px modal over the live shell instead of a
  /// pushed page, so history and the composer stay in place behind it.
  Widget _usageDialog(BuildContext dialogContext, GenAiWorkspaceController controller) {
    final size = MediaQuery.sizeOf(dialogContext);
    final palette = GenAiPalette.of(dialogContext);
    final width = (size.width - 32).clamp(0.0, 500.0).toDouble();
    final compact = size.width <= 600;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
      ),
      child: SizedBox(
        key: const ValueKey('genai-usage-dialog'),
        width: width,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: size.height * .8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(compact ? 16 : 22, 10, compact ? 8 : 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '用量与额度',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(dialogContext),
                      icon: const GenAiIcon(GenAiGlyph.close, size: 20),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: palette.line),
              Flexible(
                child: GenAiToolsPage(
                  key: const ValueKey('genai-usage-content'),
                  workspace: controller,
                  initialTab: GenAiToolsPage.usageTab,
                  picker: widget.picker,
                  embedded: true,
                  stageWidth: _stageWidth > 0 ? _stageWidth : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _newConversation() {
    _closeDrawer();
    setState(() => _showImages = false);
    _draft.clear();
    _state.newConversation();
    _inputFocus.requestFocus();
  }

  Future<void> _send([String? retry]) async {
    if (retry == null && !_canSend) return;
    if (!_state.connected ||
        _state.selectedModel == null ||
        _state.sending ||
        _state.hasFailedUploads) {
      return;
    }
    final raw = retry ?? _draft.text;
    final text = raw.trim().isEmpty && _state.attachments.isNotEmpty
        ? (_state.attachments.any((a) => a.isImage) ? '请分析这张图片' : '请分析上传的文档')
        : raw;
    if (text.trim().isEmpty) return;
    final scope = _scope;
    _inputFocus.requestFocus();
    final sending = _state.send(
      text,
      onAccepted: () {
        if (_isCurrent(scope) && retry == null && _draft.text == raw) _draft.clear();
      },
    );
    _scrollToEnd();
    await sending;
  }

  Future<void> _changeTurn(int index, String action) async {
    if (_state.sending || index >= _state.turns.length) return;
    final scope = _scope;
    final controller = _state;
    final turn = controller.turns[index];
    final keep = action == 'revert';
    final removed = controller.turns.skip(index + (keep ? 1 : 0)).toList();
    if (removed.isEmpty) return;
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => genAiThemeScope(
        dialogContext,
        GenAiTurnEditDialog(
          prompt: turn.prompt,
          action: action,
          hasComposerDraft: _draft.text.isNotEmpty || controller.attachments.isNotEmpty,
          hasAttachments: turn.attachedFileIds.isNotEmpty ||
              turn.attachedFileNames.isNotEmpty ||
              turn.attachedFileContents.isNotEmpty ||
              turn.attachedImageUrls.isNotEmpty ||
              turn.attachedImageUrl != null ||
              turn.attachedImageBytes != null ||
              turn.attachedImageBytesList.isNotEmpty,
          onSubmit: (result, onCommitted) async {
            if (!_isCurrent(scope)) return;
            try {
              await controller.changeTurn(
                turn.id,
                keepTurn: keep,
                replacement: action == 'edit' ? result : null,
                onCommitted: onCommitted,
              );
            } finally {
              if (mounted && identical(_state, controller)) unawaited(_history.load());
            }
          },
          removedTurns: removed.length,
          hasExternalActions: removed.any(
            (t) => t.agentEvents.values.any(genAiHasExternalEffect),
          ),
        ),
      ),
    );
  }

  Future<void> _retryTurn(int index) async {
    if (_state.sending || !_state.connected || _state.selectedModel == null) {
      return;
    }
    final sending = _state.retryTurn(index);
    _scrollToEnd();
    await sending;
  }

  Future<void> _copy(String text, [String message = '已复制回复']) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: message,
        duration: const Duration(seconds: 1),
      );
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(context: context, message: '无法复制，请手动选择文字');
      }
    }
  }

  Future<void> _openLink(String? link) async {
    final uri = Uri.tryParse(link ?? '');
    if (uri == null || !const ['https', 'http'].contains(uri.scheme) || uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '无法打开链接',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    }
  }

  @override
  void dispose() {
    _media.removeListener(_mediaChanged);
    _media.dispose();
    _history.dispose();
    _deletionCheck?.cancel();
    _state.removeListener(_changed);
    _state.cancelAgentForPageExit();
    _refresh?.cancel();
    _draft.dispose();
    _inputFocus.dispose();
    _scroll.removeListener(_scrolled);
    _scroll.dispose();
    super.dispose();
  }

  Widget _sidebar({required bool drawer}) => GenAiHistorySidebar(
        history: _history,
        connected: _state.connected,
        sending: _state.sending,
        activeId: _showImages ? '' : _state.groupId,
        imagesActive: _showImages,
        touch: _touch || drawer,
        // Draft rail: 232 px inline, 260 px as an overlay drawer.
        width: drawer ? 260 : 232,
        accountMenu: _accountMenu(),
        onNewChat: _newConversation,
        onImages: _openImages,
        onOpen: (item) => unawaited(_openConversation(item)),
        onSearch: () => unawaited(_openSearch()),
        shortcutLabel: _touch ? null : (_apple ? '⌘N' : 'Ctrl N'),
        onExit: Navigator.of(context).canPop() ? _exit : null,
        menuBuilder: (item) => GenAiConversationMenu(
          key: ValueKey(item.id),
          workspace: _state,
          conversation: item,
          enabled: !_state.sending,
          workspaceWidth: _workspaceWidth,
          onChanged: () => unawaited(_history.load()),
          onDelete: () => unawaited(_deleteConversation(item.id)),
        ),
      );

  void _toggleSidebar(bool wide) {
    if (wide) {
      setState(() => _sidebarHidden = !_sidebarHidden);
    } else {
      _scaffoldKey.currentState?.openDrawer();
    }
  }

  Future<void> _openSearch() async {
    if (_searchOpen || !_state.connected) return;
    _closeDrawer();
    _searchOpen = true;
    final controller = _state;
    final revision = controller.sessions.revision;
    final accountScope = controller.accountScope;
    bool current() =>
        mounted &&
        identical(controller, _state) &&
        controller.sessions.revision == revision &&
        controller.accountScope == accountScope;
    try {
      final selected = await genAiShowDialog<GenAiConversationSummary>(
        context: context,
        builder: (dialogContext) => genAiThemeScope(
          dialogContext,
          AnimatedBuilder(
            animation: Listenable.merge([controller, _history]),
            builder: (_, __) => _shellDialog(
              dialogContext,
              current() ? '搜索对话' : '账号已切换',
              current()
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          key: const ValueKey('genai-search-input'),
                          autofocus: true,
                          contextMenuBuilder: genAiTextSelectionContextMenu,
                          controller: _history.searchController,
                          onChanged: _history.searchChanged,
                          textAlignVertical: TextAlignVertical.center,
                          strutStyle: StrutStyle(
                            fontSize: MediaQuery.sizeOf(dialogContext).width <= 600 ? 16 : 13,
                            height: 1.5,
                            forceStrutHeight: true,
                          ),
                          style: TextStyle(
                            fontSize: MediaQuery.sizeOf(dialogContext).width <= 600 ? 16 : 13,
                            height: 1.5,
                          ),
                          // Draft search field: 12px inset, a soft fill and a
                          // 9px outline; hint and entered text share metrics.
                          decoration: InputDecoration(
                            hintText: '搜索历史对话',
                            hintStyle: TextStyle(
                              fontSize: MediaQuery.sizeOf(dialogContext).width <= 600 ? 16 : 13,
                              height: 1.5,
                              color: _palette.muted,
                            ),
                            filled: true,
                            fillColor: _palette.soft,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: BorderSide(color: _palette.line),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: BorderSide(color: _palette.line),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(9),
                              borderSide: BorderSide(color: _palette.accent),
                            ),
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Flexible(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_history.loading)
                                  const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                                  ),
                                if (_history.failure case final failure?)
                                  Text(
                                    genAiFailureText(failure),
                                    style: TextStyle(color: _palette.muted),
                                  ),
                                if (!_history.loading &&
                                    _history.failure == null &&
                                    _history.conversations.isEmpty)
                                  Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Text('没有匹配的对话', style: TextStyle(color: _palette.muted)),
                                  ),
                                for (final item in _history.conversations)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Material(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(8),
                                      child: InkWell(
                                        key: ValueKey('genai-search-result-${item.id}'),
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: _state.sending
                                            ? null
                                            : () {
                                                if (current()) {
                                                  Navigator.pop(dialogContext, item);
                                                }
                                              },
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 12,
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                item.title.isEmpty ? '未命名对话' : item.title,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 13),
                                              ),
                                              // The server returns only the
                                              // question and createTime, so the
                                              // draft preview line uses the
                                              // available time rather than
                                              // fetching every conversation.
                                              if (item.time.isNotEmpty) ...[
                                                const SizedBox(height: 4),
                                                Text(
                                                  genAiHistoryTime(item.time),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: _palette.muted,
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                if (_history.hasMore)
                                  TextButton(
                                    onPressed: _history.loading
                                        ? null
                                        : () => unawaited(_history.load(more: true)),
                                    child: const Text('加载更多'),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : const Text('请在当前账号下重新打开搜索。'),
            ),
          ),
        ),
      );
      if (selected != null && current()) await _openConversation(selected);
    } finally {
      _searchOpen = false;
      if (mounted) {
        _history.searchController.clear();
        _history.searchChanged('');
      }
    }
  }

  Widget _shellDialog(BuildContext dialogContext, String title, Widget body) {
    // Overlay routes occupy the screen, independently of the chat column.
    final compact = MediaQuery.sizeOf(dialogContext).width <= 600;
    return Dialog(
      clipBehavior: Clip.antiAlias,
      insetPadding: compact
          ? const EdgeInsets.all(12)
          : const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 14 : 18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 500,
          maxHeight: MediaQuery.sizeOf(dialogContext).height * .8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: compact
                  ? const EdgeInsets.fromLTRB(16, 10, 8, 10)
                  : const EdgeInsets.fromLTRB(22, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.pop(dialogContext),
                    icon: const GenAiIcon(GenAiGlyph.close, size: 20),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _palette.line),
            Flexible(
              child: Padding(
                padding: EdgeInsets.all(compact ? 18 : 24),
                child: body,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The drawer is a local history entry of this route, so close it first;
  /// otherwise the pop only dismisses the drawer.
  void _exit() {
    _closeDrawer();
    Navigator.of(context).pop();
  }

  /// A new chat drops the current one, so never trigger it mid-reply.
  void _shortcutNewConversation() {
    if (!_state.sending) _newConversation();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Theme(
      data: theme,
      child: LayoutBuilder(
        builder: (context, size) {
          // The shell switches at 960 px of the surface it actually occupies.
          _stageWidth = size.maxWidth;
          final wide = size.maxWidth >= GenAiPalette.wideBreakpoint;
          // A drawer opened at compact stays open in the Scaffold's own state
          // across a resize to the wide layout, where the drawer is no longer
          // built. Keep _drawerOpen set: the scope ignores it while wide (the
          // inline sidebar must stay interactive) and blocks again if the
          // drawer reappears on the way back to compact. ScaffoldState cannot
          // close a drawer it no longer owns, so clearing the flag here would
          // leave a visibly open drawer unblocked after resizing back.
          final sidebar = wide && !_sidebarHidden;
          final drawerOpen = _scaffoldKey.currentState?.isDrawerOpen ?? false;
          return CallbackShortcuts(
            bindings: {
              // Escape belongs to an open drawer before it stops a reply.
              if (_state.sending && !drawerOpen)
                const SingleActivator(LogicalKeyboardKey.escape): _stop,
              SingleActivator(LogicalKeyboardKey.keyN, meta: _apple, control: !_apple):
                  _shortcutNewConversation,
              SingleActivator(LogicalKeyboardKey.keyK, meta: _apple, control: !_apple): () =>
                  unawaited(_openSearch()),
            },
            // System back from inline image creation returns to the chat,
            // as it did when the studio was a pushed page.
            child: PopScope(
              canPop: !_showImages,
              onPopInvokedWithResult: (didPop, _) {
                if (!didPop && _showImages) setState(() => _showImages = false);
              },
              child: Scaffold(
                key: _scaffoldKey,
                backgroundColor: theme.scaffoldBackgroundColor,
                drawerScrimColor: genAiOverlayScrim(drawer: true),
                // The drawer is an overlay owned by this scaffold, not a
                // route, so publish its state to interactive web content.
                // The scope always wraps the same body, so opening or closing
                // the drawer never changes the subtree's shape.
                onDrawerChanged: (open) {
                  if (mounted && open != _drawerOpen) {
                    setState(() => _drawerOpen = open);
                  }
                },
                drawer: wide
                    ? null
                    : Drawer(
                        width: 260,
                        backgroundColor: GenAiPalette.of(context).sidebar,
                        shape: const RoundedRectangleBorder(),
                        child: _sidebar(drawer: true),
                      ),
                body: GenAiWebInputScope(
                  // The inline sidebar at >=960 is not modal, so only the
                  // compact drawer may block.
                  blocked: !wide && _drawerOpen,
                  child: Row(
                    children: [
                      if (sidebar)
                        Semantics(
                          container: true,
                          explicitChildNodes: true,
                          child: _sidebar(drawer: false),
                        ),
                      Expanded(
                        child: SafeArea(
                          left: !sidebar,
                          child: LayoutBuilder(
                            builder: (context, content) {
                              // The chat column's own width drives the composer,
                              // menus and dialogs, so the sidebar cannot make a
                              // desktop window behave like a phone.
                              _workspaceWidth = content.maxWidth;
                              return _main(wide: wide, keyboardOpen: keyboardOpen);
                            },
                          ),
                        ),
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

  String get _networkTitle => '暂时无法连接校园 GenAI';
  String get _networkSubtitle => '请连接校园网或校园 VPN 后重试。';

  bool _isNetworkFailure(GenAiFailure failure) =>
      failure.kind == GenAiFailureKind.campusNetworkRequired;

  List<Widget> _notices({required bool compact}) {
    final notices = <Widget>[];
    final catalog = _state.catalogFailure;
    if (catalog != null) {
      final network = _isNetworkFailure(catalog);
      notices.add(
        _notice(
          network ? _networkTitle : genAiFailureText(catalog),
          subtitle: network ? _networkSubtitle : null,
          compact: compact,
          action: _noticeAction(
            '重试',
            () => unawaited(_state.reloadModels()),
          ),
        ),
      );
    }
    if (_state.uncertainDeletionCount > 0) {
      notices.add(
        _notice(
          '有 ${_state.uncertainDeletionCount} 个对话的删除结果待核实',
          subtitle: '检查后将恢复仍存在的对话，不会重复删除。',
          compact: compact,
          action: _noticeAction(
            _deletionCheck != null ? '正在检查…' : '检查删除结果',
            _deletionCheck != null ? null : () => unawaited(_checkDeletions()),
          ),
        ),
      );
    }
    if (_state.archiveFailure != null) {
      notices.add(
        _notice(
          '服务器尚未确认完整记录',
          subtitle: '请保留此页面并检查同步状态。',
          compact: compact,
          action: _noticeAction('检查同步', () async {
            try {
              await _state.retrySaveConversations();
            } catch (_) {
              // The persistent notice remains until a successful retry.
            }
          }),
        ),
      );
    }
    return notices;
  }

  Widget _main({required bool wide, required bool keyboardOpen}) {
    final workspaceWidth = _workspaceWidth;
    final phone = workspaceWidth <= 680;
    final tiny = workspaceWidth < 360;
    final gutter = tiny
        ? 14.0
        : phone
            ? 18.0
            : 24.0;
    final notices = _notices(compact: phone);
    final noticeArea = notices.isEmpty
        ? null
        : Padding(
            padding: EdgeInsets.fromLTRB(gutter, phone ? 8 : 12, gutter, 0),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: GenAiPalette.readingWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < notices.length; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      notices[i],
                    ],
                  ],
                ),
              ),
            ),
          );
    return Column(
      children: [
        _header(wide: wide, gutter: gutter),
        if (_showImages && _state.connected)
          Expanded(
            child: GenAiToolsPage(
              key: const ValueKey('genai-image-workspace'),
              workspace: _state,
              initialTab: GenAiToolsPage.imagesTab,
              picker: widget.picker,
              embedded: true,
              stageWidth: _stageWidth > 0 ? _stageWidth : null,
            ),
          )
        else
          Expanded(
            child: LayoutBuilder(
              builder: (context, body) {
                if (!_state.connected) return _loginPanel(compact: phone);
                if (_state.turns.isEmpty && !keyboardOpen && body.maxHeight > 420) {
                  // The composer sits under the greeting, slightly above center.
                  return Center(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(bottom: body.maxHeight * .08),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Notices belong to the conversation column, not the
                          // top chrome, so they keep the composer's geometry.
                          if (noticeArea != null)
                            ConstrainedBox(
                              constraints: BoxConstraints(maxHeight: body.maxHeight * .4),
                              child: SingleChildScrollView(child: noticeArea),
                            ),
                          _welcome(body.maxWidth),
                          const SizedBox(height: 20),
                          _composer(gutter: gutter),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    if (noticeArea != null)
                      ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: body.maxHeight * .4),
                        child: SingleChildScrollView(child: noticeArea),
                      ),
                    Expanded(
                      child: _state.turns.isEmpty ? _welcome(body.maxWidth) : _threadArea(gutter),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: body.maxHeight * (keyboardOpen ? .85 : .65),
                      ),
                      child: SingleChildScrollView(
                        reverse: true,
                        child: _composer(gutter: gutter),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
      ],
    );
  }

  String get _title => _showImages
      ? '图片创作'
      : _state.turns.isEmpty
          ? ''
          : _state.title;

  Widget _header({required bool wide, required double gutter}) {
    final palette = _palette;
    final canPop = Navigator.of(context).canPop();
    final title = _title;
    final phone = _workspaceWidth <= 680;
    // Draft header: 66 px on desktop, 60 px and 16 px side padding in the
    // compact shell; phone titles step to 13 px.
    final horizontal = wide ? gutter : 16.0;
    Widget iconButton({
      required String tooltip,
      required Widget icon,
      required VoidCallback onPressed,
      Key? key,
      Color? color,
    }) =>
        IconButton(
          key: key,
          tooltip: tooltip,
          onPressed: onPressed,
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          color: color,
          iconSize: 18,
          icon: icon,
        );
    return SizedBox(
      height: wide ? 66 : 60,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontal),
        child: Row(
          children: [
            // Image creation returns to the same chat and draft. Otherwise a
            // pushed page keeps its platform back affordance on compact
            // screens; the sidebar still holds the way back to TechPie.
            if (_showImages)
              iconButton(
                tooltip: '返回对话',
                onPressed: () => setState(() => _showImages = false),
                icon: const GenAiIcon(GenAiGlyph.back, size: 18),
              )
            // With the wide sidebar hidden, its "返回 TechPie" is hidden too.
            else if (canPop && (!wide || _sidebarHidden))
              iconButton(
                tooltip: '返回',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const GenAiIcon(GenAiGlyph.back, size: 18),
              ),
            iconButton(
              tooltip: wide ? (_sidebarHidden ? '展开侧栏' : '收起侧栏') : '打开导航与历史',
              color: palette.muted,
              onPressed: () => _toggleSidebar(wide),
              icon: const GenAiIcon(GenAiGlyph.sidebar, size: 18),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title.isEmpty && !wide ? 'GenAI' : title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: phone ? 13 : 14,
                    fontWeight: wide ? FontWeight.w500 : FontWeight.w600,
                    color: palette.text,
                  ),
                ),
              ),
            ),
            if (!wide && _state.connected && !_showImages)
              iconButton(
                key: const ValueKey('genai-new-chat-compact'),
                tooltip: '新对话',
                color: palette.muted,
                onPressed: _newConversation,
                icon: const GenAiIcon(GenAiGlyph.edit, size: 18),
              ),
            if (_state.connected && !_showImages && _state.turns.isNotEmpty) _conversationMenu(),
          ],
        ),
      ),
    );
  }

  /// The open conversation's actions; rename, export and delete share the
  /// sidebar row's guarded implementation.
  Widget _conversationMenu() => GenAiConversationMenu(
        key: ValueKey('genai-header-menu-${_state.groupId}'),
        workspace: _state,
        conversation: GenAiConversationSummary(id: _state.groupId, title: _state.title),
        enabled: !_state.sending,
        iconSize: 18,
        showSync: true,
        workspaceWidth: _workspaceWidth,
        onChanged: () => unawaited(_history.load()),
        onDelete: () => unawaited(_deleteConversation(_state.groupId)),
      );

  Widget _accountAvatar(String name, {double radius = 16}) => CircleAvatar(
        radius: radius,
        backgroundColor: _palette.accentSoft,
        foregroundColor: _palette.accent,
        child: name.isNotEmpty && !RegExp(r'^\d+$').hasMatch(name)
            ? Text(
                name.characters.last,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              )
            : const GenAiIcon(GenAiGlyph.user, size: 17),
      );

  Widget _accountMenu() => IconButton(
        tooltip: 'GenAI 账户',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        onPressed: () => unawaited(_openAccount()),
        icon: _accountAvatar(_state.connected ? _state.sessions.session!.profile.username : ''),
      );

  Future<void> _openAccount() async {
    _closeDrawer();
    final controller = _state;
    final revision = controller.sessions.revision;
    final accountScope = controller.accountScope;
    bool current() =>
        mounted &&
        identical(controller, _state) &&
        controller.sessions.revision == revision &&
        controller.accountScope == accountScope;
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => genAiThemeScope(
        dialogContext,
        AnimatedBuilder(
          animation: controller,
          builder: (_, __) {
            final connected = controller.connected;
            final name = connected ? controller.sessions.session!.profile.username : '';
            // Draft menu row: 42px minimum, 8/10 padding, a 17px icon, a 10px
            // gap and a 13px label, clipped to the draft's 7px corners.
            Widget row(Widget icon, String label, VoidCallback? action) {
              final radius = BorderRadius.circular(7);
              return Material(
                color: Colors.transparent,
                borderRadius: radius,
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  borderRadius: radius,
                  onTap: !current() ? null : action,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 42),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          IconTheme.merge(
                            data: IconThemeData(size: 17, color: _palette.muted),
                            child: icon,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(label, style: const TextStyle(fontSize: 13)),
                          ),
                          GenAiIcon(GenAiGlyph.chevron, size: 17, color: _palette.muted),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return _shellDialog(
              dialogContext,
              current() ? '校园账号' : '账号已切换',
              !current()
                  ? const Text('请在当前账号下重新打开账号操作。')
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            _accountAvatar(name, radius: 20),
                            const SizedBox(width: 13),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(connected ? name : '尚未连接'),
                                  const SizedBox(height: 5),
                                  Text(
                                    connected ? '校园 GenAI · 已连接' : '连接后可同步学校对话记录',
                                    style: TextStyle(fontSize: 12, color: _palette.muted),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (connected)
                          row(const GenAiIcon(GenAiGlyph.clock), '用量与额度', () {
                            if (!current()) return;
                            Navigator.pop(dialogContext);
                            unawaited(_openUsage());
                          }),
                        if (widget.onBindCampus != null)
                          row(const GenAiIcon(GenAiGlyph.user), '管理校园账号', () {
                            if (!current()) return;
                            Navigator.pop(dialogContext);
                            widget.onBindCampus?.call();
                          }),
                        if (!connected)
                          row(
                            const GenAiIcon(GenAiGlyph.logout),
                            '连接 GenAI',
                            controller.sessions.owner == null
                                ? null
                                : () {
                                    if (!current()) return;
                                    Navigator.pop(dialogContext);
                                    unawaited(_login());
                                  },
                          ),
                        if (connected)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: TextButton(
                              style: TextButton.styleFrom(
                                foregroundColor: _palette.muted,
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              onPressed: () async {
                                if (!current()) return;
                                final confirmed = await genAiShowDialog<bool>(
                                  context: dialogContext,
                                  builder: (confirmContext) => genAiThemeScope(
                                    confirmContext,
                                    AnimatedBuilder(
                                      animation: controller,
                                      builder: (_, __) => GenAiDialogFrame(
                                        title: Text(current() ? '断开校园 GenAI？' : '账号已切换'),
                                        content: Text(
                                          current()
                                              ? '保留 TechPie 已绑定的 IDS 账号。你可以随时重新连接。'
                                              : '请在当前账号下重新打开账号操作。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(confirmContext, false),
                                            child: const Text('取消'),
                                          ),
                                          FilledButton(
                                            onPressed: !current()
                                                ? null
                                                : () {
                                                    if (current()) {
                                                      Navigator.pop(confirmContext, true);
                                                    }
                                                  },
                                            child: const Text('断开'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                                if (confirmed != true || !current() || !dialogContext.mounted) {
                                  return;
                                }
                                Navigator.pop(dialogContext);
                                await controller.disconnect();
                              },
                              child: const Text('断开 GenAI 连接'),
                            ),
                          ),
                      ],
                    ),
            );
          },
        ),
      ),
    );
  }

  bool get _canResolveCampusIdentity =>
      widget.campusBound && widget.onCampusLogin != null && widget.onSignIn == null;

  Widget _loginPanel({required bool compact}) {
    final palette = _palette;
    final owner = _state.sessions.owner;
    final busy = _openingLogin || _state.connecting;
    final loginFailure = _state.loginFailure;
    final network = loginFailure != null && _isNetworkFailure(loginFailure);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(compact ? 20 : 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: [
              GenAiIcon(GenAiGlyph.lock, size: 34, color: palette.accent),
              const SizedBox(height: 22),
              Text(
                owner == null ? (_canResolveCampusIdentity ? '校园身份待同步' : '先连接校园账号') : '连接你的校园 AI',
                textAlign: TextAlign.center,
                style: _theme.textTheme.headlineSmall?.copyWith(
                  fontSize: 25,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.4,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                owner == null
                    ? (_canResolveCampusIdentity
                        ? 'IDS 账号已绑定。连接 GenAI 后，将通过学校平台核验你的校园身份。'
                        : '登录 TechPie 并绑定校园账号后，即可连接学校的 GenAI 平台。')
                    : '使用 TechPie 已绑定的上海科技大学账号登录。',
                textAlign: TextAlign.center,
                style: TextStyle(color: palette.muted, height: 1.8, fontSize: 14),
              ),
              const SizedBox(height: 26),
              if (owner != null || _canResolveCampusIdentity)
                FilledButton.icon(
                  key: const ValueKey('genai-connect'),
                  onPressed: busy
                      ? null
                      : owner == null
                          ? widget.onCampusLogin
                          : () => unawaited(_login()),
                  icon: busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const GenAiIcon(GenAiGlyph.logout, size: 18),
                  label: Text(
                    busy
                        ? '正在验证身份…'
                        : owner == null
                            ? '使用现有 IDS 会话连接'
                            : '使用校园账号连接',
                  ),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                ),
              if (owner == null && widget.onSignIn != null)
                FilledButton(onPressed: widget.onSignIn, child: const Text('登录 TechPie')),
              if (owner == null && !widget.campusBound && widget.onBindCampus != null)
                TextButton(onPressed: widget.onBindCampus, child: const Text('绑定校园账号')),
              if (loginFailure != null)
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: _notice(
                    network ? _networkTitle : genAiFailureText(loginFailure),
                    subtitle: network ? _networkSubtitle : null,
                    compact: compact,
                    action: _noticeAction(
                      '重试',
                      () => unawaited(_login()),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _welcome(double width) {
    final phone = width <= 680;
    final logo = phone ? 49.0 : 44.0;
    final greeting = phone ? 25.0 : (width * .022).clamp(22.0, 28.0);
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: width < 360
              ? 14
              : phone
                  ? 18
                  : 24,
          vertical: 12,
        ),
        // The draft keeps the greeting and its composer side by side at every
        // width: the wordmark is a row, the composer sits underneath.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              'assets/icon/icon.png',
              width: logo,
              height: logo,
              semanticLabel: 'TechPie',
            ),
            SizedBox(width: phone ? 10 : 14),
            Flexible(
              child: Text(
                _chatCopy.title,
                key: const ValueKey('genai-welcome-title'),
                style: TextStyle(
                  fontSize: greeting,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -.6,
                  color: _palette.text,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _threadArea(double gutter) => Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _scrollRevision++;
                return false;
              },
              child: _thread(gutter),
            ),
          ),
          if (!_followingLatest)
            Positioned(
              bottom: 12,
              left: 0,
              right: 0,
              child: Center(
                child: FilledButton.tonalIcon(
                  key: const ValueKey('genai-scroll-latest'),
                  onPressed: _scrollToEnd,
                  icon: const GenAiIcon(GenAiGlyph.down, size: 16),
                  label: const Text('回到最新'),
                ),
              ),
            ),
        ],
      );

  final _visualCounts = <String, (String, int)>{};

  (String, int)? _latestVisual(List<GenAiConversationTurn> turns) {
    final ids = turns.map((turn) => turn.id).toSet();
    _visualCounts.removeWhere((id, _) => !ids.contains(id));
    for (final turn in turns.reversed) {
      var cached = _visualCounts[turn.id];
      if (cached == null || cached.$1 != turn.answer) {
        cached = (turn.answer, GenAiVisualSyntax.countComplete(turn.answer));
        _visualCounts[turn.id] = cached;
      }
      if (cached.$2 > 0) return (turn.id, cached.$2);
    }
    return null;
  }

  late final _turnActions = GenAiTurnActions(
    copy: (text, message) => unawaited(_copy(text, message)),
    openLink: (link) => unawaited(_openLink(link)),
    changeTurn: (index, action) => unawaited(_changeTurn(index, action)),
    retry: (index) => unawaited(_retryTurn(index)),
    exportConversation: () => unawaited(
      showGenAiConversationExport(
        context,
        _state,
        GenAiConversationSummary(id: _state.groupId, title: _state.title),
        workspaceWidth: _workspaceWidth,
      ),
    ),
    openImages: _openImages,
    showImage: _showImageDialog,
    imageDisplayUri: (url) => _state.repository.imageDisplayUri(url),
    markdownImage: (uri, title, alt) => GenAiMarkdownImage(
      uri: uri,
      title: title,
      alt: alt,
      imageDisplayUri: _state.repository.imageDisplayUri,
    ),
    toggleTts: (index, answer) => unawaited(_media.toggleTts(index, answer)),
    approve: (pending) => _state.resolveAgentApproval(true, expected: pending),
    reject: (pending) => _state.resolveAgentApproval(false, expected: pending),
  );

  Widget _thread(double gutter) {
    // The controller returns a defensive copy. Take it once per frame, rather
    // than copying the entire history for every visible row and key lookup.
    final turns = _state.turns;
    final latestVisual = _latestVisual(turns);
    final width = _workspaceWidth;
    final top = width < 360
        ? 18.0
        : width <= 680
            ? 18.0
            : width < GenAiPalette.wideBreakpoint
                ? 22.0
                : 28.0;
    return ListView.builder(
      key: const ValueKey('genai-thread'),
      controller: _scroll,
      // The latest edge is always zero, even before older variable-height
      // messages are laid out. Never chase an estimated maxScrollExtent.
      reverse: true,
      padding: EdgeInsets.fromLTRB(gutter, top, gutter, 8),
      itemCount: turns.length,
      findChildIndexCallback: (key) {
        if (key is! ValueKey<String>) return null;
        final index = turns.indexWhere((turn) => turn.id == key.value);
        return index < 0 ? null : turns.length - 1 - index;
      },
      itemBuilder: (context, reverseIndex) {
        final index = turns.length - 1 - reverseIndex;
        final turn = turns[index];
        return Align(
          key: ValueKey(turn.id),
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: GenAiPalette.readingWidth),
            child: GenAiTurnView(
              turn: turn,
              actions: _turnActions,
              context: GenAiTurnContext(
                index: index,
                count: turns.length,
                sending: _state.sending,
                connected: _state.connected,
                touch: _touch,
                workspaceWidth: _workspaceWidth,
                pendingApproval: _state.pendingAgentApproval,
                latestVisual: latestVisual,
                supportsPlayback: _media.supportsPlayback,
                playingTtsIndex: _media.playingTtsTurnIndex,
                loadingTts: _media.loadingTts,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _composer({required double gutter}) {
    final scope = _scope;
    final workspaceWidth = _workspaceWidth;
    final desktop = workspaceWidth >= GenAiPalette.wideBreakpoint;
    // Measure the model name naturally. The composer's toolbar, which knows the
    // row it has left after the fixed controls, is the only thing that trims it.
    final modelWidth = GenAiModelPicker.widthFor(
      context,
      _state.selectedModel?.name ?? (_state.loadingModels ? '正在加载模型…' : '选择模型'),
    );
    return GenAiComposer(
      key: _composerKey,
      draft: _draft,
      inputFocus: _inputFocus,
      hint: _chatCopy.hint,
      wide: desktop,
      workspaceWidth: workspaceWidth,
      horizontalPadding: gutter,
      modelSelectorWidth: modelWidth,
      modelSelector: GenAiModelPicker(
        models: _state.models,
        selected: _state.selectedModel,
        loading: _state.loadingModels,
        enabled: !_state.sending,
        maxWidth: modelWidth,
        workspaceWidth: workspaceWidth,
        onSelected: (model) {
          // The picker awaits a menu route; the account or conversation may
          // have moved on in the meantime, so re-check the captured scope.
          if (!_isCurrent(scope) || _state.sending) return;
          _state.selectModel(model);
        },
      ),
      keyboardOpen: MediaQuery.viewInsetsOf(context).bottom > 0,
      sending: _state.sending,
      thinkingEnabled: _state.thinkingEnabled,
      supportsThinking: _state.selectedModel?.supportsThinking ?? false,
      agentAvailable: _state.agentAvailable,
      agentEnabled: _state.agentEnabled,
      recognizingAudio: _state.recognizingAudio,
      attachments: _state.attachments,
      hasPendingUploads: _state.hasPendingUploads,
      hasFailedUploads: _state.hasFailedUploads,
      canSubmit: _state.connected &&
          _state.selectedModel != null &&
          !_state.sending &&
          !_state.hasPendingUploads &&
          !_state.hasFailedUploads,
      supportsRecording: _media.supportsRecording,
      supportsAudio: _media.supportsAudio,
      supportsDocuments: _media.supportsDocuments,
      recording: _media.recording,
      startingRecording: _media.startingRecording,
      recordingSeconds: _media.recordingSeconds,
      onSend: () => unawaited(_send()),
      onStop: _stop,
      contextStatus: _state.turns.isEmpty && _state.contextUsage == null
          ? null
          : GenAiContextStatus(usage: _state.contextUsage),
      onThinkingChanged: _state.setThinking,
      onAgentChanged: _state.setAgentEnabled,
      onMenuAction: (action) {
        if (!_isCurrent(scope) || _state.sending) return;
        switch (action) {
          case 'thinking':
            _state.setThinking(!_state.thinkingEnabled);
          case 'campus':
            _state.setAgentEnabled(!_state.agentEnabled);
          case 'document':
            unawaited(_media.pickDocument());
          case 'image':
            unawaited(_media.pickImage());
          case 'audio':
            if (!_state.recognizingAudio && !_media.recording && !_media.startingRecording) {
              unawaited(_media.pickAudioFile());
            }
        }
      },
      onPickAudio: () => unawaited(_media.pickAudioFile()),
      onStartRecording: () => unawaited(_media.startAudioRecording()),
      onStopRecording: () => unawaited(_media.stopAudioRecording()),
      onCancelRecording: () => unawaited(_media.cancelAudioRecording()),
      onRetryAttachment: (id) => unawaited(_state.retryAttachment(id)),
      onRemoveAttachment: _state.removeAttachment,
      onPreviewAttachment: (attachment) => _showImageDialog(
        bytes: attachment.bytes.isEmpty ? null : Uint8List.fromList(attachment.bytes),
        url: attachment.imageUrl,
      ),
    );
  }

  Widget _notice(
    String title, {
    String? subtitle,
    Widget? action,
    bool compact = false,
  }) {
    final palette = _palette;
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.5,
            color: palette.text,
          ),
        ),
        if (subtitle != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              subtitle,
              style: TextStyle(fontSize: 12, height: 1.6, color: palette.muted),
            ),
          ),
      ],
    );
    final icon = GenAiIcon(GenAiGlyph.info, size: 18, color: palette.accent);
    // The draft wraps the action under the text on phone widths; desktop keeps
    // it inline, vertically centred and right-aligned.
    final content = compact
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  icon,
                  const SizedBox(width: 10),
                  Expanded(child: text),
                ],
              ),
              if (action != null)
                Padding(
                  padding: const EdgeInsets.only(left: 28, top: 10),
                  child: Align(alignment: AlignmentDirectional.centerStart, child: action),
                ),
            ],
          )
        : Row(
            children: [
              icon,
              const SizedBox(width: 14),
              Expanded(child: text),
              if (action != null) ...[
                const SizedBox(width: 14),
                action,
              ],
            ],
          );
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.line),
      ),
      child: content,
    );
  }

  Widget _noticeAction(String label, VoidCallback? onPressed) {
    final palette = _palette;
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: palette.text,
        side: BorderSide(color: palette.line),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        minimumSize: const Size(0, 40),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }

  void _showImageDialog({Uint8List? bytes, String? url}) {
    if (bytes == null && (url == null || url.isEmpty)) return;
    unawaited(
      genAiShowDialog<void>(
        context: context,
        builder: (dialogContext) => genAiThemeScope(
          dialogContext,
          Dialog(
            insetPadding: const EdgeInsets.all(16),
            child: Stack(
              alignment: Alignment.topRight,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      color: Colors.black.withValues(alpha: .85),
                      padding: const EdgeInsets.all(8),
                      child: InteractiveViewer(
                        maxScale: 4.0,
                        child: bytes != null
                            ? Image.memory(bytes, fit: BoxFit.contain)
                            : Image.network(
                                url!,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                    '图片无法加载',
                                    style: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: IconButton.filled(
                    tooltip: '关闭',
                    icon: const GenAiIcon(GenAiGlyph.close, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black54,
                      foregroundColor: Colors.white,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
