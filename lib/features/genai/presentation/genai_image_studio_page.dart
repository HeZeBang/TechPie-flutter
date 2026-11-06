import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/genai_image_studio_controller.dart';
import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_contract.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_image_caption.dart';
import '../domain/genai_image_size.dart';
import '../domain/genai_platform_contract.dart';
import '../domain/genai_reference_image.dart';
import 'genai_copy.dart';
import 'genai_icons.dart';
import 'genai_image_dimensions.dart';
import 'genai_image_gallery.dart';
import 'genai_image_viewer.dart';
import 'genai_theme.dart';
import 'picker/genai_picker.dart';

/// Image creation and gallery using the workspace's verified campus session.
class GenAiImageStudioPage extends StatefulWidget {
  const GenAiImageStudioPage({
    super.key,
    required this.workspace,
    this.picker,
    this.embedded = false,
    this.stageWidth,
  });

  final GenAiWorkspaceController workspace;
  final GenAiPicker? picker;

  /// Width of the surface the workspace actually occupies (window/sidebar
  /// aware). Layout breakpoints follow this; null falls back to the window
  /// width when the page is shown on its own.
  final double? stageWidth;

  /// Embedded inside the workspace, which already provides the header.
  final bool embedded;
  @override
  State<GenAiImageStudioPage> createState() => _GenAiImageStudioPageState();
}

class _GenAiImageStudioPageState extends State<GenAiImageStudioPage> {
  static const _qualityLabels = {'low': '普通', 'medium': '标准', 'high': '高清'};
  static const _customResolution = 'custom';

  late final GenAiPicker _picker;
  late final GenAiImageDraft _draft;
  List<GenAiReferenceImage> get _references => _draft.references;
  Map<GenAiReferenceImage, Uint8List> get _referencePreviews => _draft.previews;
  bool _pickingReference = false;
  String? _referenceError;
  final _prompt = TextEditingController();
  final _studioScroll = ScrollController();
  final _parameterScroll = ScrollController(keepScrollOffset: false);
  final _images = <GenAiImageRecord>[];
  GenAiModel? get _imageModel => _draft.model;
  set _imageModel(GenAiModel? value) => _draft.model = value;
  GenAiCancellation? _operation;
  GenAiFailure? _failure;
  late final int _revision;
  bool _busy = false;
  bool _loading = false;
  GenAiFailure? _loadFailure;
  GenAiCancellation? _loadOperation;
  int _imageCompletion = 0;
  bool get _generating => _workspace.imageStudio.generating;
  bool get _currentScope =>
      mounted &&
      _scopeValid &&
      _accountScope == _workspace.accountScope &&
      _revision == _workspace.sessions.revision;
  bool get _editingBlocked => _busy || _generating || !_currentScope;
  bool _scopeValid = true;
  Object? _accountScope;
  bool _more = false;
  int _page = 1;
  final _customWidth = TextEditingController(text: '1024');
  final _customHeight = TextEditingController(text: '1024');
  String get _aspectRatio => _draft.aspectRatio;
  set _aspectRatio(String value) => _draft.aspectRatio = value;
  String get _resolution => _draft.resolution;
  set _resolution(String value) => _draft.resolution = value;
  bool _linked = true;
  bool get _customSize => _resolution == _customResolution;

  /// A preset request is named by the ratio and resolution alone; free-form
  /// dimensions only participate while the custom resolution is selected.
  String get _size {
    if (!_customSize) {
      final preset = GenAiImageSize.presets[_aspectRatio]?[_resolution];
      if (preset != null) return preset;
    }
    return '${_customWidth.text}x${_customHeight.text}';
  }

  String get _resolutionLabel => _customSize ? '自定义' : _resolution;
  GenAiImageSize? get _parsedSize => GenAiImageSize.tryParse(_size);
  bool get _validSize => _parsedSize?.isValid ?? false;
  String get _quality => _draft.quality;
  set _quality(String value) => _draft.quality = value;
  GenAiWorkspaceController get _workspace => widget.workspace;

  @override
  void initState() {
    super.initState();
    _picker = widget.picker ?? GenAiPicker();
    _revision = _workspace.sessions.revision;
    _accountScope = _workspace.accountScope;
    final draft = _draft = _workspace.imageStudio.draft;
    final restoreRatioFromDimensions = !GenAiImageSize.presets.containsKey(draft.aspectRatio);
    _prompt.text = draft.prompt;
    _customWidth.text = draft.width;
    _customHeight.text = draft.height;
    _aspectRatio =
        GenAiImageSize.presets.containsKey(draft.aspectRatio) ? draft.aspectRatio : '1:1';
    final presets = GenAiImageSize.presets[_aspectRatio]!;
    _resolution = draft.resolution == _customResolution || presets.containsKey(draft.resolution)
        ? draft.resolution
        : '1K';
    _quality = _qualityLabels.containsKey(draft.quality) ? draft.quality : 'low';
    // Restore a valid custom draft; preset-to-custom transitions use the
    // dimensions currently shown by the selected preset.
    final restoredCustom = GenAiImageSize.tryParse(
      '${_customWidth.text}x${_customHeight.text}',
    );
    if (restoredCustom == null || !restoredCustom.isValid) {
      final seed = GenAiImageSize.tryParse(presets[_customSize ? '1K' : _resolution]!)!;
      _setCustomDimensions(seed);
    }
    if (restoreRatioFromDimensions) {
      final width = int.tryParse(_customWidth.text);
      final height = int.tryParse(_customHeight.text);
      if (width != null && height != null && width > 0 && height > 0) {
        _aspectRatio = _ratioFor(width, height);
        final options = GenAiImageSize.presets[_aspectRatio];
        if (options == null) {
          _resolution = _customResolution;
        } else if (!_customSize && !options.containsKey(_resolution)) {
          _resolution = '1K';
        }
      }
    }
    _imageModel = _workspace.imageModels
            .where(
              (m) => m.aiType == draft.model?.aiType && m.rootAiType == draft.model?.rootAiType,
            )
            .firstOrNull ??
        _workspace.imageModels.firstOrNull;
    _imageCompletion = _workspace.imageStudio.completion;
    _workspace.imageStudio.addListener(_imageChanged);
    _workspace.sessions.addListener(_sessionChanged);
    _workspace.addListener(_workspaceChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  void _saveDraft() {
    if (!_scopeValid ||
        _accountScope != _workspace.accountScope ||
        _revision != _workspace.sessions.revision) {
      return;
    }
    final draft = _workspace.imageStudio.draft;
    draft.prompt = _prompt.text;
    draft.width = _customWidth.text;
    draft.height = _customHeight.text;
  }

  void _imageChanged() {
    if (!mounted) return;
    _sessionChanged();
    final completion = _workspace.imageStudio.completion;
    if (_imageCompletion != completion) {
      _imageCompletion = completion;
      if (_scopeValid) unawaited(_load());
    }
    setState(() {});
  }

  void _workspaceChanged() {
    if (!mounted) return;
    _sessionChanged();
    final previous = _imageModel;
    _imageModel = (previous != null
            ? _workspace.imageModels
                .where(
                  (m) => m.aiType == previous.aiType && m.rootAiType == previous.rootAiType,
                )
                .firstOrNull
            : null) ??
        _workspace.imageModels.firstOrNull;
    setState(() {});
  }

  void _sessionChanged() {
    if (!mounted ||
        !_scopeValid ||
        (_workspace.sessions.revision == _revision && _workspace.accountScope == _accountScope)) {
      return;
    }
    _operation?.cancel(GenAiFailureKind.accountChanged);
    _loadOperation?.cancel(GenAiFailureKind.accountChanged);
    setState(() {
      _scopeValid = false;
      _references.clear();
      _referencePreviews.clear();
      _referenceError = null;
      _pickingReference = false;
      _busy = false;
      _loading = false;
      _loadFailure = null;
      _images.clear();
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

  Future<void> _load({bool more = false}) async {
    if (!_scopeValid || !mounted || _busy) return;
    _loadOperation?.cancel();
    final c = GenAiCancellation();
    _loadOperation = c;
    setState(() {
      _loading = true;
      _loadFailure = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final repository = _workspace.repository;
      final data = await repository.listImages(c, page: page);
      c.throwIfCancelled();
      if (!more) _images.clear();
      for (final record in data.records) {
        _images.removeWhere((item) => item.id == record.id);
        _images.add(record);
      }
      _workspace.imageStudio.reconcile(_images);
      _more = data.hasMore;
      _page = page;
    } on GenAiFailure catch (error) {
      if (!c.isCancelled && mounted) _loadFailure = error;
    } catch (_) {
      if (!c.isCancelled && mounted) {
        _loadFailure = const GenAiFailure(GenAiFailureKind.transport);
      }
    } finally {
      if (identical(_loadOperation, c)) {
        _loadOperation = null;
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteImage(String id) async {
    if (!_currentScope || _busy) return;
    final confirmed = await genAiShowDialog<bool>(
      context: context,
      builder: (dialogContext) => GenAiDialogFrame(
        insetPadding: EdgeInsets.symmetric(
          horizontal: _compactDialog(dialogContext) ? 12 : 24,
          vertical: 24,
        ),
        shape: _dialogShape(_compactDialog(dialogContext)),
        title: const Text('删除图片记录？'),
        content: const Text('这将删除学校平台上的图片记录，无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !_currentScope) return;
    await _run((c) async {
      // A pre-deletion history snapshot must not resurrect the removed card.
      _loadOperation?.cancel();
      _loadOperation = null;
      _loading = false;
      await _workspace.repository.deleteImage(id, c);
      c.throwIfCancelled();
      _images.removeWhere((r) => r.id == id);
    });
  }

  Future<void> _generate() async {
    final model = _imageModel;
    if (_editingBlocked ||
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
    final confirmed = await genAiShowDialog<bool>(
      context: context,
      builder: (dialogContext) => GenAiDialogFrame(
        insetPadding: EdgeInsets.symmetric(
          horizontal: _compactDialog(dialogContext) ? 12 : 24,
          vertical: 24,
        ),
        shape: _dialogShape(_compactDialog(dialogContext)),
        title: const Text('生成 1 张图片'),
        content: Text(
          '${model.name} · $_size · ${_qualityLabels[_quality] ?? _quality}'
          '${request.referenceImages.isEmpty ? '' : ' · ${request.referenceImages.length} 张参考图片'}\n'
          '可能扣除学校账号额度。生成可能需要几分钟，可离开此页面，稍后回来查看结果。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('生成'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    if (!_scopeValid || _editingBlocked) return;
    _saveDraft();
    await _workspace.imageStudio.generate(request);
  }

  @override
  void dispose() {
    _saveDraft();
    _workspace.imageStudio.removeListener(_imageChanged);
    _loadOperation?.cancel();
    _operation?.cancel();
    _workspace.sessions.removeListener(_sessionChanged);
    _workspace.removeListener(_workspaceChanged);
    _prompt.dispose();
    _studioScroll.dispose();
    _parameterScroll.dispose();
    _customWidth.dispose();
    _customHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Theme(
        data: genAiTheme(Theme.of(context)),
        child: widget.embedded
            ? _content()
            : Scaffold(
                appBar: AppBar(
                  title: const Text('图片创作'),
                  actions: [_refreshButton()],
                ),
                body: SafeArea(top: false, child: _content()),
              ),
      );

  Widget _refreshButton() => IconButton(
        onPressed: _busy || _loading || !_currentScope ? null : () => unawaited(_load()),
        icon: const GenAiIcon(GenAiGlyph.retry, size: 20),
        tooltip: '刷新',
      );

  Widget _content() => Column(
        children: [
          SizedBox(
            height: 2,
            child: _busy || _loading ? const LinearProgressIndicator() : null,
          ),
          if (_failure != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(genAiFailureText(_failure!)),
            ),
          Expanded(child: _imageStudio()),
        ],
      );

  Widget _loadError() => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(genAiFailureText(_loadFailure!)),
            TextButton.icon(
              onPressed: _loading || !_scopeValid ? null : () => unawaited(_load()),
              icon: const GenAiIcon(GenAiGlyph.retry),
              label: const Text('重试加载'),
            ),
          ],
        ),
      );

  Widget _loadMore() => _more
      ? Padding(
          padding: const EdgeInsets.all(16),
          child: OutlinedButton(
            onPressed: _busy || _loading ? null : () => _load(more: true),
            child: const Text('加载更多'),
          ),
        )
      : const SizedBox.shrink();

  Future<bool> _pickReferenceImage({Uri? uri}) async {
    if (_pickingReference ||
        _editingBlocked ||
        !_scopeValid ||
        _references.length >= GenAiReferenceImage.maxCount) {
      return false;
    }
    setState(() {
      _pickingReference = true;
      _referenceError = null;
    });
    final workspace = _workspace;
    bool current() => _currentScope && identical(_workspace, workspace);
    Dio? client;
    try {
      final GenAiPickedFile? file;
      if (uri == null) {
        file = await _picker.pickImage();
      } else {
        client = Dio(
          BaseOptions(
            connectTimeout: const Duration(seconds: 20),
            receiveTimeout: const Duration(seconds: 60),
          ),
        );
        final response = await client.get<List<int>>(
          workspace.repository.imageDisplayUri(uri.toString()).toString(),
          options: Options(responseType: ResponseType.bytes),
        );
        if (!current()) return false;
        file = GenAiPickedFile(
          name: uri.pathSegments.lastOrNull ?? 'image.png',
          bytes: response.data ?? const [],
        );
      }
      if (!current() || file == null) return false;
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
          final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
          if (data == null) throw StateError('Image preview unavailable');
          thumbnail = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (!current()) return false;
      GenAiReferenceImage.validate([..._references, image]);
      setState(() {
        _references.add(image);
        _referencePreviews[image] = thumbnail;
      });
      _saveDraft();
      return true;
    } on GenAiReferenceImageFailure catch (error) {
      if (!current()) return false;
      setState(
        () => _referenceError = switch (error) {
          GenAiReferenceImageFailure.unsupportedFormat => '请选择 PNG、JPG 或 WebP 图片。',
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
      client?.close(force: true);
      if (current()) setState(() => _pickingReference = false);
    }
    return false;
  }

  Widget _referenceImageControls() {
    final enabled = !_editingBlocked && !_pickingReference;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const ValueKey('genai-add-reference'),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
            textStyle: const TextStyle(fontSize: 12),
            padding: const EdgeInsets.symmetric(vertical: 7),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: enabled && _references.length < GenAiReferenceImage.maxCount
              ? () => unawaited(_pickReferenceImage())
              : null,
          icon: _pickingReference
              ? const SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const GenAiIcon(GenAiGlyph.plus, size: 14),
          label: Text(_pickingReference ? '正在读取…' : '参考图片'),
        ),
        if (_references.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var index = 0; index < _references.length; index++)
                SizedBox(
                  width: 50,
                  height: 50,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: Image.memory(
                          _referencePreviews[_references[index]]!,
                          key: ValueKey('genai-reference-preview-$index'),
                          width: 50,
                          height: 50,
                          fit: BoxFit.cover,
                          cacheWidth: 100,
                          errorBuilder: (_, __, ___) => const SizedBox(
                            width: 50,
                            height: 50,
                            child: GenAiIcon(GenAiGlyph.image),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: IconButton.filled(
                          key: ValueKey('genai-remove-reference-$index'),
                          tooltip: '移除参考图片 ${_references[index].name}',
                          icon: const GenAiIcon(GenAiGlyph.close, size: 12),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black54,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.zero,
                            minimumSize: const Size(20, 20),
                            maximumSize: const Size(20, 20),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          onPressed: enabled
                              ? () => setState(() {
                                    _referencePreviews.remove(_references.removeAt(index));
                                    _referenceError = null;
                                  })
                              : null,
                        ),
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

  String _ratioFor(int width, int height) {
    for (final entry in GenAiImageSize.presets.entries) {
      final sample = GenAiImageSize.tryParse(entry.value.values.first)!;
      if (sample.width * height == sample.height * width) return entry.key;
    }
    final divisor = width.gcd(height);
    return '${width ~/ divisor}:${height ~/ divisor}';
  }

  /// Parses a `width:height` ratio into its two positive sides. A malformed,
  /// non-positive or multi-part value is invalid and yields null.
  (int, int)? _ratioValues(String ratio) {
    final sides = ratio.split(':').map(int.tryParse).toList();
    if (sides.length != 2 ||
        sides[0] == null ||
        sides[1] == null ||
        sides[0]! <= 0 ||
        sides[1]! <= 0) {
      return null;
    }
    return (sides[0]!, sides[1]!);
  }

  String _orientationOf(String ratio) => GenAiImageDraft.orientationOf(ratio);

  (int, int)? _ratioSides() => _ratioValues(_aspectRatio);

  String get _parameterSummary =>
      '$_aspectRatio · ${_size.replaceAll('x', ' × ')} · ${_qualityLabels[_quality] ?? _quality}';

  void _alignCustomSize() {
    if (!_customSize) return;
    final ratio = _ratioSides();
    final width = int.tryParse(_customWidth.text);
    if (ratio != null && width != null && width > 0) {
      _customHeight.text = '${(width * ratio.$2 / ratio.$1).round()}';
    }
  }

  void _selectOrientation(String orientation, {VoidCallback? notify}) {
    setState(() {
      _draft.selectOrientation(orientation);
      _alignCustomSize();
    });
    notify?.call();
  }

  void _selectAspectRatio(String ratio, {VoidCallback? notify}) {
    setState(() {
      _draft.selectAspectRatio(ratio);
      _alignCustomSize();
    });
    notify?.call();
  }

  void _selectResolution(String resolution, {VoidCallback? notify}) {
    setState(() {
      final previousSize = GenAiImageSize.tryParse(_size);
      final wasCustom = _customSize;
      _resolution = resolution;
      if (_customSize && !wasCustom && previousSize != null) {
        _setCustomDimensions(previousSize);
      }
    });
    notify?.call();
  }

  void _selectQuality(String quality, {VoidCallback? notify}) {
    setState(() => _quality = quality);
    notify?.call();
  }

  void _toggleLinked({VoidCallback? notify}) {
    setState(() {
      _linked = !_linked;
      if (!_linked) return;
      final ratio = _ratioSides();
      if (ratio == null) return;
      final width = int.tryParse(_customWidth.text);
      final height = int.tryParse(_customHeight.text);
      if (width != null && width > 0) {
        _customHeight.text = '${math.max(1, (width * ratio.$2 / ratio.$1).round())}';
      } else if (height != null && height > 0) {
        _customWidth.text = '${math.max(1, (height * ratio.$1 / ratio.$2).round())}';
      }
    });
    notify?.call();
  }

  void _setCustomDimensions(GenAiImageSize size) {
    _customWidth.text = '${size.width}';
    _customHeight.text = '${size.height}';
  }

  void _editDimension(String value, {required bool width, VoidCallback? notify}) {
    setState(() {
      if (!_linked) {
        final w = int.tryParse(_customWidth.text);
        final h = int.tryParse(_customHeight.text);
        if (w != null && h != null && w > 0 && h > 0) _aspectRatio = _ratioFor(w, h);
        return;
      }
      final amount = int.tryParse(value);
      final other = width ? _customHeight : _customWidth;
      if (amount == null || amount <= 0) {
        other.clear();
        return;
      }
      final ratio = _ratioSides();
      if (ratio == null) return;
      final scaled = width ? amount * ratio.$2 / ratio.$1 : amount * ratio.$1 / ratio.$2;
      other.text = '${scaled.round()}';
    });
    notify?.call();
  }

  bool _compactDialog(BuildContext context) => MediaQuery.sizeOf(context).width <= 600;

  ShapeBorder _dialogShape(bool compact) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
      );

  InputDecoration _studioDecoration({String? hint, bool error = false}) {
    final colors = Theme.of(context).colorScheme;
    final line = error ? colors.error : colors.outlineVariant;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: BorderSide(color: line),
    );
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: error ? colors.error : colors.primary),
      ),
    );
  }

  Widget _studioField(String label, Widget control) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          control,
        ],
      );

  Widget _studioSelect<T>({
    required ValueKey<String> key,
    required T? value,
    required List<(T, String)> items,
    required ValueChanged<T?>? onChanged,
    String? selectedLabel,
    bool compact = false,
  }) {
    final palette = GenAiPalette.of(context);
    final textStyle = Theme.of(context).textTheme.bodyMedium!.copyWith(
          fontSize: 14,
          height: 1.4,
          color: onChanged == null ? palette.muted : palette.text,
        );
    final label = selectedLabel ?? items.where((item) => item.$1 == value).firstOrNull?.$2 ?? '';
    // A real centred box, rather than InputDecorator's baseline metrics, keeps
    // both numeric presets and CJK labels centred at every text scale.
    return Builder(
      builder: (anchorContext) => Semantics(
        button: true,
        enabled: onChanged != null,
        child: Material(
          color: compact ? Colors.transparent : palette.raised,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9),
            side: compact ? BorderSide.none : BorderSide(color: palette.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: key,
            borderRadius: BorderRadius.circular(9),
            onTap: onChanged == null
                ? null
                : () async {
                    if (_editingBlocked || !_currentScope) return;
                    final anchor = anchorContext.findRenderObject()! as RenderBox;
                    var menuWidth = math.max(220.0, anchor.size.width);
                    for (final item in items) {
                      final measure = TextPainter(
                        text: TextSpan(text: item.$2, style: textStyle),
                        textDirection: Directionality.of(anchorContext),
                        textScaler: MediaQuery.textScalerOf(anchorContext),
                      )..layout();
                      // 6px outer padding, 10px row padding, and the trailing
                      // selected check + its gap are reserved for every row.
                      menuWidth = math.max(menuWidth, measure.width + 60);
                      measure.dispose();
                    }
                    final selected = await genAiShowMenu<T>(
                      context: anchorContext,
                      anchorContext: anchorContext,
                      minWidth: menuWidth,
                      items: [
                        for (var index = 0; index < items.length; index++)
                          PopupMenuItem<T>(
                            key: ValueKey('genai-studio-option-${key.value}-$index'),
                            value: items[index].$1,
                            height: 42,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    items[index].$2,
                                    softWrap: false,
                                    style: textStyle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 17,
                                  child: items[index].$1 == value
                                      ? GenAiIcon(GenAiGlyph.check, size: 17, color: palette.accent)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                    if (!mounted || !_currentScope || _editingBlocked || selected == null) return;
                    if (!anchorContext.mounted) return;
                    onChanged(selected);
                  },
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: 48,
              ),
              child: Padding(
                padding:
                    EdgeInsets.symmetric(horizontal: compact ? 0 : 12, vertical: compact ? 0 : 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        heightFactor: 1,
                        child: Text(
                          label,
                          key: ValueKey('${key.value}-value'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyle,
                          strutStyle:
                              const StrutStyle(fontSize: 14, height: 1.4, forceStrutHeight: true),
                          textHeightBehavior: const TextHeightBehavior(
                            applyHeightToFirstAscent: false,
                            applyHeightToLastDescent: false,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    GenAiIcon(GenAiGlyph.down, size: 16, color: palette.muted),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _orientationControl(
    String orientation,
    bool enabled, {
    VoidCallback? notify,
    bool minTargets = false,
  }) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final colors = Theme.of(context).colorScheme;
          final scale = MediaQuery.textScalerOf(context).scale(12) / 12;
          final columns = constraints.maxWidth >= 210 * scale ? 3 : 1;
          final width = (constraints.maxWidth - 6 - (columns - 1) * 3) / columns;
          final optionHeight = minTargets ? 44.0 : null;
          return Container(
            key: const ValueKey('genai-image-orientation'),
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Wrap(
              spacing: 3,
              runSpacing: 3,
              children: [
                for (final option in const [
                  ('landscape', '横向', 15.0, 10.0),
                  ('square', '方形', 12.0, 12.0),
                  ('portrait', '纵向', 10.0, 15.0),
                ])
                  SizedBox(
                    key: ValueKey('genai-orientation-${option.$1}'),
                    width: width,
                    height: optionHeight,
                    child: Semantics(
                      button: true,
                      selected: orientation == option.$1,
                      enabled: enabled,
                      child: Material(
                        color: orientation == option.$1 ? colors.surface : Colors.transparent,
                        elevation: orientation == option.$1 ? 1 : 0,
                        shadowColor: Colors.black12,
                        borderRadius: BorderRadius.circular(6),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap:
                              enabled ? () => _selectOrientation(option.$1, notify: notify) : null,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: option.$3,
                                  height: option.$4,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: enabled ? colors.onSurfaceVariant : colors.outline,
                                      width: 1.3,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  option.$2,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: enabled ? colors.onSurface : colors.outline,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      );

  Widget _imageSizeControls({VoidCallback? onChanged, bool compactDialog = false}) {
    final enabled = !_editingBlocked;
    final presets = GenAiImageSize.presets[_aspectRatio] ?? const <String, String>{};
    final orientation = _orientationOf(_aspectRatio);
    final ratios = [
      for (final ratio in GenAiImageSize.presets.keys)
        if (_orientationOf(ratio) == orientation) ratio,
    ];
    if (!ratios.contains(_aspectRatio)) ratios.insert(0, _aspectRatio);
    final ratio = _studioSelect<String>(
      key: const ValueKey('genai-image-ratio'),
      value: _aspectRatio,
      items: [for (final ratio in ratios) (ratio, ratio)],
      onChanged: enabled ? (value) => _selectAspectRatio(value!, notify: onChanged) : null,
    );
    final resolution = _studioSelect<String>(
      key: const ValueKey('genai-image-resolution'),
      value: _resolution,
      items: [
        for (final entry in presets.entries)
          (entry.key, '${entry.key} · ${entry.value.replaceAll('x', ' × ')}'),
        (_customResolution, '自定义'),
      ],
      selectedLabel: _resolutionLabel,
      onChanged: enabled ? (value) => _selectResolution(value!, notify: onChanged) : null,
    );
    final quality = _studioField(
      '质量',
      _studioSelect<String>(
        key: const ValueKey('genai-image-quality'),
        value: _quality,
        items: [for (final entry in _qualityLabels.entries) (entry.key, entry.value)],
        onChanged: enabled ? (value) => _selectQuality(value!, notify: onChanged) : null,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _studioField(
          '方向',
          _orientationControl(
            orientation,
            enabled,
            notify: onChanged,
            minTargets: compactDialog,
          ),
        ),
        const SizedBox(height: 18),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (ratios.length > 1) ...[
              Expanded(child: _studioField('比例', ratio)),
              const SizedBox(width: 12),
            ],
            Expanded(child: _studioField('分辨率', resolution)),
          ],
        ),
        if (_customSize) ...[
          const SizedBox(height: 12),
          _dimensionRow(enabled, onChanged),
        ],
        const SizedBox(height: 18),
        quality,
      ],
    );
  }

  Widget _dimensionRow(bool enabled, VoidCallback? onChanged) {
    final palette = GenAiPalette.of(context);
    final error = !_validSize;
    Widget dimension(TextEditingController controller, bool width) => _studioField(
          width ? '宽度' : '高度',
          Semantics(
            label: width ? '宽度' : '高度',
            child: TextField(
              key: ValueKey(width ? 'genai-image-width' : 'genai-image-height'),
              controller: controller,
              enabled: enabled,
              textAlignVertical: TextAlignVertical.center,
              style: const TextStyle(fontSize: 14, height: 1.4),
              strutStyle: const StrutStyle(fontSize: 14, height: 1.4, forceStrutHeight: true),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(7),
              ],
              decoration: _studioDecoration(error: error),
              onChanged: (value) => _editDimension(value, width: width, notify: onChanged),
            ),
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(child: dimension(_customWidth, true)),
        SizedBox(
          width: 48,
          height: 48,
          child: Center(
            child: IconButton(
              key: const ValueKey('genai-image-link'),
              tooltip: _linked ? '宽高联动' : '宽高独立',
              visualDensity: VisualDensity.compact,
              color: _linked ? palette.accent : palette.muted,
              onPressed: enabled ? () => _toggleLinked(notify: onChanged) : null,
              isSelected: _linked,
              selectedIcon: const GenAiIcon(GenAiGlyph.link, size: 18),
              icon: const GenAiIcon(GenAiGlyph.unlink, size: 18),
            ),
          ),
        ),
        Expanded(child: dimension(_customHeight, false)),
      ],
    );
  }

  Widget _imageStudio() => LayoutBuilder(
        builder: (context, constraints) {
          final localWidth = constraints.maxWidth;
          final declaredStage = widget.stageWidth ?? 0;
          final windowWidth = MediaQuery.sizeOf(context).width;
          // Breakpoints follow the stage the studio actually occupies. The
          // local box only constrains what can be painted; a zero/invalid
          // stage never selects a phone layout.
          final stage =
              declaredStage > 0 ? declaredStage : (windowWidth > 0 ? windowWidth : localWidth);
          // The draft stacks the form above the gallery at 680px and keeps the
          // form beside its own scrolling gallery above that.
          if (stage <= 680) {
            return CustomScrollView(
              controller: _studioScroll,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      ..._studioForm(compact: true, short: constraints.maxHeight < 360),
                      const SizedBox(height: 26),
                    ]),
                  ),
                ),
                ..._gallerySlivers(
                  const EdgeInsets.symmetric(horizontal: 18),
                  bottom: 30,
                  stageWidth: stage,
                ),
              ],
            );
          }
          final short = GenAiLayout(Size(localWidth, constraints.maxHeight)).short;
          final wide = stage > 1100;
          final mid = stage > 959;
          final formWidth = (localWidth * .4).clamp(280.0, 440.0);
          final gap = wide ? 42.0 : (mid ? 26.0 : 28.0);
          final padding = short
              ? const EdgeInsets.symmetric(horizontal: 18, vertical: 8)
              : wide
                  ? const EdgeInsets.fromLTRB(32, 24, 32, 40)
                  : mid
                      ? const EdgeInsets.all(20)
                      : const EdgeInsets.symmetric(horizontal: 24, vertical: 20);
          return Padding(
            key: const ValueKey('genai-image-padding'),
            padding: padding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  key: const ValueKey('genai-image-form'),
                  width: formWidth,
                  child: Column(
                    children: [
                      Flexible(
                        child: ListView(
                          controller: _studioScroll,
                          shrinkWrap: true,
                          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                          children: [
                            if (!short) ...[
                              Text(
                                '让想象成像。',
                                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -.4,
                                    ),
                              ),
                              const SizedBox(height: 24),
                            ],
                            ..._studioForm(
                              compact: short || constraints.maxHeight < 760,
                              includeGenerate: false,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      _generateButton(),
                    ],
                  ),
                ),
                SizedBox(key: const ValueKey('genai-image-gap'), width: gap),
                Expanded(
                  child: CustomScrollView(
                    slivers: _gallerySlivers(EdgeInsets.zero, stageWidth: stage),
                  ),
                ),
              ],
            ),
          );
        },
      );

  List<Widget> _gallerySlivers(
    EdgeInsets padding, {
    double bottom = 24,
    double? stageWidth,
  }) =>
      [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 20),
          sliver: SliverToBoxAdapter(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '我的创作',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
                if (_images.isNotEmpty)
                  Text(
                    '${_images.length} 张',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                _refreshButton(),
              ],
            ),
          ),
        ),
        if (_loadFailure != null)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding.left, 0, padding.right, 0),
            sliver: SliverToBoxAdapter(child: _loadError()),
          ),
        SliverPadding(padding: padding, sliver: _imageGallery(stageWidth)),
        SliverToBoxAdapter(child: _loadMore()),
        SliverToBoxAdapter(child: SizedBox(height: bottom)),
      ];

  List<Widget> _studioForm({
    required bool compact,
    bool includeGenerate = true,
    bool short = false,
  }) {
    final models = _workspace.imageModels;
    return [
      if (models.isEmpty) const Text('当前模型目录没有可用的生图模型。') else _modelField(models, compact: compact),
      SizedBox(
        height: short
            ? 4
            : compact
                ? 12
                : 18,
      ),
      Semantics(
        label: '画面描述',
        child: TextField(
          key: const ValueKey('genai-image-prompt'),
          controller: _prompt,
          enabled: !_editingBlocked,
          minLines: short
              ? 1
              : compact
                  ? 4
                  : 6,
          maxLines: compact ? 10 : 14,
          textAlignVertical: TextAlignVertical.top,
          style: const TextStyle(fontSize: 14, height: 1.7),
          onChanged: (_) => setState(() {}),
          decoration: _studioDecoration(hint: '描述你想创作的画面…'),
        ),
      ),
      SizedBox(height: short ? 2 : 12),
      _referenceImageControls(),
      if (compact) ...[
        SizedBox(height: short ? 2 : 12),
        _mobileParametersButton(),
      ] else ...[
        SizedBox(height: short ? 4 : 16),
        _imageSizeControls(),
      ],
      SizedBox(height: short ? 4 : 16),
      if (includeGenerate) _generateButton(),
      if (_workspace.imageStudio.failure case final failure?)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(genAiFailureText(failure)),
        ),
    ];
  }

  Widget _modelField(List<GenAiModel> models, {required bool compact}) {
    final select = _studioSelect<GenAiModel>(
      key: const ValueKey('genai-image-model'),
      value: _imageModel,
      items: [for (final model in models) (model, model.name)],
      compact: compact,
      onChanged: _editingBlocked ? null : (model) => setState(() => _imageModel = model),
    );
    return compact ? Semantics(label: '模型', child: select) : _studioField('模型', select);
  }

  Widget _mobileParametersButton() => SizedBox(
        width: double.infinity,
        height: 44,
        child: OutlinedButton(
          key: const ValueKey('genai-image-parameters'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurface,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
          onPressed: _editingBlocked ? null : () => unawaited(_showParameters()),
          child: Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _parameterSummary,
                    key: const ValueKey('genai-image-parameter-summary'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    strutStyle: const StrutStyle(fontSize: 12, height: 1.4, forceStrutHeight: true),
                    textHeightBehavior: const TextHeightBehavior(
                      applyHeightToFirstAscent: false,
                      applyHeightToLastDescent: false,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const GenAiIcon(GenAiGlyph.down, size: 14),
            ],
          ),
        ),
      );

  Future<void> _showParameters() async {
    if (_editingBlocked || !_currentScope) return;
    Widget content(BuildContext dialogContext) => AnimatedBuilder(
          animation: Listenable.merge([_workspace, _workspace.sessions, _workspace.imageStudio]),
          builder: (context, _) => StatefulBuilder(
            builder: (context, update) => Column(
              key: const ValueKey('genai-parameters-surface'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GenAiContentHeader(
                  key: const ValueKey('genai-parameters-header'),
                  title: _currentScope ? '图片参数' : '账号已切换',
                ),
                Flexible(
                  child: Scrollbar(
                    controller: _parameterScroll,
                    child: SingleChildScrollView(
                      key: const ValueKey('genai-parameters-body'),
                      controller: _parameterScroll,
                      padding: const EdgeInsets.all(18),
                      child: _currentScope
                          ? _imageSizeControls(onChanged: () => update(() {}), compactDialog: true)
                          : const Text('请关闭后重新打开。'),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('完成'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    if (GenAiLayout.of(context).narrow) {
      await genAiShowModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (context) => Padding(
          padding: MediaQuery.viewInsetsOf(context),
          child: SafeArea(top: false, child: content(context)),
        ),
      );
    } else {
      await genAiShowDialog<void>(
        context: context,
        builder: (context) => Dialog(
          key: const ValueKey('genai-image-parameters-dialog'),
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(16),
          constraints: const BoxConstraints(maxWidth: 520),
          child: content(context),
        ),
      );
    }
  }

  Widget _generateButton() {
    final canGenerate = !_editingBlocked &&
        !_pickingReference &&
        _scopeValid &&
        _imageModel != null &&
        _prompt.text.trim().isNotEmpty &&
        _validSize;
    Widget button = SizedBox(
      width: double.infinity,
      height: 44,
      child: FilledButton.icon(
        key: const ValueKey('genai-image-generate'),
        onPressed: canGenerate ? () => unawaited(_generate()) : null,
        icon: const GenAiIcon(GenAiGlyph.tools, size: 18),
        label: Text(_generating ? '正在生成…' : '生成图片'),
      ),
    );
    if (!_validSize) {
      button = Tooltip(
        message: '像素总数须为 655,360–8,294,400',
        child: button,
      );
    }
    return button;
  }

  ImageProvider<Object> _imageProvider(Uri uri) => NetworkImage(
        _workspace.repository.imageDisplayUri(uri.toString()).toString(),
      );

  Widget _imageGallery(double? stageWidth) {
    if (!_currentScope) return const SliverToBoxAdapter();
    final records = [..._workspace.imageStudio.pending, ..._images];
    if (records.isEmpty) {
      if (_loading) {
        return const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('正在加载图片…')),
          ),
        );
      }
      if (_loadFailure != null) return const SliverToBoxAdapter();
      final colors = Theme.of(context).colorScheme;
      return SliverToBoxAdapter(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.outlineVariant),
          ),
          child: Column(
            children: [
              GenAiIcon(GenAiGlyph.image, size: 32, color: colors.onSurfaceVariant),
              const SizedBox(height: 12),
              const Text('没有图片记录'),
            ],
          ),
        ),
      );
    }
    return GenAiImageGallery(
      records: records,
      stageWidth: stageWidth,
      imageProvider: _imageProvider,
      onOpen: (record) {
        if (_currentScope) unawaited(_previewImage(record));
      },
      onReference: (record) {
        if (!_currentScope || _editingBlocked || _pickingReference) return;
        final uri = record.images.firstOrNull;
        if (uri == null) return;
        unawaited(_pickReferenceImage(uri: uri));
      },
    );
  }

  Future<void> _previewImage(GenAiImageRecord record, {int index = 0}) async {
    if (!_currentScope) return;
    var current = index;
    if (record.images.isEmpty) {
      current = 0;
    } else if (current < 0) {
      current = 0;
    } else if (current >= record.images.length) {
      current = record.images.length - 1;
    }
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: Listenable.merge([_workspace, _workspace.sessions, _workspace.imageStudio]),
        builder: (context, _) => StatefulBuilder(
          builder: (context, updatePreview) {
            if (!_currentScope) {
              return GenAiDialogFrame(
                insetPadding: EdgeInsets.symmetric(
                  horizontal: _compactDialog(dialogContext) ? 12 : 24,
                  vertical: 24,
                ),
                shape: _dialogShape(_compactDialog(dialogContext)),
                title: const Text('账号已切换'),
                content: const Text('此图片属于之前的账号，请关闭预览后重新打开。'),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('关闭'),
                  ),
                ],
              );
            }
            final uri = record.images.isEmpty ? null : record.images[current];
            final canDelete = _images.any((image) => image.id == record.id);
            final caption = genAiImageCaption(record.prompt, title: record.title);
            return GenAiImageViewer(
              image: uri == null ? null : _imageProvider(uri),
              link: uri,
              title: caption.isEmpty ? '图片预览' : caption,
              navigation: record.images.length <= 1
                  ? null
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          tooltip: '上一张图片',
                          onPressed: current > 0 ? () => updatePreview(() => current--) : null,
                          icon: const GenAiIcon(GenAiGlyph.chevronLeft),
                        ),
                        Text('${current + 1} / ${record.images.length}'),
                        IconButton(
                          tooltip: '下一张图片',
                          onPressed: current + 1 < record.images.length
                              ? () => updatePreview(() => current++)
                              : null,
                          icon: const GenAiIcon(GenAiGlyph.chevron),
                        ),
                      ],
                    ),
              error: _referenceError == null
                  ? null
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      child: Text(
                        _referenceError!,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
              leadingAction: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: Size(0, GenAiLayout.touchPlatform ? 48 : 32),
                ),
                onPressed: uri == null ||
                        _editingBlocked ||
                        _pickingReference ||
                        _references.length >= GenAiReferenceImage.maxCount
                    ? null
                    : () async {
                        if (_editingBlocked) return;
                        final adding = _pickReferenceImage(uri: uri);
                        updatePreview(() {});
                        final added = await adding;
                        if (!context.mounted || !_currentScope) return;
                        if (added) {
                          Navigator.pop(dialogContext);
                        } else {
                          updatePreview(() {});
                        }
                      },
                child: const Text('用作参考', maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              moreActions: [
                (
                  label: '查看描述',
                  icon: GenAiGlyph.file,
                  run: () {
                    if (!_currentScope || !dialogContext.mounted) return;
                    Navigator.pop(dialogContext);
                    unawaited(_showImageDescription(record, index: current));
                  }
                ),
                (
                  label: '复用描述',
                  icon: GenAiGlyph.edit,
                  run: _editingBlocked || record.prompt.trim().isEmpty
                      ? null
                      : () {
                          if (_editingBlocked || !dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          _reuseImagePrompt(record.prompt);
                        }
                ),
                if (canDelete)
                  (
                    label: '删除图片',
                    icon: GenAiGlyph.trash,
                    run: _busy
                        ? null
                        : () {
                            if (!_currentScope || _busy || !dialogContext.mounted) return;
                            Navigator.pop(dialogContext);
                            unawaited(_deleteImage(record.id));
                          }
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _showImageDescription(GenAiImageRecord record, {int index = 0}) async {
    if (!_currentScope) return;
    var current = index;
    if (record.images.isNotEmpty && current >= record.images.length) {
      current = record.images.length - 1;
    }
    final uri = record.images.isEmpty ? null : record.images[current];
    await genAiShowDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: Listenable.merge([_workspace, _workspace.sessions, _workspace.imageStudio]),
        builder: (context, _) {
          if (!_currentScope) {
            return GenAiDialogFrame(
              insetPadding: EdgeInsets.symmetric(
                horizontal: _compactDialog(dialogContext) ? 12 : 24,
                vertical: 24,
              ),
              shape: _dialogShape(_compactDialog(dialogContext)),
              title: const Text('账号已切换'),
              content: const Text('此图片属于之前的账号，请关闭后重新打开。'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('关闭'),
                ),
              ],
            );
          }
          final theme = Theme.of(context);
          final prompt = record.prompt.trim();
          final screen = MediaQuery.sizeOf(context);
          final compact = screen.width <= 600;
          final dialogWidth = math.min(500.0, screen.width - 32);
          final caption = genAiImageCaption(prompt, title: record.title);
          final quality = record.quality?.trim();
          return GenAiDialogFrame(
            key: const ValueKey('genai-image-description'),
            constraints: BoxConstraints.tightFor(width: dialogWidth),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape: _dialogShape(compact),
            contentPadding: EdgeInsets.zero,
            actionsPadding: const EdgeInsets.fromLTRB(17, 0, 17, 17),
            surfaceKey: const ValueKey('genai-description-surface'),
            headerKey: const ValueKey('genai-description-header'),
            title: SelectableText(
              caption.isEmpty ? '图片描述' : caption,
              maxLines: 1,
              style: theme.textTheme.titleMedium?.copyWith(
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              key: const ValueKey('genai-description-body'),
              padding: const EdgeInsets.all(17),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '描述',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    prompt.isEmpty ? '无描述' : prompt,
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                  ),
                  const SizedBox(height: 17),
                  if (uri != null) _ImageSizeLabel(image: _imageProvider(uri)),
                  if (quality != null && quality.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Text(
                          '质量',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(_qualityLabels[quality] ?? quality),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: prompt.isEmpty || _editingBlocked
                    ? null
                    : () {
                        if (!_currentScope) return;
                        Navigator.pop(dialogContext);
                        _reuseImagePrompt(record.prompt);
                      },
                child: const Text('复用描述'),
              ),
              FilledButton(
                onPressed: () {
                  if (!_currentScope) return;
                  Navigator.pop(dialogContext);
                  unawaited(_previewImage(record, index: current));
                },
                child: const Text('返回图片'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _reuseImagePrompt(String prompt) {
    if (_editingBlocked) return;
    setState(() => _prompt.text = prompt);
    _saveDraft();
    if (_studioScroll.hasClients) {
      unawaited(
        _studioScroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        ),
      );
    }
  }
}

/// Shows the decoded pixel dimensions of an image, the only size metadata the
/// history record actually carries.
class _ImageSizeLabel extends StatelessWidget {
  const _ImageSizeLabel({required this.image});
  final ImageProvider<Object> image;

  @override
  Widget build(BuildContext context) => GenAiImageDimensions(
        image: image,
        builder: (context, size) {
          if (size == null) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Row(
            children: [
              Text(
                '尺寸',
                style:
                    theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text('${size.width.round()} × ${size.height.round()}'),
            ],
          );
        },
      );
}
