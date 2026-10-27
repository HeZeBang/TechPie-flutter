import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/adaptive_feedback.dart';
import '../../../widgets/adaptive_page_navigation.dart';
import '../../../widgets/app_shell/desktop/desktop_sidebar_tokens.dart';
import '../application/genai_chat_service.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'audio/genai_audio_player.dart';
import 'audio/genai_audio_recorder.dart';
import 'audio/genai_workspace_media.dart';
import 'genai_agent_widgets.dart';
import 'genai_chat_copy.dart';
import 'genai_composer.dart';
import 'genai_context_status.dart';
import 'genai_conversation_menu.dart';
import 'genai_copy.dart';
import 'genai_demo_image.dart';
import 'genai_history_controller.dart';
import 'genai_history_sidebar.dart';
import 'genai_image.dart';
import 'genai_theme.dart';
import 'genai_thinking_view.dart';
import 'genai_tools_page.dart';
import 'genai_web_search_view.dart';
import 'markdown/genai_markdown.dart';
import 'picker/genai_picker.dart';

typedef GenAiLoginAction = Future<GenAiCredential?> Function(
  BuildContext context,
);

class GenAiWorkspace extends StatefulWidget {
  const GenAiWorkspace({
    super.key,
    required this.controller,
    required this.login,
    this.demo = false,
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
  final bool demo;
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
  final _scroll = ScrollController();
  bool _followingLatest = true;
  bool _showImages = false;
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

  late ThemeData _theme;
  Color get _accent => _theme.colorScheme.primary;
  Color get _muted => _theme.colorScheme.onSurfaceVariant;
  bool get _canSend =>
      _state.connected &&
      _state.selectedModel != null &&
      !_state.sending &&
      !_state.hasPendingUploads &&
      !_state.hasFailedUploads &&
      (_draft.text.trim().isNotEmpty || _state.attachments.isNotEmpty);

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
    final following = _scroll.position.extentAfter < 120;
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
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _stop() {
    if (!_state.sending) return;
    _state.stop();
    _inputFocus.requestFocus();
    showAdaptiveFeedback(
      context: context,
      message: '已停止',
    );
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

  Future<void> _openConversation(GenAiConversationSummary item) async {
    if (_state.sending) return;
    if (item.id == _state.groupId) {
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
      _draft.clear();
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: controller,
        builder: (_, __) => AlertDialog(
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
    );
    if (confirmed != true || !current()) return;
    final cancellation = GenAiCancellation();
    try {
      await controller.deleteConversation(id, cancellation);
      if (mounted && current()) {
        _history.remove(id);
      }
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

  Future<void> _openTools(int tab) async {
    if (!_state.connected || _state.sending) return;
    final controller = _state;
    final accountScope = controller.accountScope;
    final revision = controller.sessions.revision;
    if (tab == 1 && MediaQuery.sizeOf(context).width >= 960) {
      _inputFocus.unfocus();
      setState(() => _showImages = true);
      return;
    }
    final opened = await pushAdaptivePage<bool>(
      context,
      builder: (_) => GenAiToolsPage(
        workspace: controller,
        initialTab: tab,
        demo: widget.demo,
        picker: widget.picker,
      ),
    );
    if (mounted &&
        identical(controller, _state) &&
        controller.accountScope == accountScope &&
        controller.sessions.revision == revision) {
      if (opened == true) _draft.clear();
      unawaited(_history.load());
    }
  }

  void _newConversation() {
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
    _draft.clear();
    _inputFocus.requestFocus();
    final sending = _state.send(text);
    _scrollToEnd();
    await sending;
    if (mounted) unawaited(_history.load());
  }

  Future<void> _retryTurn(int index) async {
    if (_state.sending || !_state.connected || _state.selectedModel == null) {
      return;
    }
    final sending = _state.retryTurn(index);
    _scrollToEnd();
    await sending;
    if (mounted) unawaited(_history.load());
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

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canvas = theme.scaffoldBackgroundColor;
    return CallbackShortcuts(
      bindings: {
        if (_state.sending) const SingleActivator(LogicalKeyboardKey.escape): _stop,
      },
      child: Theme(
        data: theme,
        child: Scaffold(
          backgroundColor: canvas,
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, size) {
                final wide = size.maxWidth >= 960;
                final viewport = MediaQuery.sizeOf(context);
                final landscape = !wide && size.maxWidth >= 560 && viewport.width > viewport.height;
                final modelInComposer = wide || landscape;
                return Row(
                  children: [
                    if (wide)
                      GenAiHistorySidebar(
                        history: _history,
                        connected: _state.connected,
                        sending: _state.sending,
                        activeId: _showImages ? '' : _state.groupId,
                        actions: _chatActions(labels: true),
                        accountMenu: _accountMenu(),
                        onOpen: (item) => unawaited(_openConversation(item)),
                        menuBuilder: (item) => GenAiConversationMenu(
                          key: ValueKey(item.id),
                          workspace: _state,
                          conversation: item,
                          enabled: !_state.sending,
                          onChanged: () => unawaited(_history.load()),
                          onDelete: () => unawaited(_deleteConversation(item.id)),
                        ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (!_showImages || wide) _header(wide, landscape: landscape),
                          if (_showImages && _state.connected)
                            Expanded(
                              child: GenAiToolsPage(
                                key: const ValueKey('genai-image-workspace'),
                                workspace: _state,
                                initialTab: 1,
                                demo: widget.demo,
                                picker: widget.picker,
                                embedded: true,
                                onBack: wide ? null : () => setState(() => _showImages = false),
                              ),
                            )
                          else ...[
                            if (_state.connected && !modelInComposer) _modelBar(),
                            if (_state.catalogFailure != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: _notice(
                                  genAiFailureText(_state.catalogFailure!),
                                  action: TextButton(
                                    onPressed: () => unawaited(_state.reloadModels()),
                                    child: const Text('重新加载'),
                                  ),
                                ),
                              ),
                            if (_state.uncertainDeletionCount > 0)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 6,
                                ),
                                child: _notice(
                                  '有 ${_state.uncertainDeletionCount} 个对话的删除结果待核实。检查后将恢复仍存在的对话，不会重复删除。',
                                  action: TextButton(
                                    onPressed: _deletionCheck != null
                                        ? null
                                        : () => unawaited(_checkDeletions()),
                                    child: Text(
                                      _deletionCheck != null ? '正在检查…' : '检查删除结果',
                                    ),
                                  ),
                                ),
                              ),
                            if (_state.archiveFailure != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20),
                                child: _notice(
                                  '服务器尚未确认完整记录。请保留此页面并检查同步状态。',
                                  action: TextButton(
                                    onPressed: () async {
                                      try {
                                        await _state.retrySaveConversations();
                                      } catch (_) {
                                        // The persistent notice remains until a successful retry.
                                      }
                                    },
                                    child: const Text('检查同步'),
                                  ),
                                ),
                              ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, bodySize) {
                                  if (_state.connected &&
                                      _state.turns.isEmpty &&
                                      !keyboardOpen &&
                                      bodySize.maxHeight > 420) {
                                    return Center(
                                      child: SingleChildScrollView(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _welcome(size.maxWidth, horizontal: landscape),
                                            _composer(wide, modelInComposer: modelInComposer),
                                          ],
                                        ),
                                      ),
                                    );
                                  }
                                  return Column(
                                    children: [
                                      Expanded(
                                        child: !_state.connected
                                            ? _loginPanel()
                                            : _state.turns.isEmpty
                                                ? _welcome(size.maxWidth, horizontal: landscape)
                                                : _threadArea(),
                                      ),
                                      if (_state.connected)
                                        ConstrainedBox(
                                          constraints: BoxConstraints(
                                            maxHeight:
                                                bodySize.maxHeight * (keyboardOpen ? .85 : .65),
                                          ),
                                          child: SingleChildScrollView(
                                            reverse: true,
                                            child:
                                                _composer(wide, modelInComposer: modelInComposer),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _chatActions({bool labels = false}) {
    final actions = [
      if (labels) (Icons.edit_square, '新对话', _newConversation as VoidCallback?),
      if (!labels)
        (
          Icons.forum_outlined,
          '会话记录',
          _state.connected && !_state.sending ? () => unawaited(_openTools(0)) : null
        ),
      (
        Icons.image_outlined,
        '图片创作',
        _state.connected && !_state.sending ? () => unawaited(_openTools(1)) : null
      ),
    ];
    Widget button((IconData, String, VoidCallback?) action) => labels
        ? TextButton(
            key: action.$1 == Icons.edit_square ? const ValueKey('genai-new-chat-wide') : null,
            onPressed: action.$3,
            style: TextButton.styleFrom(
              alignment: Alignment.centerLeft,
              minimumSize: const Size.fromHeight(DesktopSidebarTokens.navItemHeight),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesktopSidebarTokens.navItemRadius),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              backgroundColor: action.$1 == Icons.image_outlined && _showImages
                  ? _theme.colorScheme.secondaryContainer
                  : null,
              foregroundColor: action.$1 == Icons.image_outlined && _showImages
                  ? _theme.colorScheme.onSecondaryContainer
                  : _theme.colorScheme.onSurfaceVariant,
            ),
            child: Row(
              children: [
                Icon(action.$1, size: DesktopSidebarTokens.navItemIconSize),
                const SizedBox(width: DesktopSidebarTokens.navItemTextGap),
                Flexible(child: Text(action.$2, style: _theme.textTheme.labelLarge)),
              ],
            ),
          )
        : IconButton(
            tooltip: action.$2,
            onPressed: action.$3,
            icon: Icon(action.$1, size: 21),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          );
    return labels
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [for (final action in actions) button(action)],
          )
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final action in actions) button(action)],
          );
  }

  Widget _header(bool wide, {required bool landscape}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12, vertical: 10),
      child: Row(
        children: [
          if (_showImages || Navigator.of(context).canPop())
            IconButton(
              onPressed: _showImages
                  ? () => setState(() => _showImages = false)
                  : () => Navigator.of(context).pop(),
              tooltip: _showImages ? '返回对话' : '返回',
              icon: const BackButtonIcon(),
            ),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: wide
                  ? const SizedBox.shrink()
                  : Text(
                      _showImages
                          ? '图片创作'
                          : _state.turns.isEmpty
                              ? 'GenAI'
                              : _state.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          if (widget.demo) _demoNotice(),
          if (landscape && _state.connected && !_showImages) _newChatButton(),
          if (!wide) _chatActions(),
          if (!wide) _accountMenu(),
        ],
      ),
    );
  }

  Widget _accountMenu() {
    final scope = _scope;
    return PopupMenuButton<String>(
      tooltip: 'GenAI 账户',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
      icon: Icon(Icons.account_circle_outlined, color: _muted),
      onSelected: (value) {
        if (!_isCurrent(scope)) return;
        switch (value) {
          case 'usage':
            unawaited(_openTools(2));
          case 'campus':
            widget.onBindCampus?.call();
          case 'ids':
            widget.onCampusLogin?.call();
          case 'disconnect':
            unawaited(_state.disconnect());
          case 'connect':
            unawaited(_login());
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            _state.connected ? _state.sessions.session!.profile.username : '尚未连接',
          ),
        ),
        if (_state.connected)
          const PopupMenuItem(
            value: 'usage',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.bar_chart),
              title: Text('用量统计'),
            ),
          ),
        if (widget.onBindCampus != null)
          const PopupMenuItem(value: 'campus', child: Text('管理校园账号')),
        if (widget.demo && widget.onCampusLogin != null)
          const PopupMenuItem(
            value: 'ids',
            child: Text('使用 TechPie IDS 登录'),
          ),
        if (_state.connected)
          const PopupMenuItem(
            value: 'disconnect',
            child: Text('断开 GenAI'),
          )
        else
          PopupMenuItem(
            value: 'connect',
            enabled: _state.sessions.owner != null,
            child: const Text('连接 GenAI'),
          ),
      ],
    );
  }

  Widget _demoNotice() => Tooltip(
        message: '本地演示 · 不访问校园服务，不产生费用',
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: _theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('演示', style: TextStyle(fontSize: 11, color: _muted)),
        ),
      );

  Widget _modelSelector() => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 250),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<GenAiModel>(
            key: const ValueKey('genai-model'),
            borderRadius: BorderRadius.circular(12),
            isExpanded: true,
            value: _state.selectedModel,
            hint: Text(_state.loadingModels ? '正在加载模型…' : '选择模型'),
            icon: Icon(Icons.keyboard_arrow_down_rounded, color: _muted, size: 18),
            items: _state.models
                .where((model) => !model.isImage)
                .map(
                  (model) => DropdownMenuItem(
                    value: model,
                    child: Text(
                      '${model.name}${model.payType == 'FREE' ? '' : model.payType == 'PAID' ? ' · 付费' : ' · 费用未知'}',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _state.sending
                ? null
                : (model) {
                    if (model != null) _state.selectModel(model);
                  },
          ),
        ),
      );

  Widget _modelBar() => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(child: _modelSelector()),
            const SizedBox(width: 8),
            _newChatButton(),
          ],
        ),
      );

  Widget _newChatButton() => TextButton.icon(
        key: const ValueKey('genai-new-chat-compact'),
        onPressed: _newConversation,
        icon: const Icon(Icons.edit_square, size: 18),
        label: const Text('新对话'),
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          foregroundColor: _theme.colorScheme.onSurface,
        ),
      );

  bool get _canResolveCampusIdentity =>
      widget.campusBound && widget.onCampusLogin != null && widget.onSignIn == null;

  Widget _loginPanel() => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.lock_open_rounded,
                    size: 38,
                    color: _accent,
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  _state.sessions.owner == null
                      ? (_canResolveCampusIdentity ? '校园身份待同步' : '先连接校园账号')
                      : '连接你的校园 AI',
                  textAlign: TextAlign.center,
                  style: _theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Text(
                  _state.sessions.owner == null
                      ? (_canResolveCampusIdentity
                          ? 'IDS 账号已绑定。连接 GenAI 后，将通过学校平台核验你的校园身份。'
                          : '登录 TechPie 并绑定校园账号后，即可连接学校的 GenAI 平台。')
                      : '使用上海科技大学账号登录。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, height: 1.9, fontSize: 14),
                ),
                const SizedBox(height: 28),
                if (_state.sessions.owner != null || _canResolveCampusIdentity)
                  FilledButton.icon(
                    key: const ValueKey('genai-connect'),
                    onPressed: _openingLogin || _state.connecting
                        ? null
                        : _state.sessions.owner == null
                            ? widget.onCampusLogin
                            : () => unawaited(_login()),
                    icon: _openingLogin || _state.connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login_rounded, size: 18),
                    label: Text(
                      _openingLogin || _state.connecting
                          ? '正在验证身份…'
                          : _state.sessions.owner == null
                              ? '使用现有 IDS 会话连接'
                              : widget.demo
                                  ? '连接本地演示'
                                  : '使用校园账号连接',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: _theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 26,
                        vertical: 18,
                      ),
                    ),
                  ),
                if (_state.sessions.owner == null && widget.onSignIn != null)
                  FilledButton(
                    onPressed: widget.onSignIn,
                    child: const Text('登录 TechPie'),
                  ),
                if (_state.sessions.owner == null &&
                    !widget.campusBound &&
                    widget.onBindCampus != null)
                  TextButton(
                    onPressed: widget.onBindCampus,
                    child: const Text('绑定校园账号'),
                  ),
                if (_state.loginFailure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _notice(genAiFailureText(_state.loginFailure!)),
                  ),
              ],
            ),
          ),
        ),
      );

  Widget _welcome(double width, {required bool horizontal}) {
    final logo = Image.asset(
      'assets/icon/icon.png',
      width: horizontal ? 64 : 96,
      height: horizontal ? 64 : 96,
      semanticLabel: 'TechPie',
    );
    final title = Text(
      _chatCopy.title,
      key: const ValueKey('genai-welcome-title'),
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: width < 500 ? 25 : 30,
        fontWeight: FontWeight.w500,
        letterSpacing: -.6,
      ),
    );
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: horizontal ? 12 : 24),
        child: horizontal
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [logo, const SizedBox(width: 12), Flexible(child: title)],
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [logo, const SizedBox(height: 12), title],
              ),
      ),
    );
  }

  Widget _threadArea() => Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollStartNotification>(
              onNotification: (notification) {
                if (notification.depth == 0) _scrollRevision++;
                return false;
              },
              child: _thread(),
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
                  icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                  label: const Text('回到最新'),
                ),
              ),
            ),
        ],
      );

  Widget _thread() => ListView.builder(
        key: const ValueKey('genai-thread'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 12),
        itemCount: _state.turns.length,
        itemBuilder: (context, index) {
          final turn = _state.turns[index];
          if (turn.isHistoryGap) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                '部分历史记录无法读取，上下文已在此处断开。',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 12),
              ),
            );
          }
          final incomplete = const [
            GenAiChatPhase.cancelled,
            GenAiChatPhase.interrupted,
            GenAiChatPhase.failed,
            GenAiChatPhase.needsLogin,
          ].contains(turn.phase);
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 800),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            constraints: const BoxConstraints(maxWidth: 680),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 13,
                            ),
                            margin: const EdgeInsets.only(left: 36, bottom: 4),
                            decoration: BoxDecoration(
                              color: _theme.colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (turn.attachedImageBytesList.isNotEmpty ||
                                    turn.attachedImageBytes != null ||
                                    turn.attachedImageUrl != null ||
                                    turn.attachedImageUrls.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      alignment: WrapAlignment.end,
                                      children: [
                                        if (turn.attachedImageBytesList.isNotEmpty)
                                          for (final bytes in turn.attachedImageBytesList)
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: GestureDetector(
                                                onTap: () => _showImageDialog(
                                                  bytes: bytes,
                                                ),
                                                child: Image.memory(
                                                  bytes,
                                                  height: 180,
                                                  fit: BoxFit.contain,
                                                  errorBuilder: (
                                                    _,
                                                    __,
                                                    ___,
                                                  ) =>
                                                      _buildImageErrorPlaceholder(),
                                                ),
                                              ),
                                            )
                                        else if (turn.attachedImageBytes != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: GestureDetector(
                                              onTap: () => _showImageDialog(
                                                bytes: turn.attachedImageBytes,
                                              ),
                                              child: Image.memory(
                                                turn.attachedImageBytes!,
                                                height: 180,
                                                fit: BoxFit.contain,
                                                errorBuilder: (_, __, ___) =>
                                                    _buildImageErrorPlaceholder(),
                                              ),
                                            ),
                                          )
                                        else if (turn.attachedImageUrls.isNotEmpty)
                                          for (final url in turn.attachedImageUrls.map(
                                            (url) =>
                                                _state.repository.imageDisplayUri(url).toString(),
                                          ))
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(8),
                                              child: GestureDetector(
                                                onTap: () => _showImageDialog(
                                                  url: url,
                                                ),
                                                child: _remoteAttachmentImage(
                                                  url,
                                                  height: 180,
                                                ),
                                              ),
                                            )
                                        else if (turn.attachedImageUrl != null)
                                          ClipRRect(
                                            borderRadius: BorderRadius.circular(8),
                                            child: GestureDetector(
                                              onTap: () => _showImageDialog(
                                                url: _state.repository
                                                    .imageDisplayUri(
                                                      turn.attachedImageUrl!,
                                                    )
                                                    .toString(),
                                              ),
                                              child: _remoteAttachmentImage(
                                                _state.repository
                                                    .imageDisplayUri(
                                                      turn.attachedImageUrl!,
                                                    )
                                                    .toString(),
                                                height: 180,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                if (turn.attachedFileNames.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Wrap(
                                      spacing: 6,
                                      runSpacing: 4,
                                      children: [
                                        for (final fileName in turn.attachedFileNames)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _accent.withValues(
                                                alpha: .15,
                                              ),
                                              borderRadius: BorderRadius.circular(6),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons.description,
                                                  size: 12,
                                                  color: _accent,
                                                ),
                                                const SizedBox(width: 4),
                                                Text(
                                                  fileName,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: _accent,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                SelectableText(
                                  turn.prompt,
                                  style: const TextStyle(
                                    fontSize: 15.5,
                                    height: 1.7,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16, right: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  key: ValueKey('genai-user-copy-$index'),
                                  tooltip: '复制内容',
                                  icon: Icon(
                                    Icons.copy_outlined,
                                    size: 14,
                                    color: _muted,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                    minWidth: 26,
                                    minHeight: 26,
                                  ),
                                  onPressed: () => unawaited(
                                    _copy(turn.prompt, '已复制内容'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Semantics(
                        container: true,
                        label: turn.isAgent ? '校园工具回复' : 'AI 回复',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (turn.isAgent) ...[
                              if (turn.agentEvents.isNotEmpty ||
                                  turn.agentActivity.isNotEmpty ||
                                  turn.reasoning.isNotEmpty ||
                                  turn.citations.isNotEmpty)
                                GenAiAgentToolActivity(
                                  key: ObjectKey(turn),
                                  events: turn.agentEvents.values.toList(),
                                  activity: turn.agentActivity,
                                  thinking: turn.isAgentThinking,
                                  legacyReasoning: turn.reasoning,
                                  legacyCitations: turn.citations,
                                  onOpenLink: (url) => unawaited(_openLink(url)),
                                  running: _state.sending && index == _state.turns.length - 1,
                                  stopped: incomplete,
                                  demo: widget.demo,
                                  imageDisplayUri: _state.repository.imageDisplayUri,
                                  onOpenImages:
                                      _state.sending ? null : () => unawaited(_openTools(1)),
                                ),
                              if (_state.pendingAgentApproval != null &&
                                  index == _state.turns.length - 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Builder(
                                    builder: (context) {
                                      final pending = _state.pendingAgentApproval!;
                                      return GenAiAgentApprovalCard(
                                        call: pending.call,
                                        prepared: pending.prepared,
                                        onApprove: () =>
                                            _state.resolveAgentApproval(true, expected: pending),
                                        onReject: () =>
                                            _state.resolveAgentApproval(false, expected: pending),
                                      );
                                    },
                                  ),
                                ),
                              if (turn.agentEvents.isNotEmpty) const SizedBox(height: 12),
                            ],
                            if (!turn.isAgent && turn.citations.isNotEmpty)
                              GenAiWebSearchView(
                                citations: turn.citations,
                                onOpenLink: (url) => unawaited(_openLink(url)),
                              ),
                            if (!turn.isAgent &&
                                (turn.reasoning.isNotEmpty ||
                                    turn.phase == GenAiChatPhase.streaming && turn.answer.isEmpty))
                              GenAiThinkingView(
                                reasoning: turn.reasoning,
                                isThinking:
                                    turn.phase == GenAiChatPhase.streaming && turn.answer.isEmpty,
                                durationMs: turn.thinkingDurationMs,
                                onTapLink: (href) => unawaited(_openLink(href)),
                              ),
                            if (turn.answer.isEmpty &&
                                !incomplete &&
                                turn.reasoning.isEmpty &&
                                (!turn.isAgent || _state.pendingAgentApproval == null))
                              Row(
                                children: [
                                  SizedBox(
                                    width: 13,
                                    height: 13,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: _accent,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    turn.isAgent ? turn.agentStatus : '正在思考…',
                                    style: TextStyle(color: _muted, fontSize: 12),
                                  ),
                                ],
                              ),
                            if (turn.contextCompacted)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  '已整理较早的上下文 · 完整记录已保留',
                                  style: TextStyle(color: _muted, fontSize: 11),
                                ),
                              ),
                            if (turn.answer.isNotEmpty)
                              GenAiMarkdown(
                                data: turn.answer,
                                selectable: true,
                                imageBuilder: (uri, title, alt) => GenAiMarkdownImage(
                                  uri: uri,
                                  title: title,
                                  alt: alt,
                                  demo: widget.demo,
                                  imageDisplayUri: _state.repository.imageDisplayUri,
                                ),
                                onTapLink: (_, href, __) => unawaited(_openLink(href)),
                              ),
                            if (incomplete)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  turn.isAgent && turn.agentStatus.isNotEmpty
                                      ? turn.agentStatus
                                      : turn.failure != null
                                          ? genAiFailureText(turn.failure!)
                                          : '已停止',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                    height: 1.7,
                                  ),
                                ),
                              ),
                            if (turn.finishReason == GenAiFinishReason.length)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '已达到本次回复的长度限制',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            if (turn.finishReason == GenAiFinishReason.contentFilter)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: Text(
                                  '平台已结束本次回复',
                                  style: TextStyle(
                                    color: _muted,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                if (turn.answer.isNotEmpty) ...[
                                  IconButton(
                                    tooltip: '复制回复',
                                    key: ValueKey('genai-copy-$index'),
                                    icon: Icon(
                                      Icons.copy_outlined,
                                      size: 16,
                                      color: _muted,
                                    ),
                                    onPressed: () => unawaited(_copy(turn.answer)),
                                  ),
                                  if (_media.supportsPlayback)
                                    IconButton(
                                      tooltip:
                                          _media.playingTtsTurnIndex == index ? '停止播放' : '语音播报',
                                      key: ValueKey('genai-tts-$index'),
                                      icon: _media.loadingTts && _media.playingTtsTurnIndex == index
                                          ? SizedBox(
                                              width: 14,
                                              height: 14,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 1.5,
                                                color: _accent,
                                              ),
                                            )
                                          : Icon(
                                              _media.playingTtsTurnIndex == index
                                                  ? Icons.stop_circle_outlined
                                                  : Icons.volume_up_outlined,
                                              size: 16,
                                              color: _media.playingTtsTurnIndex == index
                                                  ? _accent
                                                  : _muted,
                                            ),
                                      onPressed: () => unawaited(
                                        _media.toggleTts(index, turn.answer),
                                      ),
                                    ),
                                ],
                                if (incomplete &&
                                    index == _state.turns.length - 1 &&
                                    !turn.isHistoryGap &&
                                    _state.connected)
                                  TextButton.icon(
                                    key: ValueKey('genai-retry-$index'),
                                    onPressed:
                                        _state.sending ? null : () => unawaited(_retryTurn(index)),
                                    icon: const Icon(Icons.refresh, size: 15),
                                    label: const Text(
                                      '重试',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _composer(bool wide, {required bool modelInComposer}) {
    final scope = _scope;
    return GenAiComposer(
      key: _composerKey,
      draft: _draft,
      inputFocus: _inputFocus,
      hint: _chatCopy.hint,
      wide: wide,
      modelSelector: modelInComposer ? _modelSelector() : null,
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

  Widget _notice(String text, {Widget? action}) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _theme.colorScheme.errorContainer.withValues(alpha: .3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 17,
              color: _theme.colorScheme.error,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontSize: 12, height: 1.7),
              ),
            ),
            if (action != null) action,
          ],
        ),
      );

  Widget _buildImageErrorPlaceholder() => Container(
        padding: const EdgeInsets.all(8),
        color: Colors.black12,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.broken_image_outlined, size: 16),
            SizedBox(width: 4),
            Text(
              '图片无法加载',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      );

  Widget _remoteAttachmentImage(String url, {double? height}) {
    // Saved fixture URLs are synthetic; never fetch them from the campus CDN.
    if (widget.demo) {
      return SizedBox(
        height: height ?? 180,
        width: 180,
        child: const GenAiDemoImage(),
      );
    }
    return Image.network(
      url,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => _buildImageErrorPlaceholder(),
    );
  }

  void _showImageDialog({Uint8List? bytes, String? url}) {
    if (bytes == null && (url == null || url.isEmpty)) return;
    unawaited(
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: Colors.transparent,
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
                          : _remoteAttachmentImage(url!),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 10,
                right: 10,
                child: IconButton.filled(
                  icon: const Icon(Icons.close, size: 20),
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
    );
  }
}
