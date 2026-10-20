import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/genai_chat_service.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_session.dart';
import 'audio/genai_audio_player.dart';
import 'genai_copy.dart';
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
    this.onPreviewLiveLogin,
  });

  final GenAiWorkspaceController controller;
  final GenAiLoginAction login;
  final bool demo;
  final bool ephemeral;
  final bool campusBound;
  final VoidCallback? onSignIn;
  final VoidCallback? onBindCampus;
  final VoidCallback? onPreviewLiveLogin;

  @override
  State<GenAiWorkspace> createState() => _GenAiWorkspaceState();
}

class _GenAiWorkspaceState extends State<GenAiWorkspace> {
  final _draft = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  final _conversations = <GenAiConversationSummary>[];
  final _sidebarImages = <GenAiImageRecord>[];
  final _picker = GenAiPicker();
  final _audioPlayer = GenAiAudioPlayer();
  int? _playingTtsTurnIndex;
  bool _loadingTts = false;
  Timer? _refresh;
  bool _openingLogin = false;
  bool _loadingHistory = false;
  bool _hasMoreHistory = false;
  int _historyPage = 1;
  GenAiCancellation? _historyCancellation;
  bool _loadingImages = false;
  bool _hasMoreImages = false;
  int _imagePage = 1;
  GenAiCancellation? _imageCancellation;
  int _sidebarTab = 0;
  GenAiImageRecord? _selectedImage;
  GenAiOwner? _draftOwner;
  GenAiWorkspaceController get _state => widget.controller;
  Color get _accent => Theme.of(context).brightness == Brightness.dark
      ? const Color(0xff67d4c2)
      : const Color(0xff167c6d);
  Color get _muted => Theme.of(context).colorScheme.onSurfaceVariant;
  Color get _border =>
      Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .65);
  bool get _canSend =>
      _state.connected &&
      _state.selectedModel != null &&
      (_draft.text.trim().isNotEmpty || _state.attachments.isNotEmpty) &&
      !_state.sending;

  @override
  void initState() {
    super.initState();
    _draftOwner = _state.sessions.owner;
    _state.addListener(_changed);
    _draft.addListener(_draftChanged);
    _audioPlayer.onFinished = () {
      if (mounted) setState(() => _playingTtsTurnIndex = null);
    };
    unawaited(_state.restore());
    if (_state.connected) {
      unawaited(_loadHistory());
      unawaited(_loadImageHistory());
    }
  }

  @override
  void didUpdateWidget(covariant GenAiWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;
    oldWidget.controller.removeListener(_changed);
    _draft.clear();
    _state.addListener(_changed);
    unawaited(_state.restore());
  }

  void _draftChanged() {
    if (mounted) setState(() {});
  }

  void _changed() {
    if (!mounted) return;
    if (_draftOwner != _state.sessions.owner) {
      _draftOwner = _state.sessions.owner;
      _draft.clear();
      _conversations.clear();
      _sidebarImages.clear();
      _selectedImage = null;
      _historyPage = 1;
      _hasMoreHistory = false;
      _imagePage = 1;
      _hasMoreImages = false;
    }
    if (_state.connected) {
      if (_conversations.isEmpty && !_loadingHistory) {
        unawaited(_loadHistory());
      }
      if (_sidebarImages.isEmpty && !_loadingImages) {
        unawaited(_loadImageHistory());
      }
    } else if (!_state.connected && _conversations.isNotEmpty) {
      _conversations.clear();
      _sidebarImages.clear();
      _selectedImage = null;
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

  Future<void> _loadHistory({bool more = false}) async {
    if (!_state.connected || _loadingHistory) return;
    _historyCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _historyCancellation = cancellation;
    final page = more ? _historyPage + 1 : 1;
    setState(() => _loadingHistory = true);
    try {
      final result = await _state.repository.listConversations(
        cancellation,
        page: page,
      );
      if (!mounted || cancellation.isCancelled) return;
      setState(() {
        if (!more) _conversations.clear();
        _conversations.addAll(result.records);
        _hasMoreHistory = result.hasMore;
        _historyPage = page;
      });
    } catch (_) {
      // Best-effort history load
    } finally {
      if (identical(_historyCancellation, cancellation)) {
        _historyCancellation = null;
      }
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  Future<void> _openConversation(GenAiConversationSummary item) async {
    if (_state.sending || item.id == _state.groupId) return;
    _selectedImage = null;
    final cancellation = GenAiCancellation();
    try {
      await _state.openConversation(item.id, cancellation);
      _draft.clear();
      _scrollToEnd();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('加载对话失败')),
        );
      }
    }
  }

  Future<void> _deleteConversation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除此对话？'),
        content: const Text('这将删除学校平台上的记录，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cancellation = GenAiCancellation();
    try {
      await _state.repository.deleteConversation(id, cancellation);
      if (mounted) {
        setState(() {
          _conversations.removeWhere((c) => c.id == id);
        });
      }
      if (_state.groupId == id) {
        _newConversation();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除对话失败')),
        );
      }
    }
  }

  Future<void> _loadImageHistory({bool more = false}) async {
    if (!_state.connected || _loadingImages) return;
    _imageCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _imageCancellation = cancellation;
    final page = more ? _imagePage + 1 : 1;
    setState(() => _loadingImages = true);
    try {
      final data = await _state.repository.listImages(cancellation, page: page);
      if (!mounted || cancellation.isCancelled) return;
      setState(() {
        if (!more) _sidebarImages.clear();
        _sidebarImages.addAll(data.records);
        _hasMoreImages = data.hasMore;
        _imagePage = page;
      });
    } catch (_) {
      // Best-effort image history load
    } finally {
      if (mounted && identical(_imageCancellation, cancellation)) {
        setState(() => _loadingImages = false);
      }
    }
  }

  Future<void> _deleteImageRecord(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除图片记录？'),
        content: const Text('这将删除学校平台上的记录，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final cancellation = GenAiCancellation();
    try {
      await _state.repository.deleteImage(id, cancellation);
      if (mounted) {
        setState(() {
          _sidebarImages.removeWhere((img) => img.id == id);
          if (_selectedImage?.id == id) {
            _selectedImage = null;
          }
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('删除图片记录失败')),
        );
      }
    }
  }

  Future<void> _openTools(int tab) async {
    if (!_state.connected || _state.sending) return;
    final opened = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => GenAiToolsPage(
          workspace: _state,
          initialTab: tab,
          demo: widget.demo,
        ),
      ),
    );
    if (mounted) {
      if (opened == true) _draft.clear();
      unawaited(_loadHistory());
      unawaited(_loadImageHistory());
    }
  }

  void _newConversation() {
    _draft.clear();
    _selectedImage = null;
    _state.newConversation();
    _inputFocus.requestFocus();
  }

  Future<void> _send([String? retry]) async {
    if (retry == null && !_canSend) return;
    if (!_state.connected || _state.selectedModel == null || _state.sending) {
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

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已复制回复'), duration: Duration(seconds: 1)),
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
    if (_playingTtsTurnIndex == index) {
      await _audioPlayer.stop();
      setState(() {
        _playingTtsTurnIndex = null;
        _loadingTts = false;
      });
      return;
    }
    await _audioPlayer.stop();
    setState(() {
      _playingTtsTurnIndex = index;
      _loadingTts = true;
    });
    try {
      final cleanText = text
          .replaceAll(RegExp(r'```[\s\S]*?```'), '')
          .replaceAll(RegExp(r'[#*`_~]'), '')
          .trim();
      final wavBytes = await _state.synthesizeSpeech(
        cleanText.length > 500 ? cleanText.substring(0, 500) : cleanText,
      );
      if (!mounted || _playingTtsTurnIndex != index) return;
      setState(() => _loadingTts = false);
      await _audioPlayer.playWav(wavBytes);
    } catch (_) {
      if (mounted) {
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
    try {
      final file = await _picker.pickDocument();
      if (file == null || !mounted) return;
      await _state.addDocumentAttachment(file.name, file.bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法选择文档')),
        );
      }
    }
  }

  Future<void> _pickImage() async {
    try {
      final file = await _picker.pickImage();
      if (file == null || !mounted) return;
      await _state.addImageAttachment(file.name, file.bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法选择图片')),
        );
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      final file = await _picker.pickAudio();
      if (file == null || !mounted) return;
      final text = await _state.transcribeAudio(file.name, file.bytes);
      if (text != null && text.isNotEmpty && mounted) {
        final current = _draft.text;
        _draft.text = current.isEmpty ? text : '$current $text';
        _draft.selection = TextSelection.collapsed(offset: _draft.text.length);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别失败，请稍后重试')),
        );
      }
    }
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _historyCancellation?.cancel();
    _imageCancellation?.cancel();
    _state.removeListener(_changed);
    _refresh?.cancel();
    _draft.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
    final dark = theme.brightness == Brightness.dark;
    final canvas = dark ? theme.colorScheme.surface : const Color(0xfff7f9f8);
    return Scaffold(
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
                      if (_state.connected && !keyboardOpen) _modelBar(),
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
                      Expanded(
                        child: !_state.connected
                            ? _loginPanel()
                            : _selectedImage != null
                                ? _imageDetailView(_selectedImage!)
                                : _state.turns.isEmpty
                                    ? _welcome(size.maxWidth)
                                    : _thread(),
                      ),
                      if (_state.connected)
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: size.maxHeight * .5),
                          child: SingleChildScrollView(
                            reverse: true,
                            child: _composer(wide),
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
    );
  }

  Widget _sidebar(ThemeData theme) => Container(
        width: 260,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
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
                    Icon(Icons.hexagon_outlined, color: _accent, size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'TechPie',
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 42, top: 2),
                child: Text(
                  'CAMPUS · GENAI',
                  style: TextStyle(
                    color: _muted,
                    fontSize: 10,
                    letterSpacing: 1.8,
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
                    _sidebarTabButton(
                      label: '对话',
                      selected: _sidebarTab == 0,
                      onTap: () {
                        setState(() => _sidebarTab = 0);
                        if (_conversations.isEmpty && !_loadingHistory) {
                          unawaited(_loadHistory());
                        }
                      },
                    ),
                    const SizedBox(width: 6),
                    _sidebarTabButton(
                      label: '生图',
                      selected: _sidebarTab == 1,
                      onTap: () {
                        setState(() => _sidebarTab = 1);
                        if (_sidebarImages.isEmpty && !_loadingImages) {
                          unawaited(_loadImageHistory());
                        }
                      },
                    ),
                    const Spacer(),
                    if (_sidebarTab == 0 ? _loadingHistory : _loadingImages)
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
                        tooltip: _sidebarTab == 0 ? '刷新历史' : '刷新生图',
                        onPressed: _state.connected &&
                                !(_sidebarTab == 0
                                    ? _loadingHistory
                                    : _loadingImages)
                            ? () => unawaited(
                                  _sidebarTab == 0
                                      ? _loadHistory()
                                      : _loadImageHistory(),
                                )
                            : null,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _sidebarTab == 0
                    ? _sidebarHistoryList(theme)
                    : _sidebarImageList(theme),
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
    if (_loadingHistory && _conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_conversations.isEmpty) {
      return Center(
        child: Text('暂无历史对话', style: TextStyle(fontSize: 12, color: _muted)),
      );
    }
    return ListView.builder(
      itemCount: _conversations.length + (_hasMoreHistory ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _conversations.length) {
          return Center(
            child: TextButton(
              onPressed: _loadingHistory
                  ? null
                  : () => unawaited(_loadHistory(more: true)),
              child: const Text('加载更多', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        final item = _conversations[index];
        final isActive = item.id == _state.groupId;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color:
                isActive ? _accent.withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: _state.sending || isActive
                  ? null
                  : () => unawaited(_openConversation(item)),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: isActive
                      ? Border.all(color: _accent.withValues(alpha: .3))
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
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            item.title.isEmpty ? '未命名对话' : item.title,
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
                              style: TextStyle(fontSize: 10, color: _muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 15),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      tooltip: '删除对话',
                      onPressed: _state.sending
                          ? null
                          : () => unawaited(_deleteConversation(item.id)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _sidebarTabButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) =>
      InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color:
                selected ? _accent.withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              color: selected ? _accent : _muted,
            ),
          ),
        ),
      );

  Widget _sidebarImageList(ThemeData theme) {
    if (!_state.connected) {
      return Center(
        child: Text('未连接 GenAI', style: TextStyle(fontSize: 12, color: _muted)),
      );
    }
    if (_loadingImages && _sidebarImages.isEmpty) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_sidebarImages.isEmpty) {
      return Center(
        child: Text('暂无历史生图', style: TextStyle(fontSize: 12, color: _muted)),
      );
    }
    return ListView.builder(
      itemCount: _sidebarImages.length + (_hasMoreImages ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= _sidebarImages.length) {
          return Center(
            child: TextButton(
              onPressed: _loadingImages
                  ? null
                  : () => unawaited(_loadImageHistory(more: true)),
              child: const Text('加载更多', style: TextStyle(fontSize: 12)),
            ),
          );
        }
        final item = _sidebarImages[index];
        final isActive = _selectedImage?.id == item.id;
        final previewUri = item.images.firstOrNull;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color:
                isActive ? _accent.withValues(alpha: .12) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() => _selectedImage = item);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: isActive
                      ? Border.all(color: _accent.withValues(alpha: .3))
                      : null,
                ),
                child: Row(
                  children: [
                    if (previewUri != null)
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: Image.network(
                            previewUri.toString(),
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Icon(
                              Icons.image_outlined,
                              size: 18,
                              color: isActive ? _accent : _muted,
                            ),
                          ),
                        ),
                      )
                    else
                      Icon(
                        Icons.image_outlined,
                        size: 18,
                        color: isActive ? _accent : _muted,
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item.prompt.isEmpty ? '图片创作' : item.prompt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.normal,
                          color:
                              isActive ? _accent : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 15),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 22,
                        minHeight: 22,
                      ),
                      tooltip: '删除图片记录',
                      onPressed: () => unawaited(_deleteImageRecord(item.id)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _imageDetailView(GenAiImageRecord record) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 868),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: '返回对话',
                      onPressed: () => setState(() => _selectedImage = null),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '图片详情',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '删除图片记录',
                      onPressed: () => unawaited(_deleteImageRecord(record.id)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 0,
                  color: theme.colorScheme.surfaceContainerHighest
                      .withValues(alpha: .5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: _border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '提示词 / Prompt',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _muted,
                          ),
                        ),
                        const SizedBox(height: 6),
                        SelectableText(
                          record.prompt.isEmpty ? '（无描述）' : record.prompt,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                for (final uri in record.images) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight > 0
                            ? constraints.maxHeight * 0.65
                            : 500,
                      ),
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: .3),
                      child: Image.network(
                        uri.toString(),
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) => Container(
                          height: 240,
                          alignment: Alignment.center,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.broken_image_outlined,
                                size: 40,
                                color: _muted,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '图片加载失败，可在浏览器中打开',
                                style: TextStyle(color: _muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: const Text('在新标签页打开原图'),
                        onPressed: () => unawaited(_openLink(uri.toString())),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ),
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

  Widget _header(bool wide) => Container(
        padding: EdgeInsets.symmetric(horizontal: wide ? 32 : 12, vertical: 16),
        decoration:
            BoxDecoration(border: Border(bottom: BorderSide(color: _border))),
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
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4,
                    ),
                  ),
                  SizedBox(height: 3),
                  Text('校园 AI', style: TextStyle(fontSize: 11)),
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
                switch (value) {
                  case 'usage':
                    unawaited(_openTools(2));
                  case 'campus':
                    widget.onBindCampus?.call();
                  case 'ids':
                    widget.onPreviewLiveLogin?.call();
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
                if (widget.demo && widget.onPreviewLiveLogin != null)
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

  Widget _modelBar() => Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 868),
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Row(
            children: [
              Flexible(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 350),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    border: Border.all(color: _border),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.hub_outlined, size: 17, color: _accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<GenAiModel>(
                            key: const ValueKey('genai-model'),
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
                                      style: const TextStyle(fontSize: 12),
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
              if (_state.selectedModel != null)
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
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
            ],
          ),
        ),
      );

  bool get _canResolveCampusIdentity =>
      widget.campusBound &&
      widget.onPreviewLiveLogin != null &&
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
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
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
                            ? widget.onPreviewLiveLogin
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
                      foregroundColor: Theme.of(context).colorScheme.surface,
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
                if (widget.onPreviewLiveLogin != null &&
                    _state.sessions.owner != null)
                  TextButton.icon(
                    onPressed:
                        _state.connecting ? null : widget.onPreviewLiveLogin,
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

  Widget _welcome(double width) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 650),
            child: Column(
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: _accent.withValues(alpha: .12)),
                  ),
                  child: Icon(Icons.auto_awesome, color: _accent, size: 31),
                ),
                const SizedBox(height: 24),
                Text(
                  '把想法，聊成答案。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: width < 500 ? 25 : 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -1.2,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '一个问题，一点灵感，或一件想弄明白的事。',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13, height: 1.8),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _thread() => ListView.builder(
        key: const ValueKey('genai-thread'),
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 12),
        itemCount: _state.turns.length,
        itemBuilder: (context, index) {
          final turn = _state.turns[index];
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
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 680),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 13,
                        ),
                        margin: const EdgeInsets.only(left: 36, bottom: 26),
                        decoration: BoxDecoration(
                          color: _accent.withValues(alpha: .09),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (turn.attachedImageUrl != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(
                                    turn.attachedImageUrl!,
                                    height: 180,
                                    fit: BoxFit.contain,
                                  ),
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
                                          color: _accent.withValues(alpha: .15),
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
                                fontSize: 14,
                                height: 1.7,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
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
                        const Text(
                          'TechPie AI',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 42, top: 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (turn.citations.isNotEmpty || turn.isSearching)
                            GenAiWebSearchView(
                              citations: turn.citations,
                              isSearching: turn.isSearching,
                              onOpenLink: (url) => unawaited(_openLink(url)),
                            ),
                          if (turn.reasoning.isNotEmpty ||
                              (turn.phase == GenAiChatPhase.streaming &&
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
                              !turn.isSearching)
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
                                  '正在思考…',
                                  style: TextStyle(color: _muted, fontSize: 12),
                                ),
                              ],
                            ),
                          if (turn.answer.isNotEmpty)
                            GenAiMarkdown(
                              data: turn.answer,
                              selectable: true,
                              imageBuilder: (uri, title, alt) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
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
                                turn.failure != null
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
                                  onPressed: () =>
                                      unawaited(_toggleTts(index, turn.answer)),
                                ),
                              ],
                              if (incomplete && _state.connected)
                                TextButton.icon(
                                  onPressed: _state.sending
                                      ? null
                                      : () => unawaited(_send(turn.prompt)),
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

  Widget _composer(bool wide) => Align(
        alignment: Alignment.center,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 868),
          padding: EdgeInsets.fromLTRB(wide ? 24 : 14, 12, wide ? 24 : 14, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(18, 8, 10, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .025),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_state.attachments.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: SizedBox(
                          height: 36,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _state.attachments.length,
                            separatorBuilder: (_, __) =>
                                const SizedBox(width: 8),
                            itemBuilder: (context, i) {
                              final att = _state.attachments[i];
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: _accent.withValues(alpha: .08),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: _accent.withValues(alpha: .2),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (att.uploading)
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.5,
                                          color: _accent,
                                        ),
                                      )
                                    else
                                      Icon(
                                        att.isImage
                                            ? Icons.image_outlined
                                            : Icons.description_outlined,
                                        size: 14,
                                        color: _accent,
                                      ),
                                    const SizedBox(width: 6),
                                    ConstrainedBox(
                                      constraints:
                                          const BoxConstraints(maxWidth: 140),
                                      child: Text(
                                        att.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                          color: _accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    InkWell(
                                      onTap: () =>
                                          _state.removeAttachment(att.id),
                                      borderRadius: BorderRadius.circular(10),
                                      child: Icon(
                                        Icons.close,
                                        size: 13,
                                        color: _muted,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
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
                        decoration: const InputDecoration(
                          hintText: '有什么想一起探索的？',
                          hintStyle: TextStyle(fontSize: 13),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                        style: const TextStyle(fontSize: 14, height: 1.6),
                      ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                FilterChip(
                                  key: const ValueKey('genai-thinking-toggle'),
                                  label: const Text(
                                    '深度思考',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  avatar: Icon(
                                    Icons.psychology_outlined,
                                    size: 14,
                                    color: _state.thinkingEnabled
                                        ? _accent
                                        : _muted,
                                  ),
                                  selected: _state.thinkingEnabled,
                                  onSelected: _state.sending
                                      ? null
                                      : (v) => _state.setThinking(v),
                                  showCheckmark: false,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: _state.thinkingEnabled
                                          ? _accent.withValues(alpha: .5)
                                          : _border,
                                    ),
                                  ),
                                  backgroundColor: Colors.transparent,
                                  selectedColor: _accent.withValues(alpha: .12),
                                ),
                                const SizedBox(width: 6),
                                FilterChip(
                                  key: const ValueKey('genai-search-toggle'),
                                  label: const Text(
                                    '联网搜索',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  avatar: Icon(
                                    Icons.travel_explore_outlined,
                                    size: 14,
                                    color: _state.netSearchEnabled
                                        ? _accent
                                        : _muted,
                                  ),
                                  selected: _state.netSearchEnabled,
                                  onSelected: _state.sending
                                      ? null
                                      : (v) => _state.setNetSearch(v),
                                  showCheckmark: false,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                    side: BorderSide(
                                      color: _state.netSearchEnabled
                                          ? _accent.withValues(alpha: .5)
                                          : _border,
                                    ),
                                  ),
                                  backgroundColor: Colors.transparent,
                                  selectedColor: _accent.withValues(alpha: .12),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  key: const ValueKey('genai-upload-file'),
                                  tooltip: '上传文档',
                                  icon: Icon(
                                    Icons.attach_file,
                                    size: 17,
                                    color: _muted,
                                  ),
                                  onPressed:
                                      _state.sending ? null : _pickDocument,
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  key: const ValueKey('genai-upload-image'),
                                  tooltip: '上传图片',
                                  icon: Icon(
                                    Icons.image_outlined,
                                    size: 17,
                                    color: _muted,
                                  ),
                                  onPressed: _state.sending ? null : _pickImage,
                                  visualDensity: VisualDensity.compact,
                                ),
                                IconButton(
                                  key: const ValueKey('genai-audio-stt'),
                                  tooltip: '语音输入',
                                  icon: _state.recognizingAudio
                                      ? SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 1.5,
                                            color: _accent,
                                          ),
                                        )
                                      : Icon(
                                          Icons.mic_none,
                                          size: 17,
                                          color: _muted,
                                        ),
                                  onPressed:
                                      _state.sending || _state.recognizingAudio
                                          ? null
                                          : _pickAudio,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (wide)
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Text(
                              'Enter 发送 · Shift + Enter 换行',
                              style: TextStyle(fontSize: 10, color: _muted),
                            ),
                          ),
                        const SizedBox(width: 6),
                        IconButton.filled(
                          key: const ValueKey('genai-send'),
                          tooltip: _state.sending ? '停止生成' : '发送消息',
                          onPressed: _state.sending
                              ? _state.stop
                              : _canSend
                                  ? () => unawaited(_send())
                                  : null,
                          style: IconButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor:
                                Theme.of(context).colorScheme.surface,
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
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'AI 生成内容可能不准确，请核实重要信息。',
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
          color: Theme.of(context)
              .colorScheme
              .errorContainer
              .withValues(alpha: .3),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 17,
              color: Theme.of(context).colorScheme.error,
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
}
