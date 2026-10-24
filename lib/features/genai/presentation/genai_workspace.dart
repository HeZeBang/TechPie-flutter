import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/genai_chat_service.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'audio/genai_audio_player.dart';
import 'audio/genai_audio_recorder.dart';
import 'genai_agent_widgets.dart';
import 'genai_chat_copy.dart';
import 'genai_conversation_menu.dart';
import 'genai_copy.dart';
import 'genai_demo_image.dart';
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
    this.ephemeral = false,
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
  final bool ephemeral;
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
  final _scroll = ScrollController();
  final _conversations = <GenAiConversationSummary>[];
  final _sidebarSearch = TextEditingController();
  Timer? _sidebarSearchTimer;
  String _sidebarQuery = '';
  int _chatCopyIndex =
      DateTime.now().millisecondsSinceEpoch % genAiChatCopy.length;
  late String _copyGroupId;
  int _copyChangeRevision = 0;
  ({String hint, String title, String subtitle}) get _chatCopy =>
      genAiChatCopy[_chatCopyIndex];
  late final GenAiPicker _picker;
  late final GenAiAudioPlayer _audioPlayer;
  late final GenAiAudioRecorder _audioRecorder;
  bool _recordingAudio = false;
  bool _startingAudio = false;
  int _ttsOperation = 0;
  late _WorkspaceScope _mediaScope;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  int? _playingTtsTurnIndex;
  bool _loadingTts = false;
  Timer? _refresh;
  bool _openingLogin = false;
  bool _loadingHistory = false;
  bool _historyRequested = false;
  GenAiFailure? _historyFailure;
  GenAiCancellation? _deletionCheck;
  late int _historySessionRevision;
  late String _historyGroupId;
  late bool _historyWasSending;
  bool _hasMoreHistory = false;
  int _historyPage = 1;
  GenAiCancellation? _historyCancellation;
  GenAiOwner? _draftOwner;
  Object? _historyAccountScope;
  GenAiWorkspaceController get _state => widget.controller;
  _WorkspaceScope get _scope =>
      (_state, _state.sessions.revision, _state.conversationRevision);
  bool _isCurrent(_WorkspaceScope scope) => mounted && scope == _scope;

  void _resetMedia() {
    _ttsOperation++;
    _playingTtsTurnIndex = null;
    _loadingTts = false;
    _recordingAudio = false;
    _recordingTimer?.cancel();
    unawaited(_audioRecorder.cancel());
    unawaited(_audioPlayer.stop());
  }

  late ThemeData _theme;
  Color get _accent => _theme.colorScheme.primary;
  Color get _muted => _theme.colorScheme.onSurfaceVariant;
  Color get _border => _theme.colorScheme.outlineVariant;
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
    _picker = widget.picker ?? GenAiPicker();
    _audioPlayer = widget.audioPlayer ?? GenAiAudioPlayer();
    _audioRecorder = widget.audioRecorder ?? GenAiAudioRecorder();
    _draftOwner = _state.sessions.owner;
    _historyAccountScope = _state.accountScope;
    _historySessionRevision = _state.sessions.revision;
    _historyGroupId = _state.groupId;
    _historyWasSending = _state.sending;
    _mediaScope = _scope;
    _copyGroupId = _state.groupId;
    _state.addListener(_changed);
    _draft.addListener(_draftChanged);
    _inputFocus.addListener(_draftChanged);
    _audioPlayer.onFinished = () {
      if (mounted) setState(() => _playingTtsTurnIndex = null);
    };
    unawaited(_state.restore());
    if (_state.connected) {
      unawaited(_loadHistory());
    }
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
    _resetMedia();
    _mediaScope = _scope;
    _resetHistory();
    _draftOwner = _state.sessions.owner;
    _historyAccountScope = _state.accountScope;
    _historySessionRevision = _state.sessions.revision;
    _historyGroupId = _state.groupId;
    _historyWasSending = _state.sending;
    _copyGroupId = _state.groupId;
    _copyChangeRevision++;
    if (_state.turns.isEmpty) {
      _chatCopyIndex = (_chatCopyIndex + 1) % genAiChatCopy.length;
    }
    _draft.clear();
    _state.addListener(_changed);
    unawaited(_state.restore());
    if (_state.connected) unawaited(_loadHistory());
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    if (_copyGroupId != _state.groupId) {
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
    if (_mediaScope != _scope) {
      _mediaScope = _scope;
      _resetMedia();
    }
    if (_draftOwner != _state.sessions.owner ||
        _historyAccountScope != _state.accountScope ||
        _historySessionRevision != _state.sessions.revision) {
      _historyAccountScope = _state.accountScope;
      _historySessionRevision = _state.sessions.revision;
      _draftOwner = _state.sessions.owner;
      _draft.clear();
      _resetHistory();
    }
    final historyChanged = _historyGroupId != _state.groupId ||
        (_historyWasSending && !_state.sending);
    _historyGroupId = _state.groupId;
    _historyWasSending = _state.sending;
    if (_state.connected &&
        (!_historyRequested ||
            (historyChanged && !(_sidebarSearchTimer?.isActive ?? false)))) {
      unawaited(_loadHistory());
    }
    if (!_state.sending) {
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

  void _paint() {
    final nearEnd = !_scroll.hasClients || _scroll.position.extentAfter < 120;
    setState(() {});
    if (nearEnd) _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法完成 GenAI 登录，请重试')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingLogin = false);
    }
  }

  void _resetHistory() {
    _deletionCheck?.cancel();
    _deletionCheck = null;
    _historyCancellation?.cancel();
    _historyCancellation = null;
    _sidebarSearchTimer?.cancel();
    _sidebarSearch.clear();
    _sidebarQuery = '';
    _conversations.clear();
    _historyPage = 1;
    _hasMoreHistory = false;
    _loadingHistory = false;
    _historyRequested = false;
    _historyFailure = null;
  }

  Future<void> _loadHistory({bool more = false, String? query}) async {
    if (!_state.connected || (more && _loadingHistory)) return;
    _historyCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _historyCancellation = cancellation;
    final page = more ? _historyPage + 1 : 1;
    final targetQuery = query ?? _sidebarQuery;
    setState(() {
      _historyRequested = true;
      _loadingHistory = true;
      _historyFailure = null;
      if (!more) {
        if (_sidebarQuery != targetQuery) _conversations.clear();
        _sidebarQuery = targetQuery;
      }
    });
    try {
      final result = await _state.listConversations(
        cancellation,
        page: page,
        query: targetQuery,
      );
      if (!mounted || cancellation.isCancelled) return;
      setState(() {
        if (!more) _conversations.clear();
        for (final record in result.records) {
          _conversations.removeWhere((item) => item.id == record.id);
          _conversations.add(record);
        }
        _hasMoreHistory = result.hasMore;
        _historyPage = page;
      });
    } catch (error) {
      if (mounted && !cancellation.isCancelled) {
        setState(
          () => _historyFailure = error is GenAiFailure
              ? error
              : const GenAiFailure(GenAiFailureKind.transport),
        );
      }
    } finally {
      if (identical(_historyCancellation, cancellation)) {
        _historyCancellation = null;
        if (mounted) setState(() => _loadingHistory = false);
      }
    }
  }

  void _onSidebarSearchChanged(String text) {
    _sidebarSearchTimer?.cancel();
    _historyCancellation?.cancel();
    _historyCancellation = null;
    _loadingHistory = false;
    // Notifications from streaming must not start a competing history load.
    _historyRequested = true;
    _sidebarSearchTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_loadHistory(query: text.trim()));
    });
    setState(() {});
  }

  Future<void> _openConversation(GenAiConversationSummary item) async {
    if (_state.sending || item.id == _state.groupId) return;
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
      _draft.clear();
      _scrollToEnd();
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载对话失败')),
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
          content:
              Text(current() ? '这将删除此对话的本机和学校记录，无法撤销。' : '请在当前账号下重新打开对话操作。'),
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
        setState(() {
          _conversations.removeWhere((c) => c.id == id);
        });
      }
    } catch (_) {
      if (mounted && current()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除对话失败')),
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
      if (current() && !cancellation.isCancelled) await _loadHistory();
    } catch (error) {
      if (mounted && current() && !cancellation.isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              genAiFailureText(
                error is GenAiFailure
                    ? error
                    : const GenAiFailure(GenAiFailureKind.transport),
              ),
            ),
          ),
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
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GenAiToolsPage(
          workspace: controller,
          initialTab: tab,
          demo: widget.demo,
        ),
      ),
    );
    if (mounted &&
        identical(controller, _state) &&
        controller.accountScope == accountScope &&
        controller.sessions.revision == revision) {
      if (opened == true) _draft.clear();
      unawaited(_loadHistory());
    }
  }

  void _newConversation() {
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
    if (mounted) unawaited(_loadHistory());
  }

  Future<void> _retryTurn(int index) async {
    if (_state.sending || !_state.connected || _state.selectedModel == null) {
      return;
    }
    final sending = _state.retryTurn(index);
    _scrollToEnd();
    await sending;
    if (mounted) unawaited(_loadHistory());
  }

  Future<void> _copy(String text, [String message = '已复制回复']) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 1)),
    );
  }

  Future<void> _openLink(String? link) async {
    final uri = Uri.tryParse(link ?? '');
    if (uri == null ||
        !const ['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开链接')));
      }
    }
  }

  Future<void> _toggleTts(int index, String text) async {
    if (!_audioPlayer.isSupported) return;
    final scope = _scope;
    final operation = ++_ttsOperation;
    bool current() => _isCurrent(scope) && operation == _ttsOperation;
    if (_playingTtsTurnIndex == index) {
      await _audioPlayer.stop();
      if (!current()) return;
      setState(() {
        _playingTtsTurnIndex = null;
        _loadingTts = false;
      });
      return;
    }
    await _audioPlayer.stop();
    if (!current()) return;
    setState(() {
      _playingTtsTurnIndex = index;
      _loadingTts = true;
    });
    try {
      final cleanText = text
          .replaceAll(RegExp(r'```[\s\S]*?```'), '')
          .replaceAll(RegExp(r'[#*`_~]'), '')
          .trim();
      final wavBytes = await scope.$1.synthesizeSpeech(
        cleanText.length > 500 ? cleanText.substring(0, 500) : cleanText,
      );
      if (!current()) return;
      setState(() => _loadingTts = false);
      await _audioPlayer.playWav(wavBytes);
    } catch (_) {
      if (mounted && current()) {
        setState(() {
          _playingTtsTurnIndex = null;
          _loadingTts = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音播报失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    final scope = _scope;
    try {
      if (!_picker.supportsDocuments) return;
      final file = await _picker.pickDocument();
      if (file == null || !_isCurrent(scope)) return;
      await scope.$1.addDocumentAttachment(file.name, file.bytes);
    } catch (_) {
      if (mounted && _isCurrent(scope)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法选择文档')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    final scope = _scope;
    try {
      final file = await _picker.pickImage();
      if (file == null || !_isCurrent(scope)) return;
      await scope.$1.addImageAttachment(file.name, file.bytes);
    } catch (_) {
      if (mounted && _isCurrent(scope)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法选择图片')),
        );
      }
    }
  }

  Future<void> _startAudioRecording() async {
    if (!_audioRecorder.isSupported ||
        _recordingAudio ||
        _startingAudio ||
        _state.sending ||
        _state.recognizingAudio) {
      return;
    }
    final scope = _scope;
    _startingAudio = true;
    try {
      final hasPerm = await _audioRecorder.hasPermission();
      if (!_isCurrent(scope)) return;
      if (!hasPerm) {
        if (mounted && _isCurrent(scope)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('无法访问麦克风，请检查权限设置')),
          );
        }
        return;
      }
      await _audioRecorder.start();
      if (!_isCurrent(scope)) {
        await _audioRecorder.cancel();
        return;
      }
      setState(() {
        _recordingAudio = true;
        _recordingSeconds = 0;
      });
      _recordingTimer?.cancel();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        setState(() {
          _recordingSeconds++;
        });
        if (_recordingSeconds >= 120) {
          unawaited(_stopAudioRecording());
        }
      });
    } catch (_) {
      if (mounted && _isCurrent(scope)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法启动麦克风录音，请检查权限设置')),
        );
      }
    } finally {
      _startingAudio = false;
    }
  }

  Future<void> _stopAudioRecording() async {
    final scope = _scope;
    if (!_recordingAudio) return;
    _recordingTimer?.cancel();
    setState(() => _recordingAudio = false);
    try {
      final wavBytes = await _audioRecorder.stop();
      if (wavBytes == null || wavBytes.isEmpty || !_isCurrent(scope)) return;
      final text = await scope.$1.transcribeAudio('recording.wav', wavBytes);
      if (text != null && text.isNotEmpty && _isCurrent(scope)) {
        final current = _draft.text;
        _draft.text = current.isEmpty ? text : '$current $text';
        _draft.selection = TextSelection.collapsed(offset: _draft.text.length);
        _inputFocus.requestFocus();
      }
    } catch (_) {
      if (mounted && _isCurrent(scope)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别失败，请稍后重试')),
        );
      }
    }
  }

  Future<void> _cancelAudioRecording() async {
    if (!_recordingAudio) return;
    _recordingTimer?.cancel();
    setState(() => _recordingAudio = false);
    await _audioRecorder.cancel();
  }

  Future<void> _pickAudioFile() async {
    final scope = _scope;
    try {
      if (!_picker.supportsAudio) return;
      final file = await _picker.pickAudio();
      if (file == null || !_isCurrent(scope)) return;
      final text = await scope.$1.transcribeAudio(file.name, file.bytes);
      if (text != null && text.isNotEmpty && _isCurrent(scope)) {
        final current = _draft.text;
        _draft.text = current.isEmpty ? text : '$current $text';
        _draft.selection = TextSelection.collapsed(offset: _draft.text.length);
      }
    } catch (_) {
      if (mounted && _isCurrent(scope)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别失败，请稍后重试')),
        );
      }
    }
  }

  @override
  void dispose() {
    _sidebarSearchTimer?.cancel();
    _sidebarSearch.dispose();
    _recordingTimer?.cancel();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _historyCancellation?.cancel();
    _deletionCheck?.cancel();
    _state.removeListener(_changed);
    _state.cancelAgentForPageExit();
    _refresh?.cancel();
    _draft.dispose();
    _inputFocus.removeListener(_draftChanged);
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = _theme;
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final canvas = theme.colorScheme.surface;
    return Theme(
      data: theme,
      child: Scaffold(
        backgroundColor: canvas,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, size) {
              final wide = size.maxWidth >= 960;
              return Row(
                children: [
                  if (wide) _sidebar(theme),
                  Expanded(
                    child: Column(
                      children: [
                        _header(wide),
                        if (widget.demo && !keyboardOpen) _demoNotice(),
                        if (_state.connected) _modelBar(wide),
                        if (_state.catalogFailure != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: _notice(
                              genAiFailureText(_state.catalogFailure!),
                              action: TextButton(
                                onPressed: () =>
                                    unawaited(_state.reloadModels()),
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
                              '此对话尚未安全保存。请保留此页面，检查设备存储后重试。',
                              action: TextButton(
                                onPressed: () async {
                                  try {
                                    await _state.retrySaveConversations();
                                  } catch (_) {
                                    // The persistent notice remains until a successful retry.
                                  }
                                },
                                child: const Text('重新保存'),
                              ),
                            ),
                          ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, bodySize) => Column(
                              children: [
                                Expanded(
                                  child: !_state.connected
                                      ? _loginPanel()
                                      : _state.turns.isEmpty
                                          ? _welcome(size.maxWidth)
                                          : _thread(),
                                ),
                                if (_state.connected)
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: bodySize.maxHeight *
                                          (keyboardOpen ? .85 : .65),
                                    ),
                                    child: SingleChildScrollView(
                                      reverse: true,
                                      child: _composer(wide),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _sidebar(ThemeData theme) => Container(
        width: 248,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border(right: BorderSide(color: _border)),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_outlined, color: _accent, size: 28),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'TechPie',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 42, top: 2),
                child: Text(
                  '校园智能助手',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 11,
                    letterSpacing: .3,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _chatActions(labels: true),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  children: [
                    Text(
                      '历史对话',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                    const Spacer(),
                    if (_loadingHistory)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        icon: const Icon(Icons.refresh, size: 16),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 24,
                          minHeight: 24,
                        ),
                        tooltip: '刷新历史',
                        onPressed: _state.connected && !_loadingHistory
                            ? () => unawaited(_loadHistory())
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _sidebarHistoryList(theme),
              ),
              const SizedBox(height: 12),
              Divider(height: 1, color: _border),
              const SizedBox(height: 12),
              _sidebarUserFooter(theme),
            ],
          ),
        ),
      );

  Widget _sidebarHistoryList(ThemeData theme) {
    if (!_state.connected) {
      return Center(
        child: Text('未连接 GenAI', style: TextStyle(fontSize: 12, color: _muted)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: SizedBox(
            height: 34,
            child: TextField(
              controller: _sidebarSearch,
              style: const TextStyle(fontSize: 12),
              onChanged: _onSidebarSearchChanged,
              decoration: InputDecoration(
                hintText: '搜索历史对话',
                hintStyle: TextStyle(fontSize: 12, color: _muted),
                prefixIcon: Icon(Icons.search, size: 16, color: _muted),
                prefixIconConstraints: const BoxConstraints(minWidth: 32),
                suffixIcon: _sidebarSearch.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 14),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28),
                        onPressed: () {
                          _sidebarSearch.clear();
                          _onSidebarSearchChanged('');
                        },
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                isDense: true,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: .5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        if (_historyFailure case final failure?)
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              children: [
                Text(
                  genAiFailureText(failure),
                  style: TextStyle(fontSize: 12, color: _muted),
                ),
                TextButton(
                  onPressed: () => unawaited(_loadHistory()),
                  child: const Text('重试加载历史'),
                ),
              ],
            ),
          ),
        Expanded(
          child: _loadingHistory && _conversations.isEmpty
              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
              : _conversations.isEmpty
                  ? _historyFailure != null
                      ? const SizedBox.shrink()
                      : Center(
                          child: Text(
                            _sidebarQuery.isNotEmpty ? '未找到相关对话' : '暂无历史对话',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                        )
                  : ListView.builder(
                      itemCount:
                          _conversations.length + (_hasMoreHistory ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= _conversations.length) {
                          return Center(
                            child: TextButton(
                              onPressed: _loadingHistory
                                  ? null
                                  : () => unawaited(_loadHistory(more: true)),
                              child: const Text(
                                '加载更多',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                          );
                        }
                        final item = _conversations[index];
                        final isActive = item.id == _state.groupId;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Material(
                            color: isActive
                                ? _accent.withValues(alpha: .12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: _state.sending || isActive
                                  ? null
                                  : () => unawaited(_openConversation(item)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: isActive
                                      ? Border.all(
                                          color: _accent.withValues(alpha: .3),
                                        )
                                      : null,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isActive
                                          ? Icons.chat_bubble_rounded
                                          : Icons.chat_bubble_outline_rounded,
                                      size: 16,
                                      color: isActive ? _accent : _muted,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            item.title.isEmpty
                                                ? '未命名对话'
                                                : item.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isActive
                                                  ? FontWeight.w600
                                                  : FontWeight.normal,
                                              color: isActive
                                                  ? _accent
                                                  : theme.colorScheme.onSurface,
                                            ),
                                          ),
                                          if (item.time.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                              item.time.split(' ').first,
                                              style: TextStyle(
                                                fontSize: 10,
                                                color: _muted,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                    GenAiConversationMenu(
                                      key: ValueKey(item.id),
                                      workspace: _state,
                                      conversation: item,
                                      enabled: !_state.sending,
                                      onChanged: () =>
                                          unawaited(_loadHistory()),
                                      onDelete: () => unawaited(
                                        _deleteConversation(item.id),
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
        ),
      ],
    );
  }

  Widget _sidebarUserFooter(ThemeData theme) => Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: _accent.withValues(alpha: .1),
            child: Icon(Icons.person_outline, size: 19, color: _accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _state.connected
                      ? (widget.demo
                          ? '预览同学'
                          : _state.sessions.session!.profile.username)
                      : '尚未连接',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.demo ? '本地演示账户' : '校园 GenAI',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
        ],
      );

  Widget _chatActions({bool labels = false}) {
    final actions = [
      if (labels)
        (Icons.edit_square, '新的对话', '新对话', _newConversation as VoidCallback?),
      (
        Icons.forum_outlined,
        '会话记录',
        '会话',
        _state.connected && !_state.sending
            ? () => unawaited(_openTools(0))
            : null
      ),
      (
        Icons.image_outlined,
        '图片创作',
        '图片',
        _state.connected && !_state.sending
            ? () => unawaited(_openTools(1))
            : null
      ),
    ];
    Widget button((IconData, String, String, VoidCallback?) action) => labels
        ? Tooltip(
            message: action.$2,
            child: TextButton(
              key: action.$1 == Icons.edit_square
                  ? const ValueKey('genai-new-chat-wide')
                  : null,
              onPressed: action.$4,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(action.$1, size: 21),
                  const SizedBox(height: 5),
                  Text(action.$3, style: const TextStyle(fontSize: 12)),
                ],
              ),
            ),
          )
        : IconButton(
            tooltip: action.$2,
            onPressed: action.$4,
            icon: Icon(action.$1, size: 21),
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          );
    return Row(
      mainAxisSize: labels ? MainAxisSize.max : MainAxisSize.min,
      children: [
        for (final action in actions)
          if (labels) Expanded(child: button(action)) else button(action),
      ],
    );
  }

  Widget _header(bool wide) {
    final scope = _scope;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: wide ? 28 : 12, vertical: 10),
      child: Row(
        children: [
          if (Navigator.of(context).canPop())
            IconButton(
              onPressed: () => Navigator.of(context).pop(),
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
            ),
          if (!wide && MediaQuery.sizeOf(context).width >= 480) ...[
            Icon(Icons.auto_awesome_outlined, color: _accent),
            const SizedBox(width: 10),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GenAI',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -.4,
                  ),
                ),
              ],
            ),
          ),
          if (!wide) _chatActions(),
          PopupMenuButton<String>(
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
                  _state.connected
                      ? _state.sessions.session!.profile.username
                      : '尚未连接',
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
          ),
        ],
      ),
    );
  }

  Widget _demoNotice() => Container(
        width: double.infinity,
        color: _accent.withValues(alpha: .06),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.science_outlined, size: 15, color: _accent),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '本地演示 · 不访问校园服务，不产生费用',
                style: TextStyle(fontSize: 11, color: _accent),
              ),
            ),
          ],
        ),
      );

  Widget _modelBar(bool wide) => Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 868),
          padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 4, wide ? 24 : 16, 4),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 240),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: _theme.colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.auto_awesome_outlined,
                              size: 15,
                              color: _accent,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<GenAiModel>(
                                  key: const ValueKey('genai-model'),
                                  borderRadius: BorderRadius.circular(16),
                                  isDense: true,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  isExpanded: true,
                                  value: _state.selectedModel,
                                  hint: Text(
                                    _state.loadingModels ? '正在加载模型…' : '选择模型',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down,
                                    color: _muted,
                                    size: 20,
                                  ),
                                  items: _state.models
                                      .where((model) => !model.isImage)
                                      .map(
                                        (model) => DropdownMenuItem(
                                          value: model,
                                          child: Text(
                                            '${model.name}${model.payType == 'FREE' ? '' : model.payType == 'PAID' ? ' · 付费' : ' · 费用未知'}',
                                            style:
                                                const TextStyle(fontSize: 12),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: _state.sending
                                      ? null
                                      : (model) {
                                          if (model != null) {
                                            _state.selectModel(model);
                                          }
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (_state.selectedModel != null &&
                        (wide || MediaQuery.sizeOf(context).width >= 400))
                      Text(
                        _state.selectedModel!.payType == 'FREE'
                            ? '免费'
                            : _state.selectedModel!.payType == 'PAID'
                                ? '付费模型'
                                : '费用未知',
                        style: TextStyle(
                          fontSize: 11,
                          color: _state.selectedModel!.payType == 'FREE'
                              ? _accent
                              : _theme.colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
              if (!wide) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: '新的对话',
                  child: TextButton.icon(
                    key: const ValueKey('genai-new-chat-compact'),
                    onPressed: _newConversation,
                    icon: const Icon(Icons.edit_square, size: 20),
                    label: const Text('新对话'),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      foregroundColor: _accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      );

  bool get _canResolveCampusIdentity =>
      widget.campusBound &&
      widget.onCampusLogin != null &&
      widget.onSignIn == null;

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
                  style: _theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                Text(
                  _state.sessions.owner == null
                      ? (_canResolveCampusIdentity
                          ? 'IDS 账号已绑定。连接 GenAI 后，将通过学校平台核验你的校园身份。'
                          : '登录 TechPie 并绑定校园账号后，即可连接学校的 GenAI 平台。')
                      : '使用上海科技大学账号，\n开启学习、编程与灵感探索的新对话。',
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
                              : '连接校园 GenAI',
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: _theme.colorScheme.surface,
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
                if (widget.onCampusLogin != null &&
                    _state.sessions.owner != null)
                  TextButton.icon(
                    onPressed: _state.connecting ? null : widget.onCampusLogin,
                    icon: const Icon(Icons.open_in_browser, size: 18),
                    label: const Text('使用 TechPie IDS 登录'),
                  ),
                if ((_state.sessions.owner != null || widget.campusBound) &&
                    widget.onBindCampus != null)
                  TextButton(
                    onPressed: widget.onBindCampus,
                    child: const Text('管理校园账号'),
                  ),
                if (_state.loginFailure != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: _notice(genAiFailureText(_state.loginFailure!)),
                  ),
                const SizedBox(height: 24),
                Text(
                  widget.demo
                      ? '登录过程同样使用本地演示数据'
                      : widget.ephemeral
                          ? '真实学校登录 · 凭据仅保存在内存'
                          : '学校账号登录 · 独立安全存储',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _welcome(double width) => LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 220;
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 24,
                vertical: compact ? 10 : 28,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 650),
                child: Column(
                  children: [
                    if (!compact) ...[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child:
                            Icon(Icons.auto_awesome, color: _accent, size: 31),
                      ),
                      const SizedBox(height: 24),
                    ],
                    Text(
                      _chatCopy.title,
                      key: const ValueKey('genai-welcome-title'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: compact ? 22 : (width < 500 ? 26 : 34),
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.8,
                      ),
                    ),
                    SizedBox(height: compact ? 6 : 12),
                    Text(
                      _chatCopy.subtitle,
                      key: const ValueKey('genai-welcome-subtitle'),
                      textAlign: TextAlign.center,
                      style:
                          TextStyle(color: _muted, fontSize: 13, height: 1.8),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
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
              constraints: const BoxConstraints(maxWidth: 760),
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
                              borderRadius: BorderRadius.circular(20),
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
                                        if (turn
                                            .attachedImageBytesList.isNotEmpty)
                                          for (final bytes
                                              in turn.attachedImageBytesList)
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                        else if (turn.attachedImageBytes !=
                                            null)
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
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
                                        else if (turn
                                            .attachedImageUrls.isNotEmpty)
                                          for (final url
                                              in turn.attachedImageUrls.map(
                                            (url) => _state.repository
                                                .imageDisplayUri(url)
                                                .toString(),
                                          ))
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
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
                                            borderRadius:
                                                BorderRadius.circular(8),
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
                                        for (final fileName
                                            in turn.attachedFileNames)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 3,
                                            ),
                                            decoration: BoxDecoration(
                                              color: _accent.withValues(
                                                alpha: .15,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(6),
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
                            padding:
                                const EdgeInsets.only(bottom: 16, right: 4),
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
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: _accent.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Icons.auto_awesome,
                            size: 17,
                            color: _accent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          turn.isAgent ? 'TechPie AI · 校园工具' : 'TechPie AI',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 0, top: 16),
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
                                running: _state.sending &&
                                    index == _state.turns.length - 1,
                                stopped: incomplete,
                                demo: widget.demo,
                                imageDisplayUri:
                                    _state.repository.imageDisplayUri,
                                onOpenImages: _state.sending
                                    ? null
                                    : () => unawaited(_openTools(1)),
                              ),
                            if (_state.pendingAgentApproval != null &&
                                index == _state.turns.length - 1)
                              Padding(
                                padding: const EdgeInsets.only(top: 12),
                                child: GenAiAgentApprovalCard(
                                  call: _state.pendingAgentApproval!.call,
                                  prepared:
                                      _state.pendingAgentApproval!.prepared,
                                  onApprove: () =>
                                      _state.resolveAgentApproval(true),
                                  onReject: () =>
                                      _state.resolveAgentApproval(false),
                                ),
                              ),
                            if (turn.agentEvents.isNotEmpty)
                              const SizedBox(height: 12),
                          ],
                          if (!turn.isAgent &&
                              (turn.citations.isNotEmpty || turn.isSearching))
                            GenAiWebSearchView(
                              citations: turn.citations,
                              isSearching: turn.isSearching,
                              onOpenLink: (url) => unawaited(_openLink(url)),
                            ),
                          if (!turn.isAgent &&
                              (turn.reasoning.isNotEmpty ||
                                  turn.phase == GenAiChatPhase.streaming &&
                                      turn.answer.isEmpty))
                            GenAiThinkingView(
                              reasoning: turn.reasoning,
                              isThinking:
                                  turn.phase == GenAiChatPhase.streaming &&
                                      turn.answer.isEmpty,
                              durationMs: turn.thinkingDurationMs,
                              onTapLink: (href) => unawaited(_openLink(href)),
                            ),
                          if (turn.answer.isEmpty &&
                              !incomplete &&
                              turn.reasoning.isEmpty &&
                              !turn.isSearching &&
                              (!turn.isAgent ||
                                  _state.pendingAgentApproval == null))
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
                          if (turn.answer.isNotEmpty)
                            GenAiMarkdown(
                              data: turn.answer,
                              selectable: true,
                              imageBuilder: (uri, title, alt) => turn.isAgent
                                  ? Text(alt ?? title ?? '图片请通过工具结果查看')
                                  : Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 8,
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(
                                          uri.toString(),
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) =>
                                              Text(alt ?? title ?? '图片'),
                                        ),
                                      ),
                                    ),
                              onTapLink: (_, href, __) =>
                                  unawaited(_openLink(href)),
                            ),
                          if (incomplete)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                turn.isAgent && turn.agentStatus.isNotEmpty
                                    ? turn.agentStatus
                                    : turn.failure != null
                                        ? genAiFailureText(turn.failure!)
                                        : '已停止生成 · 内容可能不完整',
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
                          if (turn.finishReason ==
                              GenAiFinishReason.contentFilter)
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
                                  onPressed: () =>
                                      unawaited(_copy(turn.answer)),
                                ),
                                if (_audioPlayer.isSupported)
                                  IconButton(
                                    tooltip: _playingTtsTurnIndex == index
                                        ? '停止播放'
                                        : '语音播报',
                                    key: ValueKey('genai-tts-$index'),
                                    icon: _loadingTts &&
                                            _playingTtsTurnIndex == index
                                        ? SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.5,
                                              color: _accent,
                                            ),
                                          )
                                        : Icon(
                                            _playingTtsTurnIndex == index
                                                ? Icons.stop_circle_outlined
                                                : Icons.volume_up_outlined,
                                            size: 16,
                                            color: _playingTtsTurnIndex == index
                                                ? _accent
                                                : _muted,
                                          ),
                                    onPressed: () => unawaited(
                                      _toggleTts(index, turn.answer),
                                    ),
                                  ),
                              ],
                              if (incomplete &&
                                  !turn.isHistoryGap &&
                                  _state.connected)
                                TextButton.icon(
                                  key: ValueKey('genai-retry-$index'),
                                  onPressed: _state.sending
                                      ? null
                                      : () => unawaited(_retryTurn(index)),
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
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _composerMoreMenu({
    bool collapsedThinking = false,
    bool collapsedCampus = false,
  }) {
    final scope = _scope;
    return PopupMenuButton<String>(
      key: const ValueKey('genai-composer-more'),
      constraints: const BoxConstraints(minWidth: 228),
      position: PopupMenuPosition.over,
      tooltip: _state.netSearchEnabled ? '添加附件与搜索（联网搜索已开启）' : '添加附件与搜索',
      enabled: !_state.sending,
      icon: Badge(
        isLabelVisible: _state.netSearchEnabled,
        backgroundColor: _accent,
        child: Icon(Icons.add, size: 20, color: _muted),
      ),
      onSelected: (action) {
        if (!_isCurrent(scope) || _state.sending) return;
        switch (action) {
          case 'thinking':
            _state.setThinking(!_state.thinkingEnabled);
          case 'campus':
            _state.setAgentEnabled(!_state.agentEnabled);
          case 'search':
            _state.setNetSearch(!_state.netSearchEnabled);
          case 'document':
            unawaited(_pickDocument());
          case 'image':
            unawaited(_pickImage());
          case 'audio':
            if (!_state.recognizingAudio &&
                !_recordingAudio &&
                !_startingAudio) {
              unawaited(_pickAudioFile());
            }
        }
      },
      itemBuilder: (_) => [
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
        PopupMenuItem<String>(
          key: const ValueKey('genai-search-toggle'),
          value: 'search',
          child: _composerMenuRow(
            Icons.travel_explore_outlined,
            '联网搜索',
            selected: _state.netSearchEnabled,
          ),
        ),
        const PopupMenuDivider(height: 12),
        if (_picker.supportsDocuments)
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
        if (_picker.supportsAudio)
          PopupMenuItem<String>(
            value: 'audio',
            enabled:
                !_state.recognizingAudio && !_recordingAudio && !_startingAudio,
            child: _composerMenuRow(
              Icons.audio_file_outlined,
              '上传音频',
              disabled:
                  _state.recognizingAudio || _recordingAudio || _startingAudio,
            ),
          ),
      ],
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
              color: (selected ? _accent : _muted)
                  .withValues(alpha: disabled ? .04 : .1),
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
                color: disabled
                    ? _muted.withValues(alpha: .5)
                    : _theme.colorScheme.onSurface,
              ),
            ),
          ),
          if (selected) Icon(Icons.check_rounded, color: _accent, size: 18),
        ],
      );

  static const _modePadding = EdgeInsets.symmetric(horizontal: 4);
  static const _modeLabelPadding =
      EdgeInsets.symmetric(horizontal: 4, vertical: 2);

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
    final width = painter.width.ceilToDouble() +
        20 +
        _modePadding.horizontal +
        _modeLabelPadding.horizontal;
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
        avatarBoxConstraints:
            const BoxConstraints.tightFor(width: 20, height: 20),
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
          (states) => Color.alphaBlend(
            _accent.withValues(
              alpha: states.contains(WidgetState.selected) ? .14 : .025,
            ),
            _theme.colorScheme.surface,
          ),
        ),
      );

  Widget _composerToolbar() => LayoutBuilder(
        builder: (context, constraints) {
          final hasAudio = _audioRecorder.isSupported || _picker.supportsAudio;
          final actionWidth = (hasAudio ? 48 : 0) + 6 + 48;
          final available = constraints.maxWidth - actionWidth - 8;
          final thinkingWidth = _modeChipWidth('深度思考');
          final campusWidth = _modeChipWidth('校园工具');
          final searchWidth = _modeChipWidth('联网搜索');
          var showThinking = true;
          var showCampus = _state.agentAvailable;
          double modesWidth() =>
              48 +
              (showThinking ? thinkingWidth + 6 : 0) +
              (showCampus ? campusWidth + 6 : 0) +
              (_state.netSearchEnabled ? searchWidth + 6 : 0);
          // Reserve the microphone and Send first. Preserve active modes;
          // hide inactive campus tools before hiding inactive thinking.
          if (modesWidth() > available && showCampus && !_state.agentEnabled) {
            showCampus = false;
          }
          if (modesWidth() > available && !_state.thinkingEnabled) {
            showThinking = false;
          }
          final primary = <Widget>[
            SizedBox(
              width: 48,
              height: 48,
              child: _composerMoreMenu(
                collapsedThinking: !showThinking,
                collapsedCampus: _state.agentAvailable && !showCampus,
              ),
            ),
            if (showThinking)
              _modeChip(
                key: 'genai-thinking-toggle',
                label: '深度思考',
                icon: Icons.psychology_outlined,
                selected: _state.thinkingEnabled,
                onSelected: _state.sending ? null : _state.setThinking,
              ),
            if (showCampus)
              Tooltip(
                message: '使用校园工具，可结合附件、深度思考和联网搜索',
                child: _modeChip(
                  key: 'genai-agent-toggle',
                  label: '校园工具',
                  icon: Icons.auto_awesome_outlined,
                  selected: _state.agentEnabled,
                  onSelected: _state.sending ? null : _state.setAgentEnabled,
                ),
              ),
          ];
          final search = _state.netSearchEnabled
              ? Tooltip(
                  message: '联网搜索已开启，点击关闭',
                  child: _modeChip(
                    key: 'genai-active-search-toggle',
                    label: '联网搜索',
                    icon: Icons.travel_explore_outlined,
                    selected: true,
                    onSelected: _state.sending ? null : _state.setNetSearch,
                  ),
                )
              : null;
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_audioRecorder.isSupported || _picker.supportsAudio)
                GestureDetector(
                  // Keep the semantics structure stable while
                  // recording changes the inner button label.
                  onLongPress: !_picker.supportsAudio
                      ? null
                      : () {
                          if (!_state.sending &&
                              !_state.recognizingAudio &&
                              !_recordingAudio) {
                            unawaited(_pickAudioFile());
                          }
                        },
                  child: IconButton(
                    key: const ValueKey('genai-audio-stt'),
                    constraints:
                        const BoxConstraints(minWidth: 48, minHeight: 48),
                    tooltip: !_audioRecorder.isSupported
                        ? '选择音频文件'
                        : _recordingAudio
                            ? '完成录音并识别'
                            : _picker.supportsAudio
                                ? '麦克风录音（长按选择音频文件）'
                                : '麦克风录音',
                    icon: _state.recognizingAudio
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: _accent,
                            ),
                          )
                        : _recordingAudio
                            ? const Icon(
                                Icons.stop_circle_outlined,
                                size: 19,
                                color: Colors.redAccent,
                              )
                            : Icon(
                                Icons.mic_none,
                                size: 17,
                                color: _muted,
                              ),
                    onPressed: _state.sending || _state.recognizingAudio
                        ? null
                        : !_audioRecorder.isSupported
                            ? _pickAudioFile
                            : _recordingAudio
                                ? _stopAudioRecording
                                : _startAudioRecording,
                    visualDensity: VisualDensity.standard,
                  ),
                ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: const ValueKey('genai-send'),
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                tooltip: _state.sending
                    ? '停止生成'
                    : _state.hasPendingUploads
                        ? '正在上传附件...'
                        : _state.hasFailedUploads
                            ? '附件上传失败，请重试或删除后发送'
                            : '发送消息',
                onPressed: _state.sending
                    ? _state.stop
                    : _canSend
                        ? () => unawaited(_send())
                        : null,
                style: IconButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: _theme.colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(
                  _state.sending
                      ? Icons.stop_rounded
                      : Icons.arrow_upward_rounded,
                  size: 21,
                ),
              ),
            ],
          );
          final modes = [...primary, if (search != null) search];
          final widestMode = [
            48.0,
            if (showThinking) thinkingWidth,
            if (showCampus) campusWidth,
            if (search != null) searchWidth,
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

  Widget _composer(bool wide) => Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 868),
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 12, wide ? 24 : 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                padding: const EdgeInsets.fromLTRB(18, 10, 12, 12),
                decoration: BoxDecoration(
                  color: Color.alphaBlend(
                    _accent.withValues(alpha: .025),
                    _theme.colorScheme.surface,
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _inputFocus.hasFocus
                        ? _accent.withValues(alpha: .5)
                        : _border,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 28,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_recordingAudio) _buildRecordingBar(),
                    if (_state.attachments.isNotEmpty)
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
                                itemCount: _state.attachments.length,
                                separatorBuilder: (_, __) =>
                                    const SizedBox(width: 8),
                                itemBuilder: (context, i) {
                                  final att = _state.attachments[i];
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
                                            ? _theme.colorScheme.error
                                                .withValues(alpha: .5)
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
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  att.name,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                    fontSize: 11,
                                                    fontWeight: FontWeight.w500,
                                                    color: isError
                                                        ? _theme
                                                            .colorScheme.error
                                                        : _accent,
                                                  ),
                                                ),
                                              ),
                                              if (isError) ...[
                                                const SizedBox(width: 4),
                                                Container(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                    horizontal: 4,
                                                    vertical: 1,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: _theme
                                                        .colorScheme.error
                                                        .withValues(alpha: .15),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                      4,
                                                    ),
                                                  ),
                                                  child: Text(
                                                    att.error ?? '上传失败',
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: _theme
                                                          .colorScheme.error,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                        if (isError) ...[
                                          const SizedBox(width: 4),
                                          InkWell(
                                            key: ValueKey(
                                              'genai-retry-attachment-${att.id}',
                                            ),
                                            onTap: () => unawaited(
                                              _state.retryAttachment(att.id),
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(10),
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
                                          onTap: () =>
                                              _state.removeAttachment(att.id),
                                          borderRadius:
                                              BorderRadius.circular(10),
                                          child: Tooltip(
                                            message: '移除附件',
                                            child: Icon(
                                              Icons.close,
                                              size: 13,
                                              color: isError
                                                  ? _theme.colorScheme.error
                                                  : _muted,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                            if (_state.hasFailedUploads) ...[
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
                                      '附件上传失败，已阻止发送。请点击重试或删除失败的附件。',
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
                            !(_draft.value.composing.isValid &&
                                !_draft.value.composing.isCollapsed)) {
                          unawaited(_send());
                          return KeyEventResult.handled;
                        }
                        return KeyEventResult.ignored;
                      },
                      child: TextField(
                        key: const ValueKey('genai-prompt'),
                        controller: _draft,
                        focusNode: _inputFocus,
                        minLines: 1,
                        maxLines: 6,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          hintText: _chatCopy.hint,
                          hintStyle: const TextStyle(fontSize: 14.5),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 15.5, height: 1.6),
                      ),
                    ),
                    _composerToolbar(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                _state.agentEnabled
                    ? '工具数据会发送给学校模型 · 预约和生图需确认'
                    : 'AI 可能出错，请核查重要信息。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 10, color: _muted),
              ),
            ],
          ),
        ),
      );

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
        onTap: () => _showImageDialog(bytes: bytes, url: url),
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

  Widget _buildRecordingBar() {
    final m = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final s = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: .25)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '正在录音 $m:$s',
            key: const ValueKey('genai-recording-duration'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.redAccent,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: _AudioWaveformVisualizer(),
          ),
          TextButton(
            key: const ValueKey('genai-cancel-recording'),
            onPressed: _cancelAudioRecording,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('取消', style: TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 4),
          FilledButton.tonal(
            key: const ValueKey('genai-finish-recording'),
            onPressed: _stopAudioRecording,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 14),
                SizedBox(width: 4),
                Text('完成', style: TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AudioWaveformVisualizer extends StatefulWidget {
  const _AudioWaveformVisualizer();

  @override
  State<_AudioWaveformVisualizer> createState() =>
      _AudioWaveformVisualizerState();
}

class _AudioWaveformVisualizerState extends State<_AudioWaveformVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    unawaited(_controller.repeat(reverse: true));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        const heights = [0.4, 0.8, 1.0, 0.6, 0.9, 0.5, 0.7];
        return SizedBox(
          height: 16,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(heights.length, (i) {
              final wave = ((heights[i] + (i.isEven ? t : 1 - t) * 0.5) % 1.0)
                  .clamp(0.2, 1.0);
              return Container(
                width: 2.5,
                height: 16 * wave,
                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(1.5),
                ),
              );
            }),
          ),
        );
      },
    );
  }
}
