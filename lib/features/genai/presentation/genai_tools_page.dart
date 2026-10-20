import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_copy.dart';

/// Tools share the app's verified session; no independent login or credentials.
class GenAiToolsPage extends StatefulWidget {
  const GenAiToolsPage({
    super.key,
    required this.workspace,
    this.initialTab = 0,
    this.demo = false,
  });
  final GenAiWorkspaceController workspace;
  final int initialTab;
  final bool demo;
  @override
  State<GenAiToolsPage> createState() => _GenAiToolsPageState();
}

class _GenAiToolsPageState extends State<GenAiToolsPage> {
  final _search = TextEditingController();
  final _prompt = TextEditingController();
  final _conversations = <GenAiConversationSummary>[];
  final _images = <GenAiImageRecord>[];
  final _orders = <GenAiUsageOrder>[];
  List<Uri> _generated = const [];
  GenAiUsageSummary? _usage;
  GenAiModel? _imageModel;
  GenAiCancellation? _operation;
  GenAiFailure? _failure;
  late final int _tab;
  late final int _revision;
  bool _busy = false;
  bool _scopeValid = true;
  bool _more = false;
  int _page = 1;
  String _query = '';
  String _size = '1024x1024';
  String _quality = 'low';
  GenAiWorkspaceController get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab;
    _revision = _workspace.sessions.revision;
    _imageModel = _workspace.imageModels.firstOrNull;
    _workspace.sessions.addListener(_sessionChanged);
    _workspace.addListener(_workspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _workspaceChanged() {
    if (!mounted) return;
    final previous = _imageModel;
    _imageModel = (previous != null
            ? _workspace.imageModels
                .where(
                  (m) =>
                      m.aiType == previous.aiType &&
                      m.rootAiType == previous.rootAiType,
                )
                .firstOrNull
            : null) ??
        _workspace.imageModels.firstOrNull;
    setState(() {});
  }

  void _sessionChanged() {
    if (_workspace.sessions.revision == _revision || !mounted) return;
    _operation?.cancel(GenAiFailureKind.accountChanged);
    setState(() {
      _scopeValid = false;
      _busy = false;
      _conversations.clear();
      _images.clear();
      _orders.clear();
      _generated = const [];
      _usage = null;
      _prompt.clear();
      _failure = const GenAiFailure(GenAiFailureKind.accountChanged);
    });
  }

  Future<void> _run(Future<void> Function(GenAiCancellation) action) async {
    if (_busy || !_scopeValid || !mounted) return;
    final operation = GenAiCancellation();
    _operation = operation;
    setState(() {
      _busy = true;
      _failure = null;
    });
    try {
      await action(operation);
    } on GenAiFailure catch (error) {
      if (mounted && !operation.isCancelled) setState(() => _failure = error);
    } catch (_) {
      if (mounted && !operation.isCancelled) {
        setState(
          () => _failure = const GenAiFailure(GenAiFailureKind.transport),
        );
      }
    } finally {
      operation.cancel();
      if (identical(_operation, operation)) _operation = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load({bool more = false}) => _run((c) async {
        final page = more ? _page + 1 : 1;
        final repository = _workspace.repository;
        if (_tab == 0) {
          if (!more) _query = _search.text.trim();
          final data =
              await repository.listConversations(c, page: page, query: _query);
          c.throwIfCancelled();
          if (!more) _conversations.clear();
          _conversations.addAll(data.records);
          _more = data.hasMore;
        } else if (_tab == 1) {
          final data = await repository.listImages(c, page: page);
          c.throwIfCancelled();
          if (!more) _images.clear();
          _images.addAll(data.records);
          _more = data.hasMore;
        } else {
          if (!more) _usage = await repository.usageSummary(c);
          final data = await repository.usageOrders(c, page: page);
          c.throwIfCancelled();
          if (!more) _orders.clear();
          _orders.addAll(data.records);
          _more = data.hasMore;
        }
        _page = page;
      });

  Future<void> _openConversation(GenAiConversationSummary item) =>
      _run((c) async {
        await _workspace.openConversation(item.id, c);
        c.throwIfCancelled();
        if (mounted) Navigator.pop(context, true);
      });

  Future<void> _delete(String id, {required bool image}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(image ? '删除图片记录？' : '删除此对话？'),
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
    await _run((c) async {
      if (image) {
        await _workspace.repository.deleteImage(id, c);
        c.throwIfCancelled();
        _images.removeWhere((r) => r.id == id);
      } else {
        await _workspace.repository.deleteConversation(id, c);
        c.throwIfCancelled();
        _conversations.removeWhere((r) => r.id == id);
        if (_workspace.groupId == id) _workspace.newConversation();
      }
    });
  }

  Future<void> _generate() async {
    final model = _imageModel;
    if (_busy || model == null || _prompt.text.trim().isEmpty) return;
    final request = GenAiImageRequest(
      prompt: _prompt.text.trim(),
      model: model,
      groupId: GenAiWorkspaceController.createGroupId(),
      size: _size,
      quality: _quality,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成 1 张图片'),
        content: Text(
          '${model.name} · $_size · $_quality\n可能扣除学校账号额度。生成可能需要几分钟，离开页面不会保证停止服务器计费。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始生成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run((c) async {
      final images = await _workspace.repository.generateImage(request, c);
      c.throwIfCancelled();
      _generated = images;
      try {
        final data = await _workspace.repository.listImages(c, page: 1);
        c.throwIfCancelled();
        _images.clear();
        _images.addAll(data.records);
        _more = data.hasMore;
        _page = 1;
      } catch (_) {
        // Best-effort history refresh
      }
    });
  }

  @override
  void dispose() {
    _operation?.cancel();
    _workspace.sessions.removeListener(_sessionChanged);
    _workspace.removeListener(_workspaceChanged);
    _search.dispose();
    _prompt.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(const ['会话记录', '图片创作', '用量统计'][_tab]),
          actions: [
            IconButton(
              onPressed:
                  _busy || !_scopeValid ? null : () => unawaited(_load()),
              icon: const Icon(Icons.refresh),
              tooltip: '刷新',
            ),
          ],
        ),
        body: Column(
          children: [
            if (widget.demo)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('本地演示数据 · 不访问校园服务'),
              ),
            if (_busy) const LinearProgressIndicator(),
            if (_failure != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(genAiFailureText(_failure!)),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: _tab == 0
                      ? _history()
                      : _tab == 1
                          ? _imageStudio()
                          : _statistics(),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _loadMore() => _more
      ? Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: _busy ? null : () => unawaited(_load(more: true)),
            child: const Text('加载更多'),
          ),
        )
      : const SizedBox.shrink();

  Widget _history() => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _search,
              enabled: !_busy,
              onSubmitted: (_) => unawaited(_load()),
              decoration: InputDecoration(
                labelText: '搜索对话',
                suffixIcon: IconButton(
                  onPressed: _busy ? null : () => unawaited(_load()),
                  icon: const Icon(Icons.search),
                  tooltip: '搜索',
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (_conversations.isEmpty && !_busy)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text('没有会话记录'),
                  ),
                for (final item in _conversations)
                  ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(
                      item.title.isEmpty ? '未命名对话' : item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: item.time.isEmpty ? null : Text(item.time),
                    onTap:
                        _busy ? null : () => unawaited(_openConversation(item)),
                    trailing: IconButton(
                      tooltip: '删除对话',
                      onPressed: _busy
                          ? null
                          : () => unawaited(_delete(item.id, image: false)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ),
                _loadMore(),
              ],
            ),
          ),
        ],
      );

  Widget _imageStudio() {
    final models = _workspace.imageModels;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          '描述你想创作的图片',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        if (models.isEmpty)
          const Text('当前模型目录没有可用的生图模型。')
        else
          DropdownButtonFormField<GenAiModel>(
            key: const ValueKey('genai-image-model'),
            value: _imageModel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '生图模型'),
            items: models
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      '${m.name} · ${m.payType == 'FREE' ? '免费' : '扣除额度'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged:
                _busy ? null : (model) => setState(() => _imageModel = model),
          ),
        const SizedBox(height: 16),
        TextField(
          key: const ValueKey('genai-image-prompt'),
          controller: _prompt,
          enabled: !_busy,
          minLines: 3,
          maxLines: 6,
          onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(
            labelText: '画面描述',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 20,
          runSpacing: 12,
          children: [
            SizedBox(
              width: 200,
              child: DropdownButtonFormField<String>(
                value: _size,
                decoration: const InputDecoration(labelText: '尺寸'),
                items: const [
                  '1024x1024',
                  '1024x768',
                  '768x1024',
                  '1136x640',
                  '640x1136',
                  '1536x1024',
                  '1024x1536',
                  '2048x2048',
                ]
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _busy ? null : (s) => setState(() => _size = s!),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                value: _quality,
                decoration: const InputDecoration(labelText: '质量'),
                items: const ['low', 'medium', 'high']
                    .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                    .toList(),
                onChanged: _busy ? null : (s) => setState(() => _quality = s!),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ||
                  !_scopeValid ||
                  _imageModel == null ||
                  _prompt.text.trim().isEmpty
              ? null
              : () => unawaited(_generate()),
          icon: const Icon(Icons.auto_awesome),
          label: Text(_busy ? '处理中…' : '生成 1 张图片'),
        ),
        if (_generated.isNotEmpty) ...[
          const SizedBox(height: 20),
          const Text('本次生成'),
          for (final uri in _generated) _image(uri),
        ],
        const SizedBox(height: 28),
        const Text(
          '图片历史',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        if (_images.isEmpty && !_busy)
          const Padding(padding: EdgeInsets.all(20), child: Text('没有图片记录')),
        for (final record in _images)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(record.prompt)),
                      IconButton(
                        tooltip: '删除图片记录',
                        onPressed: _busy
                            ? null
                            : () => unawaited(_delete(record.id, image: true)),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  for (final uri in record.images) _image(uri),
                ],
              ),
            ),
          ),
        _loadMore(),
      ],
    );
  }

  Widget _image(Uri uri) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 460),
              child: widget.demo &&
                      (uri.path.contains('techpie-preview') ||
                          uri.host == 'demo')
                  ? const AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: Color(0xffe2f1ed),
                        child: Center(child: Text('本地图片预览 · 演示')),
                      ),
                    )
                  : Image.network(
                      uri.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('图片暂时无法预览，可在浏览器中打开。'),
                      ),
                    ),
            ),
            TextButton.icon(
              onPressed: () => unawaited(_openImage(uri)),
              icon: const Icon(Icons.open_in_new),
              label: const Text('打开原图'),
            ),
          ],
        ),
      );

  Future<void> _openImage(Uri uri) async {
    if (widget.demo &&
        (uri.path.contains('techpie-preview') || uri.host == 'demo')) {
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法打开图片')));
      }
    }
  }

  Widget _statistics() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            '账号额度',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('以下数据来自学校平台。额度与 Token 分开显示，结算可能延迟。'),
          for (final quota in _usage?.quotas ?? <GenAiQuota>[])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      quota.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '剩余 ${quota.remaining}    已用 ${quota.used}    总额 ${quota.total}',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 24),
          const Text(
            '消费明细',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          if (_orders.isEmpty && !_busy)
            const Padding(padding: EdgeInsets.all(20), child: Text('没有消费记录')),
          for (final order in _orders)
            Card(
              child: ListTile(
                title: Text(order.model),
                subtitle: Text(
                  '${order.time}\n输入 ${order.inputTokens} · 输出 ${order.outputTokens} · 图片 ${order.imageTokens} Token',
                ),
                trailing: Text('${order.used} 额度'),
                isThreeLine: true,
              ),
            ),
          _loadMore(),
        ],
      );
}
