import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../domain/genai_platform_contract.dart';
import 'genai_image_actions.dart';

/// A lazy image-history sliver whose tile sizes follow the decoded images.
class GenAiImageGallery extends StatefulWidget {
  const GenAiImageGallery({
    super.key,
    required this.records,
    required this.imageProvider,
    required this.onOpen,
  });

  final List<GenAiImageRecord> records;
  final ImageProvider<Object> Function(Uri) imageProvider;
  final ValueChanged<GenAiImageRecord> onOpen;

  @override
  State<GenAiImageGallery> createState() => _GenAiImageGalleryState();
}

class _GenAiImageGalleryState extends State<GenAiImageGallery> {
  static const _spacing = 12.0;
  final _aspectRatios = <Uri, double>{};
  final _pendingRatios = <Uri, double>{};
  bool _updateScheduled = false;

  @override
  void didUpdateWidget(covariant GenAiImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.records.map((record) => record.images.firstOrNull).toSet();
    _aspectRatios.removeWhere((uri, _) => !active.contains(uri));
    _pendingRatios.removeWhere((uri, _) => !active.contains(uri));
  }

  void _imageMeasured(Uri uri, double ratio) {
    if (!mounted) return;
    final validRatio = ratio.isFinite && ratio > 0 ? ratio : 1.0;
    if (_aspectRatios[uri] == validRatio && !_pendingRatios.containsKey(uri)) return;
    _pendingRatios[uri] = validRatio;
    if (_updateScheduled) return;
    _updateScheduled = true;
    // Cached image streams can complete while a sliver is building its children.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _updateScheduled = false;
      final active = widget.records.map((record) => record.images.firstOrNull).toSet();
      final updates = Map<Uri, double>.of(_pendingRatios)
        ..removeWhere((uri, ratio) => !active.contains(uri) || _aspectRatios[uri] == ratio);
      _pendingRatios.clear();
      if (updates.isNotEmpty) setState(() => _aspectRatios.addAll(updates));
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          var columns = constraints.crossAxisExtent >= 920
              ? 4
              : constraints.crossAxisExtent >= 620
                  ? 3
                  : constraints.crossAxisExtent >= 260
                      ? 2
                      : 1;
          final textScaler = MediaQuery.textScalerOf(context);
          while (columns > 1 &&
              (constraints.crossAxisExtent - _spacing * (columns - 1)) / columns <
                  textScaler.scale(120)) {
            columns--;
          }
          final promptStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35);
          final promptHeight = textScaler.scale((promptStyle?.fontSize ?? 14) * 1.35) * 2;
          return SliverGrid(
            key: const ValueKey('genai-image-gallery'),
            gridDelegate: _MasonryGridDelegate(
              columns: columns,
              spacing: _spacing,
              captionExtent: promptHeight + 24,
              aspectRatios: [
                for (final record in widget.records)
                  _aspectRatios[record.images.firstOrNull] ?? 1.0,
              ],
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final record = widget.records[index];
                final prompt = record.prompt.trim().isEmpty ? '未命名图片' : record.prompt;
                final uri = record.images.firstOrNull;
                final colors = Theme.of(context).colorScheme;
                return Card(
                  key: ValueKey('genai-image-${record.id}'),
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => widget.onOpen(record),
                    child: Semantics(
                      button: true,
                      label: '查看图片',
                      onTap: () => widget.onOpen(record),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: ColoredBox(
                              color: colors.surfaceContainerLow,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  if (uri == null)
                                    const _ImageUnavailable()
                                  else
                                    GenAiImageActions(
                                      image: widget.imageProvider(uri),
                                      link: uri,
                                      child: _MeasuredImage(
                                        key: ValueKey(uri),
                                        image: widget.imageProvider(uri),
                                        onAspectRatio: (ratio) => _imageMeasured(uri, ratio),
                                      ),
                                    ),
                                  if (record.images.length > 1)
                                    PositionedDirectional(
                                      top: 8,
                                      start: 8,
                                      child: _ImageBadge(
                                        icon: Icons.photo_library_outlined,
                                        label: '${record.images.length}',
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              height: promptHeight,
                              child: Text(
                                prompt,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: promptStyle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              childCount: widget.records.length,
            ),
          );
        },
      );
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.inverseSurface.withValues(alpha: .85),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: colors.onInverseSurface),
              const SizedBox(width: 4),
            ],
            Text(label, style: TextStyle(fontSize: 10, color: colors.onInverseSurface)),
          ],
        ),
      ),
    );
  }
}

class _ImageUnavailable extends StatelessWidget {
  const _ImageUnavailable();

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              const Text('预览暂不可用', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

/// Observe only the first decoded frame; Image owns its separate display handle.
class _MeasuredImage extends StatefulWidget {
  const _MeasuredImage({super.key, required this.image, required this.onAspectRatio});

  final ImageProvider<Object> image;
  final ValueChanged<double> onAspectRatio;

  @override
  State<_MeasuredImage> createState() => _MeasuredImageState();
}

class _MeasuredImageState extends State<_MeasuredImage> {
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolveImage();
  }

  @override
  void didUpdateWidget(covariant _MeasuredImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.image != widget.image) _resolveImage();
  }

  void _resolveImage() {
    _stopListening();
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener(
      (info, _) {
        final width = info.image.width;
        final height = info.image.height;
        info.dispose();
        if (!mounted || !identical(_stream, stream)) return;
        _stopListening();
        widget.onAspectRatio(width > 0 && height > 0 ? width / height : 1.0);
      },
      onError: (Object error, StackTrace? stackTrace) {
        if (!mounted || !identical(_stream, stream)) return;
        _stopListening();
        widget.onAspectRatio(1.0);
      },
    );
    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _stopListening() {
    final listener = _listener;
    if (listener != null) _stream?.removeListener(listener);
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Image(
        image: widget.image,
        fit: BoxFit.contain,
        excludeFromSemantics: true,
        frameBuilder: (context, child, frame, synchronouslyLoaded) =>
            frame != null || synchronouslyLoaded
                ? child
                : Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 28,
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
        errorBuilder: (_, __, ___) => const _ImageUnavailable(),
      );
}

class _MasonryGridDelegate extends SliverGridDelegate {
  const _MasonryGridDelegate({
    required this.columns,
    required this.spacing,
    required this.captionExtent,
    required this.aspectRatios,
  });

  final int columns;
  final double spacing;
  final double captionExtent;
  final List<double> aspectRatios;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => _MasonryGridLayout(
        columns: columns,
        spacing: spacing,
        captionExtent: captionExtent,
        aspectRatios: aspectRatios,
        crossAxisExtent: constraints.crossAxisExtent,
        reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
      );

  @override
  bool shouldRelayout(covariant _MasonryGridDelegate oldDelegate) =>
      columns != oldDelegate.columns ||
      spacing != oldDelegate.spacing ||
      captionExtent != oldDelegate.captionExtent ||
      !listEquals(aspectRatios, oldDelegate.aspectRatios);
}

class _MasonryGridLayout extends SliverGridLayout {
  _MasonryGridLayout({
    required int columns,
    required double spacing,
    required double captionExtent,
    required List<double> aspectRatios,
    required double crossAxisExtent,
    required bool reverseCrossAxis,
  }) : _tileWidth = math.max(0.0, (crossAxisExtent - spacing * (columns - 1)) / columns) {
    final columnOffsets = List<double>.filled(columns, 0);
    var trailingMax = 0.0;
    for (final aspectRatio in aspectRatios) {
      var column = 0;
      for (var candidate = 1; candidate < columns; candidate++) {
        if (columnOffsets[candidate] < columnOffsets[column]) column = candidate;
      }
      final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.0;
      // Only bound the tile. BoxFit.contain still displays the complete image.
      final extent = _tileWidth / ratio.clamp(1 / 3, 3.0) + captionExtent;
      final geometry = SliverGridGeometry(
        scrollOffset: columnOffsets[column],
        crossAxisOffset:
            (reverseCrossAxis ? columns - 1 - column : column) * (_tileWidth + spacing),
        mainAxisExtent: extent,
        crossAxisExtent: _tileWidth,
      );
      _tiles.add(geometry);
      columnOffsets[column] = geometry.trailingScrollOffset + spacing;
      trailingMax = math.max(trailingMax, geometry.trailingScrollOffset);
      _trailingMax.add(trailingMax);
    }
  }

  final double _tileWidth;
  final _tiles = <SliverGridGeometry>[];
  final _trailingMax = <double>[];

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset) {
    // Individual trailing edges are not sorted: an early portrait may still be
    // visible after later landscape tiles have scrolled away.
    var low = 0;
    var high = _trailingMax.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_trailingMax[middle] <= scrollOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset) {
    // Shortest-column placement keeps leading edges in nondecreasing order.
    var low = 0;
    var high = _tiles.length;
    while (low < high) {
      final middle = (low + high) ~/ 2;
      if (_tiles[middle].scrollOffset < scrollOffset) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return math.max(0, low - 1);
  }

  @override
  SliverGridGeometry getGeometryForChildIndex(int index) {
    if (index < _tiles.length) return _tiles[index];
    // RenderSliverGrid requests geometry before checking whether a child exists.
    return SliverGridGeometry(
      scrollOffset: _trailingMax.lastOrNull ?? 0,
      crossAxisOffset: 0,
      mainAxisExtent: 0,
      crossAxisExtent: _tileWidth,
    );
  }

  @override
  double computeMaxScrollOffset(int childCount) {
    final count = math.min(childCount, _trailingMax.length);
    return count == 0 ? 0 : _trailingMax[count - 1];
  }
}
