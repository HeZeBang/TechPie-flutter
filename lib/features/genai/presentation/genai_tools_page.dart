import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/adaptive_feedback.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_image_size.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_reference_image.dart';
import 'genai_conversation_menu.dart';
import 'genai_copy.dart';
import 'genai_demo_image.dart';
import 'genai_theme.dart';
import 'picker/genai_picker.dart';

/// Tools share the app's verified session; no independent login or credentials.
class GenAiToolsPage extends StatefulWidget {
  const GenAiToolsPage({
    super.key,
    required this.workspace,
    this.initialTab = 0,
    this.demo = false,
    this.picker,
  });
  final GenAiWorkspaceController workspace;
  final int initialTab;
  final bool demo;
  final GenAiPicker? picker;
  @override
  State<GenAiToolsPage> createState() => _GenAiToolsPageState();
}

class _GenAiToolsPageState extends State<GenAiToolsPage> {
  late final GenAiPicker _picker;
  final _references = <GenAiReferenceImage>[];
  final _referencePreviews = <GenAiReferenceImage, Uint8List>{};
  bool _pickingReference = false;
  String? _referenceError;
  final _search = TextEditingController();
  final _prompt = TextEditingController();
  final _conversations = <GenAiConversationSummary>[];
  final _images = <GenAiImageRecord>[];
  final _orders = <GenAiUsageOrder>[];
  List<Uri> _generated = const [];
  GenAiUsageSummary? _usage;
  GenAiModel? _imageModel;
  GenAiCancellation? _operation;
  GenAiCancellation? _searchCancellation;
  Timer? _searchDebounceTimer;
  GenAiFailure? _failure;
  late final int _tab;
  late final int _revision;
  bool _busy = false;
  bool _searching = false;
  bool _scopeValid = true;
  Object? _accountScope;
  bool _more = false;
  int _page = 1;
  String _query = '';
  final _imageWidth = TextEditingController(text: '1024');
  final _imageHeight = TextEditingController(text: '1024');
  String _aspectRatio = '1:1';
  String _resolution = '1K';
  bool get _customSize => _resolution == 'custom';
  String get _size => _customSize
      ? '${_imageWidth.text}x${_imageHeight.text}'
      : GenAiImageSize.presets[_aspectRatio]![_resolution]!;
  GenAiImageSize? get _parsedSize => GenAiImageSize.tryParse(_size);
  bool get _validSize => _parsedSize?.isValid ?? false;
  String _quality = 'low';
  GenAiWorkspaceController get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? GenAiPicker();
    _tab = widget.initialTab;
    _revision = _workspace.sessions.revision;
    _accountScope = _workspace.accountScope;
    _imageModel = _workspace.imageModels.firstOrNull;
    _workspace.sessions.addListener(_sessionChanged);
    _workspace.addListener(_workspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _workspaceChanged() {
    if (!mounted) return;
    _sessionChanged();
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
    if (!mounted ||
        !_scopeValid ||
        (_workspace.sessions.revision == _revision &&
            _workspace.accountScope == _accountScope)) {
      return;
    }
    _searchDebounceTimer?.cancel();
    _searchCancellation?.cancel();
    _operation?.cancel(GenAiFailureKind.accountChanged);
    setState(() {
      _scopeValid = false;
      _references.clear();
      _referencePreviews.clear();
      _referenceError = null;
      _pickingReference = false;
      _busy = false;
      _searching = false;
      _conversations.clear();
      _search.clear();
      _query = '';
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

  Future<void> _performSearch({bool more = false}) async {
    if (!_scopeValid || !mounted) return;
    _searchDebounceTimer?.cancel();
    _searchCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _searchCancellation = cancellation;
    final query = _search.text.trim();
    final append = more && query == _query;
    final page = append ? _page + 1 : 1;
    setState(() {
      _searching = true;
      if (!append) _query = query;
    });
    try {
      final data = await _workspace.listConversations(
        cancellation,
        page: page,
        query: query,
      );
      if (!mounted || cancellation.isCancelled) return;
      setState(() {
        if (!append) _conversations.clear();
        for (final record in data.records) {
          _conversations.removeWhere((item) => item.id == record.id);
          _conversations.add(record);
        }
        _more = data.hasMore;
        _page = page;
        _failure = null;
      });
    } on GenAiFailure catch (error) {
      if (mounted && !cancellation.isCancelled) {
        setState(() => _failure = error);
      }
    } catch (_) {
      if (mounted && !cancellation.isCancelled) {
        setState(
          () => _failure = const GenAiFailure(GenAiFailureKind.transport),
        );
      }
    } finally {
      if (identical(_searchCancellation, cancellation)) {
        _searchCancellation = null;
        if (mounted) setState(() => _searching = false);
      }
    }
  }

  void _onSearchChanged(String text) {
    _searchDebounceTimer?.cancel();
    _searchCancellation?.cancel();
    _searchCancellation = null;
    _searching = true;
    _searchDebounceTimer = Timer(const Duration(milliseconds: 250), () {
      if (mounted) unawaited(_performSearch());
    });
    setState(() {});
  }

  void _clearSearch() {
    _searchDebounceTimer?.cancel();
    _search.clear();
    setState(() {});
    unawaited(_performSearch());
  }

  Future<void> _load({bool more = false}) async {
    if (_tab == 0) {
      await _performSearch(more: more);
      return;
    }
    await _run((c) async {
      final page = more ? _page + 1 : 1;
      final repository = _workspace.repository;
      if (_tab == 1) {
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
  }

  Future<void> _openConversation(GenAiConversationSummary item) =>
      _run((c) async {
        final opened = await _workspace.openConversation(item.id, c);
        c.throwIfCancelled();
        if (mounted && opened) Navigator.pop(context, true);
      });

  Future<void> _delete(String id, {required bool image}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(image ? '删除图片记录？' : '删除此对话？'),
        content: Text(image ? '这将删除学校平台上的图片记录，无法撤销。' : '这将删除此对话的本机和学校记录，无法撤销。'),
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
        await _workspace.deleteConversation(id, c);
        c.throwIfCancelled();
        _conversations.removeWhere((r) => r.id == id);
        if (_workspace.groupId == id) _workspace.newConversation();
      }
    });
  }

  Future<void> _generate() async {
    final model = _imageModel;
    if (_busy ||
        _pickingReference ||
        !_scopeValid ||
        model == null ||
        _prompt.text.trim().isEmpty ||
        !_validSize) {
      return;
    }
    final request = GenAiImageRequest(
      prompt: _prompt.text.trim(),
      model: model,
      groupId: GenAiWorkspaceController.createGroupId(),
      size: _size,
      quality: _quality,
      referenceImages: _references,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('生成 1 张图片'),
        content: Text(
          '${model.name} · $_size · $_quality${request.referenceImages.isEmpty ? '' : ' · ${request.referenceImages.length} 张参考图片'}\n'
          '${widget.demo ? '本地演示使用校园测试图片，不访问学校服务，也不会扣费。' : '可能扣除学校账号额度。生成可能需要几分钟，离开页面不会保证停止服务器计费。'}',
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
    _searchDebounceTimer?.cancel();
    _searchCancellation?.cancel();
    _operation?.cancel();
    _workspace.sessions.removeListener(_sessionChanged);
    _workspace.removeListener(_workspaceChanged);
    _references.clear();
    _referencePreviews.clear();
    _search.dispose();
    _prompt.dispose();
    _imageWidth.dispose();
    _imageHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: genAiTheme(Theme.of(context)),
        child: Scaffold(
          appBar: AppBar(
            title: Text(const ['会话记录', '图片创作', '用量统计'][_tab]),
            actions: [
              IconButton(
                onPressed: _busy || _searching || !_scopeValid
                    ? null
                    : () => unawaited(_load()),
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
        ),
      );

  Widget _loadMore() => _more
      ? Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed:
                _busy || _searching ? null : () => unawaited(_load(more: true)),
            child: const Text('加载更多'),
          ),
        )
      : const SizedBox.shrink();

  Widget _history() {
    final hasSearchText = _search.text.isNotEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            enabled: _scopeValid && !_busy,
            onChanged: _onSearchChanged,
            onSubmitted: (_) {
              _searchDebounceTimer?.cancel();
              unawaited(_performSearch());
            },
            decoration: InputDecoration(
              labelText: '搜索对话',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_searching)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (hasSearchText)
                    IconButton(
                      icon: const Icon(Icons.clear, size: 20),
                      tooltip: '清除',
                      onPressed: _clearSearch,
                    ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            children: [
              if (_conversations.isEmpty && !_busy && !_searching)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: _query.isNotEmpty
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.search_off_rounded,
                                size: 48,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '未找到与「$_query」相关的会话',
                                style: const TextStyle(color: Colors.grey),
                              ),
                            ],
                          )
                        : const Text('没有会话记录'),
                  ),
                ),
              for (final item in _conversations)
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(
                    item.title.isEmpty ? '未命名对话' : item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: item.time.isEmpty
                      ? null
                      : Text(genAiHistoryTime(item.time)),
                  onTap: _busy || _searching
                      ? null
                      : () => unawaited(_openConversation(item)),
                  trailing: GenAiConversationMenu(
                    key: ValueKey(item.id),
                    workspace: _workspace,
                    conversation: item,
                    enabled: !_busy && !_searching,
                    onChanged: () => unawaited(_performSearch()),
                    onDelete: () => unawaited(_delete(item.id, image: false)),
                  ),
                ),
              _loadMore(),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _pickReferenceImage() async {
    if (_pickingReference ||
        _busy ||
        !_scopeValid ||
        _references.length >= GenAiReferenceImage.maxCount) {
      return;
    }
    setState(() {
      _pickingReference = true;
      _referenceError = null;
    });
    final workspace = _workspace;
    bool current() =>
        mounted &&
        _scopeValid &&
        identical(_workspace, workspace) &&
        workspace.sessions.revision == _revision;
    try {
      final file = await _picker.pickImage();
      if (!current() || file == null) return;
      final image = GenAiReferenceImage.fromBytes(file.name, file.bytes);
      GenAiReferenceImage.validate([..._references, image]);
      // Decode a small frame to reject damaged files before accepting a reference.
      // Flutter web codecs require a native typed array, not an unmodifiable view.
      final codec = await ui.instantiateImageCodec(
        Uint8List.fromList(image.bytes),
        targetWidth: 160,
        targetHeight: 160,
        allowUpscaling: false,
      );
      late Uint8List thumbnail;
      try {
        final frame = await codec.getNextFrame();
        try {
          final data =
              await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Image preview unavailable');
          thumbnail =
              data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (!current()) return;
      setState(() {
        _references.add(image);
        _referencePreviews[image] = thumbnail;
      });
    } on GenAiReferenceImageFailure catch (error) {
      if (!current()) return;
      setState(
        () => _referenceError = switch (error) {
          GenAiReferenceImageFailure.unsupportedFormat =>
            '请选择 PNG、JPG 或 WebP 图片。',
          GenAiReferenceImageFailure.empty => '图片为空，请选择其他文件。',
          GenAiReferenceImageFailure.tooLarge => '单张参考图片不能超过 10 MB。',
          GenAiReferenceImageFailure.tooMany => '最多添加 4 张参考图片。',
          GenAiReferenceImageFailure.totalTooLarge => '参考图片总大小不能超过 25 MB。',
        },
      );
    } catch (_) {
      if (current()) {
        setState(() => _referenceError = '无法读取图片，请选择有效的 PNG、JPG 或 WebP 图片。');
      }
    } finally {
      if (current()) setState(() => _pickingReference = false);
    }
  }

  Widget _referenceImageControls() {
    final enabled = !_busy && !_pickingReference && _scopeValid;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '参考图片（${_references.length}/4）',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            TextButton.icon(
              key: const ValueKey('genai-add-reference'),
              onPressed:
                  enabled && _references.length < GenAiReferenceImage.maxCount
                      ? () => unawaited(_pickReferenceImage())
                      : null,
              icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(_pickingReference ? '正在读取…' : '添加参考图片'),
            ),
          ],
        ),
        const Text(
          '可选 · 最多 4 张，单张 10 MB，总计 25 MB。仅在开始生成时发送。',
          style: TextStyle(fontSize: 12),
        ),
        if (_references.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (var index = 0; index < _references.length; index++)
                SizedBox(
                  width: 112,
                  child: Column(
                    children: [
                      Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.memory(
                              _referencePreviews[_references[index]]!,
                              key: ValueKey('genai-reference-preview-$index'),
                              width: 112,
                              height: 88,
                              fit: BoxFit.cover,
                              cacheWidth: 224,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 112,
                                height: 88,
                                child: Icon(Icons.broken_image_outlined),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: IconButton.filled(
                              key: ValueKey('genai-remove-reference-$index'),
                              tooltip: '移除参考图片 ${_references[index].name}',
                              icon: const Icon(Icons.close, size: 16),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black54,
                                foregroundColor: Colors.white,
                                minimumSize: const Size(36, 36),
                              ),
                              onPressed: enabled
                                  ? () => setState(() {
                                        _referencePreviews.remove(
                                          _references.removeAt(index),
                                        );
                                        _referenceError = null;
                                      })
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _references[index].name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
        if (_referenceError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _referenceError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }

  void _selectAspectRatio(String ratio) {
    final previousSize = _parsedSize;
    setState(() {
      _aspectRatio = ratio;
      if (ratio == 'custom') {
        _resolution = 'custom';
        if (previousSize != null) _setCustomDimensions(previousSize);
      } else {
        final options = GenAiImageSize.presets[ratio]!;
        if (!options.containsKey(_resolution)) _resolution = '1K';
        _setCustomDimensions(GenAiImageSize.tryParse(_size)!);
      }
    });
  }

  void _setCustomDimensions(GenAiImageSize size) {
    _imageWidth.text = '${size.width}';
    _imageHeight.text = '${size.height}';
  }

  void _editDimension(String value, {required bool width}) {
    setState(() {
      if (_aspectRatio == 'custom') return;
      final amount = int.tryParse(value);
      final other = width ? _imageHeight : _imageWidth;
      if (amount == null || amount <= 0) {
        other.clear();
        return;
      }
      final ratio = _aspectRatio.split(':').map(int.parse).toList();
      other.text =
          '${(amount * (width ? ratio[1] / ratio[0] : ratio[0] / ratio[1])).round()}';
    });
  }

  Widget _imageSizeControls() {
    final enabled = !_busy && _scopeValid;
    final presets = GenAiImageSize.presets[_aspectRatio];
    Widget dimension(TextEditingController controller, bool width) => SizedBox(
          width: 180,
          child: TextField(
            key: ValueKey(width ? 'genai-image-width' : 'genai-image-height'),
            controller: controller,
            enabled: enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: InputDecoration(labelText: width ? '宽度（px）' : '高度（px）'),
            onChanged: (value) => _editDimension(value, width: width),
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<String>(
                key: const ValueKey('genai-image-ratio'),
                isExpanded: true,
                initialValue: _aspectRatio,
                decoration: const InputDecoration(labelText: '画面比例'),
                items: [
                  for (final ratio in GenAiImageSize.presets.keys)
                    DropdownMenuItem(
                      value: ratio,
                      child: Text(ratio == '1:1' ? '1:1 · 正方形' : ratio),
                    ),
                  const DropdownMenuItem(value: 'custom', child: Text('自定义比例')),
                ],
                onChanged:
                    enabled ? (value) => _selectAspectRatio(value!) : null,
              ),
            ),
            if (presets != null)
              SizedBox(
                width: 260,
                child: DropdownButtonFormField<String>(
                  key: const ValueKey('genai-image-resolution'),
                  isExpanded: true,
                  initialValue: _resolution,
                  decoration: const InputDecoration(labelText: '分辨率'),
                  items: [
                    for (final entry in presets.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(
                          '${entry.key} · ${entry.value.replaceAll('x', ' × ')}',
                        ),
                      ),
                    const DropdownMenuItem(
                      value: 'custom',
                      child: Text('自定义分辨率'),
                    ),
                  ],
                  onChanged: enabled
                      ? (value) => setState(() {
                            final previous = _parsedSize;
                            _resolution = value!;
                            if (_customSize && previous != null) {
                              _setCustomDimensions(previous);
                            }
                          })
                      : null,
                ),
              ),
            SizedBox(
              width: 150,
              child: DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: _quality,
                decoration: const InputDecoration(labelText: '质量'),
                items: const [
                  DropdownMenuItem(value: 'low', child: Text('普通')),
                  DropdownMenuItem(value: 'medium', child: Text('标准')),
                  DropdownMenuItem(value: 'high', child: Text('高清')),
                ],
                onChanged: enabled
                    ? (value) => setState(() => _quality = value!)
                    : null,
              ),
            ),
          ],
        ),
        if (_customSize) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              dimension(_imageWidth, true),
              dimension(_imageHeight, false),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _aspectRatio == 'custom'
                ? '自由设置宽高，像素总数须为 655,360–8,294,400。'
                : '保持 $_aspectRatio 比例，修改一边会自动调整另一边。',
          ),
          if (!_validSize)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '请输入正整数宽高，像素总数须为 655,360–8,294,400。',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
        ],
        if (_validSize && _parsedSize!.isExperimental)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text('超2K分辨率属实验性质，效果可能不稳定。'),
          ),
      ],
    );
  }

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
            initialValue: _imageModel,
            isExpanded: true,
            decoration: const InputDecoration(labelText: '生图模型'),
            items: models
                .map(
                  (m) => DropdownMenuItem(
                    value: m,
                    child: Text(
                      '${m.name} · ${widget.demo ? '本地测试' : m.payType == 'FREE' ? '免费' : '扣除额度'}',
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
          ),
        ),
        const SizedBox(height: 12),
        _referenceImageControls(),
        const SizedBox(height: 16),
        _imageSizeControls(),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('genai-image-generate'),
          onPressed: _busy ||
                  _pickingReference ||
                  !_scopeValid ||
                  _imageModel == null ||
                  _prompt.text.trim().isEmpty ||
                  !_validSize
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
                  ? const GenAiDemoImage()
                  : Image.network(
                      _workspace.repository
                          .imageDisplayUri(uri.toString())
                          .toString(),
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
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('No image URL handler');
      }
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(context: context, message: '无法打开图片');
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
          Text(
            widget.demo
                ? '以下为本地测试数据，不代表学校账号的实际额度。'
                : '以下数据来自学校平台。额度与 Token 分开显示，结算可能延迟。',
          ),
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
