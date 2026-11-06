import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../utils/adaptive_motion.dart';
import '../domain/genai_image_caption.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_hover_region.dart';
import 'genai_icons.dart';
import 'genai_image_actions.dart';
import 'genai_image_dimensions.dart';
import 'genai_theme.dart';

/// A lazy image-history sliver whose tile sizes follow the decoded images.
class GenAiImageGallery extends StatefulWidget {
  const GenAiImageGallery({
    super.key,
    required this.records,
    required this.imageProvider,
    required this.onOpen,
    this.onReference,
    this.stageWidth,
  });

  final List<GenAiImageRecord> records;
  final ImageProvider<Object> Function(Uri) imageProvider;
  final ValueChanged<GenAiImageRecord> onOpen;

  /// Adds "用作参考" to a tile's context menu when the host can accept one.
  final ValueChanged<GenAiImageRecord>? onReference;

  /// The width of the surface the gallery is embedded in, matching the
  /// workspace's cached stage width. The compact tile treatment follows this
  /// value rather than the gallery sliver's own width: the studio places the
  /// gallery beside a fixed form, so a narrow column on a wide surface still
  /// belongs to the desktop layout. Falls back to the window width when the
  /// host does not measure its stage.
  final double? stageWidth;

  @override
  State<GenAiImageGallery> createState() => _GenAiImageGalleryState();
}

class _GenAiImageGalleryState extends State<GenAiImageGallery> {
  // Draft desktop gallery: `column-gap:14px`, `margin-bottom:17px`, 11px corner.
  static const _columnSpacing = 14.0;
  static const _rowSpacing = 17.0;
  static const _radius = 11.0;

  // Draft compact gallery: 10px gaps and a 9px corner.
  static const _compactColumnSpacing = 10.0;
  static const _compactRowSpacing = 10.0;
  static const _compactRadius = 9.0;

  /// The draft switches to the tighter tile treatment at a 680px stage.
  static const _compactBreakpoint = 680.0;
  final _aspectRatios = <Uri, double>{};
  final _pendingRatios = <Uri, double>{};
  bool _updateScheduled = false;

  /// The measured ratios of [widget.records] in tile order. The list is
  /// replaced only when a ratio actually changes, so the grid delegate and its
  /// geometry cache can compare inputs by identity instead of rescanning the
  /// whole history on every layout pass.
  List<double> _ratios = const <double>[];
  final _geometryCache = _MasonryGeometryCache();

  @override
  void initState() {
    super.initState();
    _rebuildRatios();
  }

  void _rebuildRatios() {
    final next = [
      for (final record in widget.records) _aspectRatios[record.images.firstOrNull] ?? 1.0,
    ];
    // Keeping the previous list when the values did not move leaves the cached
    // masonry geometry valid across ordinary rebuilds.
    if (listEquals(next, _ratios)) return;
    _ratios = List<double>.unmodifiable(next);
  }

  bool get _touch => GenAiLayout.touchPlatform;

  @override
  void didUpdateWidget(covariant GenAiImageGallery oldWidget) {
    super.didUpdateWidget(oldWidget);
    final active = widget.records.map((record) => record.images.firstOrNull).toSet();
    _aspectRatios.removeWhere((uri, _) => !active.contains(uri));
    _pendingRatios.removeWhere((uri, _) => !active.contains(uri));
    _rebuildRatios();
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
      if (updates.isNotEmpty) {
        setState(() {
          _aspectRatios.addAll(updates);
          _rebuildRatios();
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => SliverLayoutBuilder(
        builder: (context, constraints) {
          // The compact treatment tracks the stage the gallery belongs to, not
          // the sliver's own width: the studio places the gallery beside a
          // fixed form on wide layouts. Columns still follow the space the
          // sliver actually has.
          final stageWidth = widget.stageWidth ?? MediaQuery.sizeOf(context).width;
          final compact = stageWidth <= _compactBreakpoint;
          final columnSpacing = compact ? _compactColumnSpacing : _columnSpacing;
          final rowSpacing = compact ? _compactRowSpacing : _rowSpacing;
          final radius = BorderRadius.circular(compact ? _compactRadius : _radius);
          final columns = constraints.crossAxisExtent >= 900
              ? 3
              : constraints.crossAxisExtent >= 260
                  ? 2
                  : 1;
          return SliverGrid(
            key: const ValueKey('genai-image-gallery'),
            gridDelegate: _MasonryGridDelegate(
              columns: columns,
              columnSpacing: columnSpacing,
              rowSpacing: rowSpacing,
              aspectRatios: _ratios,
              geometryCache: _geometryCache,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final record = widget.records[index];
                final caption = genAiImageCaption(record.prompt, title: record.title);
                final uri = record.images.firstOrNull;
                final palette = GenAiPalette.of(context);
                return GenAiHoverRegion(
                  key: ValueKey('genai-image-${record.id}'),
                  always: compact || _touch,
                  builder: (context, revealed) => Semantics(
                    button: true,
                    label: '查看图片',
                    onTap: () => widget.onOpen(record),
                    child: ClipRRect(
                      borderRadius: radius,
                      child: Material(
                        color: palette.soft,
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: radius,
                          onTap: () => widget.onOpen(record),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (uri == null)
                                const _ImageUnavailable()
                              else
                                GenAiImageActions(
                                  image: widget.imageProvider(uri),
                                  link: uri,
                                  showMenuButton: false,
                                  onOpen: () => widget.onOpen(record),
                                  onReference: widget.onReference == null
                                      ? null
                                      : () => widget.onReference!(record),
                                  child: SizedBox.expand(
                                    child: _HoverScale(
                                      child: _MeasuredImage(
                                        key: ValueKey(uri),
                                        image: widget.imageProvider(uri),
                                        onAspectRatio: (ratio) => _imageMeasured(uri, ratio),
                                      ),
                                    ),
                                  ),
                                ),
                              if (record.images.length > 1)
                                PositionedDirectional(
                                  top: 8,
                                  start: 8,
                                  child: _ImageBadge(
                                    icon: const GenAiIcon(GenAiGlyph.image),
                                    label: '${record.images.length}',
                                  ),
                                ),
                              PositionedDirectional(
                                start: 0,
                                end: 0,
                                bottom: 0,
                                child: GenAiReveal(
                                  visible: revealed,
                                  child: _GalleryCaption(caption: caption, compact: compact),
                                ),
                              ),
                            ],
                          ),
                        ),
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

/// The draft scales the artwork 1.025 on hover. Reduced-motion layouts keep
/// the tile still instead of animating a zoom.
class _HoverScale extends StatefulWidget {
  const _HoverScale({required this.child});

  final Widget child;

  @override
  State<_HoverScale> createState() => _HoverScaleState();
}

class _HoverScaleState extends State<_HoverScale> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final animate = appAnimationsEnabled(context);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: animate && _hovered ? 1.025 : 1,
        duration: animate ? const Duration(milliseconds: 350) : Duration.zero,
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

/// The caption sits over the image's bottom edge, so the tile's height stays
/// proportional to the artwork rather than reserving space below it.
class _GalleryCaption extends StatelessWidget {
  const _GalleryCaption({required this.caption, required this.compact});

  final String caption;

  /// Draws the draft's tighter mobile caption inside a narrow gallery.
  final bool compact;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0x99000000)],
          ),
        ),
        child: Padding(
          padding: compact
              ? const EdgeInsetsDirectional.fromSTEB(10, 22, 10, 9)
              : const EdgeInsetsDirectional.fromSTEB(14, 30, 14, 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.3,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const GenAiIcon(GenAiGlyph.full, size: 15, color: Colors.white),
            ],
          ),
        ),
      );
}

class _ImageBadge extends StatelessWidget {
  const _ImageBadge({required this.label, this.icon});

  final String label;
  final Widget? icon;

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
              IconTheme.merge(
                data: IconThemeData(size: 14, color: colors.onInverseSurface),
                child: icon!,
              ),
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
              GenAiIcon(GenAiGlyph.image, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 8),
              const Text('预览暂不可用', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _MeasuredImage extends StatelessWidget {
  const _MeasuredImage({super.key, required this.image, required this.onAspectRatio});
  final ImageProvider<Object> image;
  final ValueChanged<double> onAspectRatio;

  @override
  Widget build(BuildContext context) => GenAiImageDimensions(
        image: image,
        onSize: (size) => onAspectRatio(
          size != null && size.width > 0 && size.height > 0 ? size.width / size.height : 1.0,
        ),
        builder: (context, _) => Image(
          image: image,
          fit: BoxFit.contain,
          excludeFromSemantics: true,
          frameBuilder: (context, child, frame, synchronouslyLoaded) =>
              frame != null || synchronouslyLoaded
                  ? child
                  : Center(
                      child: GenAiIcon(
                        GenAiGlyph.image,
                        size: 28,
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
          errorBuilder: (_, __, ___) => const _ImageUnavailable(),
        ),
      );
}

class _MasonryGridDelegate extends SliverGridDelegate {
  const _MasonryGridDelegate({
    required this.columns,
    required this.columnSpacing,
    required this.rowSpacing,
    required this.aspectRatios,
    required this.geometryCache,
  });

  final int columns;
  final double columnSpacing;
  final double rowSpacing;

  /// State-owned and only replaced when a measured ratio changes, so equal
  /// values are also the same list instance.
  final List<double> aspectRatios;

  /// Shared by every delegate the gallery builds, so an unchanged layout is
  /// reused instead of re-walking the entire history on each pass.
  final _MasonryGeometryCache geometryCache;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) => geometryCache.layoutFor(
        columns: columns,
        columnSpacing: columnSpacing,
        rowSpacing: rowSpacing,
        aspectRatios: aspectRatios,
        crossAxisExtent: constraints.crossAxisExtent,
        reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
      );

  @override
  bool shouldRelayout(covariant _MasonryGridDelegate oldDelegate) =>
      columns != oldDelegate.columns ||
      columnSpacing != oldDelegate.columnSpacing ||
      rowSpacing != oldDelegate.rowSpacing ||
      !identical(aspectRatios, oldDelegate.aspectRatios);
}

/// Memoizes the masonry geometry walk for its immutable inputs.
///
/// Scrolling only changes the sliver's scroll offset, which the walk does not
/// read: without this cache every layout pass would be O(total history).
class _MasonryGeometryCache {
  _MasonryGridLayout? _layout;
  List<double>? _aspectRatios;
  int? _columns;
  double? _columnSpacing;
  double? _rowSpacing;
  double? _crossAxisExtent;
  bool? _reverseCrossAxis;

  SliverGridLayout layoutFor({
    required int columns,
    required double columnSpacing,
    required double rowSpacing,
    required List<double> aspectRatios,
    required double crossAxisExtent,
    required bool reverseCrossAxis,
  }) {
    final cached = _layout;
    if (cached != null &&
        identical(_aspectRatios, aspectRatios) &&
        _columns == columns &&
        _columnSpacing == columnSpacing &&
        _rowSpacing == rowSpacing &&
        _crossAxisExtent == crossAxisExtent &&
        _reverseCrossAxis == reverseCrossAxis) {
      return cached;
    }
    final layout = _MasonryGridLayout(
      columns: columns,
      columnSpacing: columnSpacing,
      rowSpacing: rowSpacing,
      aspectRatios: aspectRatios,
      crossAxisExtent: crossAxisExtent,
      reverseCrossAxis: reverseCrossAxis,
    );
    _layout = layout;
    _aspectRatios = aspectRatios;
    _columns = columns;
    _columnSpacing = columnSpacing;
    _rowSpacing = rowSpacing;
    _crossAxisExtent = crossAxisExtent;
    _reverseCrossAxis = reverseCrossAxis;
    return layout;
  }
}

class _MasonryGridLayout extends SliverGridLayout {
  _MasonryGridLayout({
    required int columns,
    required double columnSpacing,
    required double rowSpacing,
    required List<double> aspectRatios,
    required double crossAxisExtent,
    required bool reverseCrossAxis,
  }) : _tileWidth = math.max(0.0, (crossAxisExtent - columnSpacing * (columns - 1)) / columns) {
    final columnOffsets = List<double>.filled(columns, 0);
    var trailingMax = 0.0;
    for (final aspectRatio in aspectRatios) {
      var column = 0;
      for (var candidate = 1; candidate < columns; candidate++) {
        if (columnOffsets[candidate] < columnOffsets[column]) column = candidate;
      }
      final ratio = aspectRatio.isFinite && aspectRatio > 0 ? aspectRatio : 1.0;
      // Only bound the tile. BoxFit.contain still displays the complete image.
      final extent = _tileWidth / ratio.clamp(1 / 3, 3.0);
      final geometry = SliverGridGeometry(
        scrollOffset: columnOffsets[column],
        crossAxisOffset:
            (reverseCrossAxis ? columns - 1 - column : column) * (_tileWidth + columnSpacing),
        mainAxisExtent: extent,
        crossAxisExtent: _tileWidth,
      );
      _tiles.add(geometry);
      columnOffsets[column] = geometry.trailingScrollOffset + rowSpacing;
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
