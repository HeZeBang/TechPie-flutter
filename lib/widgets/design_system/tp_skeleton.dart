import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_density.dart';
import '../../theme/tp_tokens.dart';
import 'tp_card.dart';

/// Pure-Dart subtle pulse skeleton block respecting reduced-motion settings.
class TpSkeleton extends StatefulWidget {
  const TpSkeleton({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = TpTokens.radiusS,
    this.isCircle = false,
    this.margin,
  });

  final double? width;
  final double height;
  final double borderRadius;
  final bool isCircle;
  final EdgeInsetsGeometry? margin;

  @override
  State<TpSkeleton> createState() => _TpSkeletonState();
}

class _TpSkeletonState extends State<TpSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _pulse = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      unawaited(_controller.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final box = AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) {
        final fill =
            Color.lerp(colors.surfaceSubtle, colors.surfacePressed, _pulse.value) ??
                colors.surfaceSubtle;
        return Container(
          width: widget.isCircle ? (widget.width ?? widget.height) : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: fill,
            shape: widget.isCircle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.isCircle
                ? null
                : BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );

    if (widget.margin == null) return box;
    return Padding(padding: widget.margin!, child: box);
  }
}

/// Placeholder card matching [TpCard] surface contrast and [TpDensity] spacing.
class TpSkeletonCard extends StatelessWidget {
  const TpSkeletonCard({
    super.key,
    this.showLeadingAvatar = false,
    this.avatarSize = 36,
    this.lineCount = 2,
    this.showTrailingBadge = false,
    this.padding,
  });

  final bool showLeadingAvatar;
  final double avatarSize;
  final int lineCount;
  final bool showTrailingBadge;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final density = context.tpDensity;
    return TpCard(
      padding: padding ?? density.cardPadding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showLeadingAvatar) ...[
            TpSkeleton(
              width: avatarSize,
              height: avatarSize,
              borderRadius: TpTokens.radiusS,
            ),
            const SizedBox(width: TpTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: 0.56,
                          child: TpSkeleton(
                            width: double.infinity,
                            height: 15,
                            borderRadius: TpTokens.radiusXs,
                          ),
                        ),
                      ),
                    ),
                    if (showTrailingBadge) ...[
                      const SizedBox(width: TpTokens.space2),
                      const TpSkeleton(
                        width: 52,
                        height: 20,
                        borderRadius: TpTokens.radiusPill,
                      ),
                    ],
                  ],
                ),
                for (var i = 0; i < lineCount; i++) ...[
                  const SizedBox(height: TpTokens.space2),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: FractionallySizedBox(
                      widthFactor: i == lineCount - 1 ? 0.65 : 0.92,
                      child: const TpSkeleton(
                        width: double.infinity,
                        height: 12,
                        borderRadius: TpTokens.radiusXs,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical group of [TpSkeletonCard] placeholders for initial page loads.
class TpSkeletonList extends StatelessWidget {
  const TpSkeletonList({
    super.key,
    this.itemCount = 3,
    this.lineCount = 2,
    this.showLeadingAvatar = false,
    this.showTrailingBadge = false,
    this.scrollable = false,
    this.padding,
  });

  final int itemCount;
  final int lineCount;
  final bool showLeadingAvatar;
  final bool showTrailingBadge;
  final bool scrollable;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final density = context.tpDensity;
    if (scrollable) {
      return ListView.separated(
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (_, __) => SizedBox(height: density.sectionGap),
        itemBuilder: (_, __) => TpSkeletonCard(
          lineCount: lineCount,
          showLeadingAvatar: showLeadingAvatar,
          showTrailingBadge: showTrailingBadge,
        ),
      );
    }

    final column = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < itemCount; i++) ...[
          if (i > 0) SizedBox(height: density.sectionGap),
          TpSkeletonCard(
            lineCount: lineCount,
            showLeadingAvatar: showLeadingAvatar,
            showTrailingBadge: showTrailingBadge,
          ),
        ],
      ],
    );

    if (padding == null) return column;
    return Padding(padding: padding!, child: column);
  }
}
