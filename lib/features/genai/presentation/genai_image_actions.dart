import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../widgets/adaptive_feedback.dart';
import 'genai_icons.dart';
import 'genai_image_save.dart';
import 'genai_image_transfer_native.dart'
    if (dart.library.js_interop) 'genai_image_transfer_web.dart'
    as platform;
import 'genai_theme.dart';

/// Resolves [image] and returns its PNG encoding.
///
/// Decode the displayed provider, not a URL inferred from model prose.
Future<Uint8List> loadGenAiImagePng(ImageProvider<Object> image, BuildContext context) async {
  final stream = image.resolve(createLocalImageConfiguration(context));
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

Rect _shareOriginFor(BuildContext context) {
  final screen = Offset.zero & MediaQuery.sizeOf(context);
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) {
    return Rect.fromLTWH(screen.center.dx, screen.center.dy, 1, 1);
  }
  final bounds = box.localToGlobal(Offset.zero) & box.size;
  final visible = bounds.intersect(screen);
  return visible.isEmpty ? Rect.fromLTWH(screen.center.dx, screen.center.dy, 1, 1) : visible;
}

typedef GenAiPreviewAction = ({String label, GenAiGlyph icon, VoidCallback? run});

/// The same image actions for chat, Markdown, gallery tiles and image viewers.
/// Decode the displayed provider, not a URL inferred from model prose.
class GenAiImageActions extends StatefulWidget {
  const GenAiImageActions({
    super.key,
    required this.image,
    required this.child,
    this.link,
    this.showMenuButton = true,
    this.toolbar = false,
    this.moreActions = const [],
    this.onOpen,
    this.onReference,
  });

  final ImageProvider<Object> image;
  final Uri? link;
  final Widget child;

  /// Gallery tiles leave the visible button to the preview they open; the
  /// right-click menu stays available on the tile itself.
  final bool showMenuButton;

  /// Common copy/share/save controls below the chat and gallery viewer.
  final bool toolbar;
  final List<GenAiPreviewAction> moreActions;

  /// When either callback is set the menu becomes the gallery tile variant:
  /// open, use as reference, copy link and save. Chat keeps its image menu.
  final VoidCallback? onOpen;
  final VoidCallback? onReference;

  @override
  State<GenAiImageActions> createState() => _GenAiImageActionsState();
}

enum _ImageAction { open, reference, copyLink, copyImage, shareImage, save }

class _GenAiImageActionsState extends State<GenAiImageActions> {
  bool _working = false;
  bool _menuOpen = false;

  Future<Uint8List> _loadPng() => loadGenAiImagePng(widget.image, context);

  /// Opens the shared anchored menu.
  ///
  /// The PNG encoding starts here but is deliberately not awaited: the popover
  /// opens immediately with its loading row and rebuilds when the bytes land.
  /// [anchorContext] is the visible button for a click, and the whole tile for
  /// a right click.
  Future<void> _open(BuildContext anchorContext, {bool pointerMenu = false}) async {
    if (_working || _menuOpen) return;
    final image = widget.image;
    // The overlay route can outlive this tile, so its rows must not read
    // `widget` after the state is disposed.
    final link = widget.link;
    final galleryMenu = _galleryMenu;
    final showOpen = widget.onOpen != null;
    final showReference = widget.onReference != null;
    final bytes = _loadPng();
    _menuOpen = true;
    _ImageAction? action;
    try {
      action = await genAiShowMenu<_ImageAction>(
        pointerMenu: pointerMenu,
        context: context,
        anchorContext: anchorContext,
        items: _items(
          bytes,
          galleryMenu: galleryMenu,
          link: link,
          showOpen: showOpen,
          showReference: showReference,
        ),
        minWidth: 220,
        gap: 7,
        semanticLabel: '图片操作',
      );
    } finally {
      _menuOpen = false;
    }
    // The tile can be removed or rebound while the popover is open.
    if (!mounted || image != widget.image || action == null) return;
    await _execute(action, bytes, image);
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
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  /// Runs the selected row after the popover has closed and the tile scope was
  /// re-checked. Byte-dependent rows await the same future the menu observed,
  /// so a failed download still lands in [_run]'s recovery message.
  Future<void> _execute(
    _ImageAction action,
    Future<Uint8List> bytes,
    ImageProvider<Object> image,
  ) async {
    switch (action) {
      case _ImageAction.open:
        widget.onOpen?.call();
        return;
      case _ImageAction.reference:
        widget.onReference?.call();
        return;
      case _ImageAction.copyLink:
        final link = widget.link;
        if (link == null) return;
        await _run(() => Clipboard.setData(ClipboardData(text: link.toString())), success: '已复制链接');
        return;
      case _ImageAction.copyImage:
        await _run(() async {
          final data = await bytes;
          if (!mounted || image != widget.image) return;
          await platform.copyImage(data);
        }, success: '已复制图片');
        return;
      case _ImageAction.shareImage:
        await _run(() async {
          final data = await bytes;
          if (!mounted || image != widget.image) return;
          await platform.shareImage(data, _shareOrigin);
        });
        return;
      case _ImageAction.save:
        await _run(() async {
          final data = await bytes;
          if (!mounted || image != widget.image) return;
          await saveGenAiImage(data, 'techpie-${DateTime.now().microsecondsSinceEpoch}.png');
        }, success: '已保存图片');
        return;
    }
  }

  Rect get _shareOrigin => _shareOriginFor(context);

  PopupMenuItem<_ImageAction> _copyLinkItem(
    GenAiPalette palette, {
    GenAiGlyph glyph = GenAiGlyph.link,
  }) => genAiActionItem(palette, _ImageAction.copyLink, GenAiIcon(glyph), '复制链接');

  PopupMenuItem<_ImageAction> _saveItem(GenAiPalette palette, {required bool enabled}) =>
      genAiActionItem(
        palette,
        _ImageAction.save,
        const GenAiIcon(GenAiGlyph.download),
        '保存图片',
        enabled: enabled,
      );

  /// Gallery tiles have no visible menu button, so their menu is the exact
  /// tile action set the draft describes. Chat keeps its image menu.
  bool get _galleryMenu => widget.onOpen != null || widget.onReference != null;

  List<PopupMenuEntry<_ImageAction>> _items(
    Future<Uint8List> bytes, {
    required bool galleryMenu,
    required Uri? link,
    required bool showOpen,
    required bool showReference,
  }) => [
    _GenAiImageMenuEntry<_ImageAction>(
      future: bytes,
      builder: (context, snapshot) {
        final palette = GenAiPalette.of(context);
        final data = snapshot.data;
        final rows = <PopupMenuItem<_ImageAction>>[];
        if (galleryMenu) {
          if (showOpen) {
            rows.add(
              genAiActionItem(palette, _ImageAction.open, const GenAiIcon(GenAiGlyph.full), '查看图片'),
            );
          }
          if (showReference) {
            rows.add(
              genAiActionItem(
                palette,
                _ImageAction.reference,
                const GenAiIcon(GenAiGlyph.image),
                '用作参考',
              ),
            );
          }
          if (link != null) rows.add(_copyLinkItem(palette, glyph: GenAiGlyph.copy));
          rows.add(_saveItem(palette, enabled: data != null));
        } else {
          if (data == null) {
            rows.add(
              genAiActionItem<_ImageAction>(
                palette,
                null,
                const GenAiIcon(GenAiGlyph.image),
                snapshot.hasError ? '图片加载失败' : '正在准备图片…',
                enabled: false,
              ),
            );
          }
          if (platform.canCopyImage) {
            rows.add(
              genAiActionItem(
                palette,
                _ImageAction.copyImage,
                const GenAiIcon(GenAiGlyph.copy),
                platform.copiesImageFile ? '复制图片文件' : '复制图片',
                enabled: data != null,
              ),
            );
          }
          if (data != null && platform.canShareImage) {
            rows.add(
              genAiActionItem(
                palette,
                _ImageAction.shareImage,
                const GenAiIcon(GenAiGlyph.share),
                '分享图片',
              ),
            );
          }
          rows.add(_saveItem(palette, enabled: data != null));
          if (link != null) rows.add(_copyLinkItem(palette));
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [for (final row in rows) genAiMenuEntry<_ImageAction>(row)],
        );
      },
    ),
  ];

  Widget _toolbar() => LayoutBuilder(
    builder: (context, constraints) {
      final image = widget.image;
      final link = widget.link;
      // Most useful first: each available slot promotes one action out of More.
      final actions = <GenAiPreviewAction>[
        (
          label: '下载图片',
          icon: GenAiGlyph.download,
          run: () => _execute(_ImageAction.save, _loadPng(), image),
        ),
        if (platform.canShareImage)
          (
            label: '分享图片',
            icon: GenAiGlyph.share,
            run: () => _execute(_ImageAction.shareImage, _loadPng(), image),
          ),
        if (link != null)
          (
            label: '复制链接',
            icon: GenAiGlyph.copy,
            run: () => _run(
              () => Clipboard.setData(ClipboardData(text: link.toString())),
              success: '已复制链接',
            ),
          ),
      ];
      final extra = <GenAiPreviewAction>[
        if (widget.showMenuButton && platform.canCopyImage)
          (
            label: platform.copiesImageFile ? '复制图片文件' : '复制图片',
            icon: GenAiGlyph.copy,
            run: () => _execute(_ImageAction.copyImage, _loadPng(), image),
          ),
        ...widget.moreActions,
      ];
      const slot = 48.0;
      final slots = (constraints.maxWidth / slot).floor();
      final needsMenu = extra.isNotEmpty || slots < actions.length;
      final visible = (slots - (needsMenu ? 1 : 0)).clamp(0, actions.length);
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          for (final action in actions.take(visible).toList().reversed)
            SizedBox.square(
              dimension: slot,
              child: IconButton(
                tooltip: action.label,
                onPressed: _working ? null : action.run,
                icon: _working && action.icon == GenAiGlyph.download
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : GenAiIcon(action.icon),
              ),
            ),
          if (needsMenu)
            Builder(
              builder: (anchor) => SizedBox.square(
                key: const ValueKey('genai-preview-more'),
                dimension: slot,
                child: IconButton(
                  tooltip: '更多图片操作',
                  icon: _working && visible == 0
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const GenAiIcon(GenAiGlyph.more),
                  onPressed: _working
                      ? null
                      : () async {
                          final picked = await genAiShowMenu<GenAiPreviewAction>(
                            context: context,
                            anchorContext: anchor,
                            minWidth: 170,
                            preferAbove: true,
                            alignEnd: true,
                            gap: 8,
                            menuPadding: 5,
                            radius: 9,
                            semanticLabel: '更多图片操作',
                            items: [
                              for (final action in [...actions.skip(visible), ...extra])
                                genAiActionItem(
                                  GenAiPalette.of(context),
                                  action,
                                  GenAiIcon(action.icon),
                                  action.label,
                                  enabled: action.run != null,
                                ),
                            ],
                          );
                          if (mounted && image == widget.image) picked?.run?.call();
                        },
                ),
              ),
            ),
        ],
      );
    },
  );

  @override
  Widget build(BuildContext context) => widget.toolbar
      ? _toolbar()
      : GestureDetector(
          // The visible menu button exposes these secondary actions without
          // overriding the image preview semantics.
          excludeFromSemantics: true,
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (_) => unawaited(_open(context, pointerMenu: true)),
          child: Stack(
            children: [
              widget.child,
              if (widget.showMenuButton)
                PositionedDirectional(
                  top: 4,
                  end: 4,
                  child: Builder(
                    builder: (anchorContext) => IconButton.filledTonal(
                      tooltip: '图片操作',
                      onPressed: _working ? null : () => unawaited(_open(anchorContext)),
                      icon: _working
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const GenAiIcon(GenAiGlyph.more),
                    ),
                  ),
                ),
            ],
          ),
        );
}

/// A menu entry whose rows are built as the PNG encoding finishes.
///
/// The shared anchored route takes a fixed entry list, so the dynamic rows live
/// inside one entry: the loading/error status and the byte-dependent copy,
/// share and save actions rebuild in place instead of delaying the popover.
class _GenAiImageMenuEntry<T> extends PopupMenuEntry<T> {
  const _GenAiImageMenuEntry({required this.future, required this.builder});

  final Future<Uint8List> future;
  final Widget Function(BuildContext context, AsyncSnapshot<Uint8List> snapshot) builder;

  @override
  double get height => 0;

  @override
  bool represents(T? value) => false;

  @override
  State<_GenAiImageMenuEntry<T>> createState() => _GenAiImageMenuEntryState<T>();
}

class _GenAiImageMenuEntryState<T> extends State<_GenAiImageMenuEntry<T>> {
  @override
  Widget build(BuildContext context) =>
      FutureBuilder<Uint8List>(future: widget.future, builder: widget.builder);
}
