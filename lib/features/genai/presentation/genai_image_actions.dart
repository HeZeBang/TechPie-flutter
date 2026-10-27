import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/adaptive_feedback.dart';
import 'genai_image_save.dart';
import 'genai_image_transfer_native.dart'
    if (dart.library.js_interop) 'genai_image_transfer_web.dart' as platform;

/// The same image actions for chat, Markdown, gallery tiles and image viewers.
/// Decode the displayed provider, not a URL inferred from model prose.
class GenAiImageActions extends StatefulWidget {
  const GenAiImageActions({super.key, required this.image, required this.child, this.link});

  final ImageProvider<Object> image;
  final Uri? link;
  final Widget child;

  @override
  State<GenAiImageActions> createState() => _GenAiImageActionsState();
}

class _GenAiImageActionsState extends State<GenAiImageActions> {
  final _menu = MenuController();
  final _menuButtonFocus = FocusNode();
  Future<Uint8List>? _bytes;
  bool _working = false;

  @override
  void didUpdateWidget(covariant GenAiImageActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) {
      _menu.close();
      _bytes = null;
    }
  }

  @override
  void dispose() {
    _menuButtonFocus.dispose();
    super.dispose();
  }

  void _open([Offset? position]) {
    if (_working) return;
    setState(() {
      // Reload on each opening so failed downloads can be retried.
      _bytes = _loadPng();
    });
    final box = context.findRenderObject()! as RenderBox;
    _menu.open(position: position ?? Offset((box.size.width - 48).clamp(0, double.infinity), 48));
  }

  Future<Uint8List> _loadPng() async {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    final ready = Completer<ImageInfo>();
    final listener = ImageStreamListener(
      (info, _) {
        if (ready.isCompleted) {
          info.dispose();
        } else {
          ready.complete(info);
        }
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    ImageInfo? info;
    try {
      info = await ready.future.timeout(const Duration(seconds: 30));
      final data = await info.image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Image could not be encoded');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } finally {
      stream.removeListener(listener);
      info?.dispose();
    }
  }

  Future<void> _run(Future<void> Function() action, {String? success}) async {
    if (_working) return;
    final image = widget.image;
    setState(() => _working = true);
    try {
      await action();
      if (mounted && image == widget.image && success != null) {
        showAdaptiveFeedback(context: context, message: success);
      }
    } catch (_) {
      if (mounted && image == widget.image) {
        showAdaptiveFeedback(context: context, message: '操作失败，请尝试保存图片或复制链接');
        _bytes = null;
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Rect get _shareOrigin {
    final box = context.findRenderObject()! as RenderBox;
    final bounds = box.localToGlobal(Offset.zero) & box.size;
    final screen = Offset.zero & MediaQuery.sizeOf(context);
    final visible = bounds.intersect(screen);
    return visible.isEmpty ? Rect.fromLTWH(screen.center.dx, screen.center.dy, 1, 1) : visible;
  }

  Widget _item(String label, IconData icon, VoidCallback? action) => MenuItemButton(
        onPressed: action,
        leadingIcon: Icon(icon, size: 20),
        style: const ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(180, 48))),
        child: Text(label),
      );

  @override
  Widget build(BuildContext context) => MenuAnchor(
        controller: _menu,
        childFocusNode: _menuButtonFocus,
        onClose: () {
          // Avoid retaining an encoded copy for every visited gallery tile.
          _bytes = null;
        },
        consumeOutsideTap: true,
        menuChildren: [
          FutureBuilder<Uint8List>(
            future: _bytes,
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (bytes == null)
                    _item(snapshot.hasError ? '图片加载失败' : '正在准备图片…', Icons.image_outlined, null),
                  if (platform.canCopyImage)
                    _item(
                      platform.copiesImageFile ? '复制图片文件' : '复制图片',
                      Icons.copy_outlined,
                      bytes == null
                          ? null
                          : () => unawaited(
                                _run(
                                  () => platform.copyImage(bytes),
                                  success: '已复制图片',
                                ),
                              ),
                    ),
                  if (bytes != null && platform.canShareImage(bytes))
                    _item(
                      '分享图片',
                      Icons.ios_share_outlined,
                      () => unawaited(_run(() => platform.shareImage(bytes, _shareOrigin))),
                    ),
                  _item(
                    '保存图片',
                    Icons.download_outlined,
                    bytes == null
                        ? null
                        : () => unawaited(
                              _run(
                                () async {
                                  await saveGenAiImage(
                                    bytes,
                                    'techpie-${DateTime.now().microsecondsSinceEpoch}.png',
                                  );
                                },
                                success: '已保存图片',
                              ),
                            ),
                  ),
                  if (widget.link case final link?)
                    _item(
                      '复制链接',
                      Icons.link,
                      () => unawaited(
                        _run(
                          () => Clipboard.setData(ClipboardData(text: link.toString())),
                          success: '已复制链接',
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
        builder: (context, controller, child) => GestureDetector(
          // The visible menu button exposes these secondary actions. Giving the
          // whole image long-press semantics intercepts web preview activation.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) => _open(details.localPosition),
          onLongPressStart: (details) => _open(details.localPosition),
          child: Stack(
            children: [
              widget.child,
              PositionedDirectional(
                top: 4,
                end: 4,
                child: IconButton.filledTonal(
                  tooltip: '图片操作',
                  focusNode: _menuButtonFocus,
                  onPressed: _working ? null : () => _open(),
                  icon: _working
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.more_horiz),
                ),
              ),
            ],
          ),
        ),
      );
}
