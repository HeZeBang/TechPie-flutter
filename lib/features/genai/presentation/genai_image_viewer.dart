import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../widgets/adaptive_feedback.dart';
import 'genai_icons.dart';
import 'genai_image_actions.dart';
import 'genai_theme.dart';

/// Shared chat/gallery preview. The image uses the available stage; controls
/// stay outside the zoomable surface and wrap on narrow screens.
class GenAiImageViewer extends StatefulWidget {
  const GenAiImageViewer({
    super.key,
    required this.image,
    this.link,
    this.title = '图片预览',
    this.navigation,
    this.leadingAction,
    this.trailingAction,
    this.error,
  });

  final ImageProvider<Object>? image;
  final Uri? link;
  final String title;
  final Widget? navigation;
  final Widget? leadingAction;
  final Widget? trailingAction;
  final Widget? error;

  @override
  State<GenAiImageViewer> createState() => _GenAiImageViewerState();
}

class _GenAiImageViewerState extends State<GenAiImageViewer> {
  int _attempt = 0;
  bool _retrying = false;
  ImageProvider<Object>? get image => widget.image;
  Uri? get link => widget.link;

  Future<void> _retry() async {
    final provider = image;
    if (provider == null || _retrying) return;
    setState(() => _retrying = true);
    try {
      await provider.evict();
    } finally {
      if (mounted) {
        setState(() {
          _attempt++;
          _retrying = false;
        });
      }
    }
  }

  Future<void> _openOriginal() async {
    final uri = link;
    if (uri == null || !{'http', 'https'}.contains(uri.scheme)) return;
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {/* Report platform failures in the viewer. */}
    if (mounted) showAdaptiveFeedback(context: context, message: '无法打开图片链接');
  }

  Widget _loadError() => SizedBox(
        height: 180,
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('图片暂时无法加载'),
                const SizedBox(height: 8),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    TextButton(onPressed: _retrying ? null : _retry, child: const Text('重试')),
                    if (link != null && {'http', 'https'}.contains(link!.scheme))
                      TextButton(onPressed: _openOriginal, child: const Text('打开原图')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final compact = screen.width <= 600;
    final inset = compact ? 12.0 : 16.0;
    return Dialog(
      key: const ValueKey('genai-image-preview'),
      insetPadding: EdgeInsets.all(inset),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.min(940, screen.width - inset * 2),
          maxHeight: screen.height - inset * 2,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GenAiContentHeader(
              key: const ValueKey('genai-preview-header'),
              title: widget.title,
              actions: [
                IconButton(
                  tooltip: '关闭图片预览',
                  onPressed: () => Navigator.pop(context),
                  icon: const GenAiIcon(GenAiGlyph.close),
                ),
              ],
            ),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: image == null
                    ? const Center(child: Text('此记录没有可预览的图片'))
                    : GenAiImageActions(
                        image: image!,
                        link: link,
                        showMenuButton: false,
                        child: Center(
                          heightFactor: 1,
                          child: InteractiveViewer(
                            key: ValueKey(image),
                            minScale: 1,
                            maxScale: 5,
                            child: Image(
                              key: ValueKey((image, _attempt)),
                              image: image!,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => _loadError(),
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            if (widget.navigation != null) widget.navigation!,
            if (widget.error != null) widget.error!,
            Padding(
              key: const ValueKey('genai-preview-footer'),
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: Wrap(
                alignment:
                    widget.leadingAction == null ? WrapAlignment.end : WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (widget.leadingAction != null) widget.leadingAction!,
                  if (image != null)
                    GenAiImageActions(
                      image: image!,
                      link: link,
                      toolbar: true,
                      showMenuButton: widget.trailingAction == null,
                      child: widget.trailingAction ?? const SizedBox.shrink(),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
