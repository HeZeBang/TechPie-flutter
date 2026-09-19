import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:techpie/utils/platform.dart';
import 'package:techpie/widgets/blurred_app_bar.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

import '../../domain/models/bill_models.dart';
import '../../domain/models/card_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';

abstract final class GeekPayAssets {
  static const widgetBackground =
      'assets/campus_card/images/widget-background.png';
  static const cardFull = 'assets/campus_card/images/card-full.png';
  static const cardTop = 'assets/campus_card/images/card-top.png';
  static const cardBottom = 'assets/campus_card/images/card-bottom.png';
  static const online = 'assets/campus_card/images/network-online.png';
  static const offline = 'assets/campus_card/images/network-offline.png';
  static const warningOnline = 'assets/campus_card/images/network-warning.png';
}

String formatMoneyFen(
  int value, {
  bool symbol = true,
  bool fixedDecimals = false,
}) {
  final sign = value < 0 ? '-' : '';
  final absolute = value.abs();
  final yuan = absolute ~/ 100;
  final fen = absolute % 100;
  final grouped = yuan.toString().replaceAllMapped(
        RegExp(r'\B(?=(\d{3})+(?!\d))'),
        (_) => ',',
      );
  final number = fen == 0 && !fixedDecimals
      ? grouped
      : '$grouped.${fen.toString().padLeft(2, '0')}';
  return '$sign${symbol ? '¥' : ''}$number';
}

bool transactionIsIncoming(TransactionRecord record) =>
    record.amount.value > 0 && record.kind != TransactionKind.consumption;

String formatTransactionAmount(TransactionRecord record) {
  if (record.amount.value == 0) {
    return formatMoneyFen(0, fixedDecimals: true);
  }
  final incoming = transactionIsIncoming(record);
  return '${incoming ? '+' : '-'}'
      '${formatMoneyFen(record.amount.value.abs(), fixedDecimals: true)}';
}

IconData transactionIcon(BuildContext context, TransactionRecord record) =>
    switch (record.kind) {
      TransactionKind.recharge => GpPlatformIcons.recharge(context),
      TransactionKind.subsidy => GpPlatformIcons.gift(context),
      TransactionKind.transfer => GpPlatformIcons.transfer(context),
      TransactionKind.refund => GpPlatformIcons.refund(context),
      TransactionKind.adjustment => GpPlatformIcons.limits(context),
      TransactionKind.consumption => GpPlatformIcons.consumption(context),
    };

String cardTail(String masked) {
  final digits = masked.replaceAll(RegExp(r'\D'), '');
  if (digits.length <= 4) return digits;
  return digits.substring(digits.length - 4);
}

String cardholderDisplayName(String value, {required String languageCode}) {
  final normalized = value.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (languageCode == 'zh') {
    final chinese = RegExp(r'^[\u3400-\u9FFF·]{2,}').firstMatch(normalized);
    if (chinese != null) return chinese.group(0)!;
  }
  return normalized;
}

final class MaskedCardNumberText extends StatelessWidget {
  const MaskedCardNumberText({
    super.key,
    required this.maskedNumber,
    this.style,
    this.textAlign,
  });

  final String maskedNumber;
  final TextStyle? style;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final tail = cardTail(maskedNumber);
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    return Text(
      '••••\u00A0$tail',
      style: baseStyle.copyWith(letterSpacing: 0),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
    );
  }
}

/// An eCard page's frame: the feature's background, painted edge to edge.
///
/// It deliberately does not measure anything. The readable width belongs to the
/// page *body* alone ([ApplePinnedHeaderLayout.contentWidth]): a window-wide
/// window gets a window-wide navigation bar — the same bar every other TechPie
/// page shows — with the column of content centred underneath it.
final class AppleWalletPage extends StatelessWidget {
  const AppleWalletPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: context.gpColors.bg, child: child);
}

/// Pull-to-refresh control positioned below the pinned eCard header.
final class EcardSliverRefreshControl extends StatelessWidget {
  const EcardSliverRefreshControl({super.key, required this.onRefresh});

  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final color = context.gpColors.textSecondary;
    return CupertinoSliverRefreshControl(
      onRefresh: onRefresh,
      builder: (
        context,
        mode,
        pulledExtent,
        refreshTriggerPullDistance,
        refreshIndicatorExtent,
      ) {
        final progress =
            (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0);
        return Center(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: ApplePinnedHeaderLayout.contentTop,
                left: 0,
                right: 0,
                child: Center(
                  child: _indicator(mode, progress, color),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _indicator(
    RefreshIndicatorMode mode,
    double progress,
    Color color,
  ) {
    const key = Key('ecard-pull-to-refresh-indicator');
    return switch (mode) {
      RefreshIndicatorMode.drag => Opacity(
          opacity: const Interval(0, 0.35, curve: Curves.easeInOut)
              .transform(progress),
          child: CupertinoActivityIndicator.partiallyRevealed(
            key: key,
            color: color,
            progress: progress,
          ),
        ),
      RefreshIndicatorMode.armed ||
      RefreshIndicatorMode.refresh =>
        CupertinoActivityIndicator(key: key, color: color),
      RefreshIndicatorMode.done => Opacity(
          opacity: progress,
          child: CupertinoActivityIndicator(key: key, color: color),
        ),
      RefreshIndicatorMode.inactive => const SizedBox.shrink(),
    };
  }
}

/// One header action rendered by TechPie's platform navigation controls.
final class CampusCardHeaderAction {
  const CampusCardHeaderAction({
    required this.id,
    required this.icon,
    required this.sfSymbol,
    required this.label,
    required this.onPressed,
    this.key,
    this.iconSize = 24,
  });

  final String id;
  final IconData icon;
  final String sfSymbol;
  final String label;
  final VoidCallback? onPressed;
  final Key? key;
  final double iconSize;
}

final class ApplePinnedHeaderLayout extends StatelessWidget {
  const ApplePinnedHeaderLayout({
    super.key,
    required this.child,
    this.leading,
    this.title,
    this.actions = const [],
  });

  static const contentTop = 78.0;

  /// The measure of the page body on a wide window. The bar is not part of it:
  /// it spans whatever the host gives the page, which is what makes an eCard
  /// page look like the rest of TechPie.
  static const contentWidth = 560.0;

  final Widget child;
  final CampusCardHeaderAction? leading;
  final String? title;
  final List<CampusCardHeaderAction> actions;

  @override
  Widget build(BuildContext context) {
    final resolvedTitle = title ?? 'eCard';
    return SafeArea(
      bottom: false,
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: contentWidth),
                child: child,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: isIos()
                ? ColoredBox(
                    color: context.gpColors.bg,
                    child: _buildIosHeader(resolvedTitle),
                  )
                : BlurredAppBar(
                    automaticallyImplyLeading: false,
                    leading: leading == null ? null : _materialButton(leading!),
                    title: Text(resolvedTitle),
                    actions: actions.map(_materialButton).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildIosHeader(String resolvedTitle) => IosNativeNavigationBar(
        title: resolvedTitle,
        leadingItems: [
          if (leading != null) _nativeItem(leading!, 'leading-main'),
        ],
        // UIKit lays out trailing items from the trailing edge inward.
        trailingItems: [
          for (final action in actions.reversed)
            _nativeItem(action, 'trailing-${action.id}'),
        ],
        onItemPressed: (id) {
          if (id == leading?.id) {
            leading?.onPressed?.call();
            return;
          }
          for (final action in actions) {
            if (action.id == id) {
              action.onPressed?.call();
              return;
            }
          }
        },
      );

  IosNativeNavigationBarItem _nativeItem(
    CampusCardHeaderAction action,
    String placementGroup,
  ) =>
      IosNativeNavigationBarItem(
        id: action.id,
        sfSymbol: action.sfSymbol,
        accessibilityLabel: action.label,
        enabled: action.onPressed != null,
        placementGroup: placementGroup,
      );

  Widget _materialButton(CampusCardHeaderAction action) => IconButton(
        key: action.key,
        icon: Icon(action.icon, size: action.iconSize),
        tooltip: action.label,
        onPressed: action.onPressed,
      );
}

final class CampusWalletCard extends StatelessWidget {
  const CampusWalletCard({
    super.key,
    required this.card,
    this.onTap,
    this.heroTag = 'campus-card',
    this.compact = false,
  });

  final CampusCard card;
  final VoidCallback? onTap;
  final Object heroTag;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = compact ? 10.0 : 20.0;
    final cardView = Hero(
      tag: heroTag,
      createRectTween: (begin, end) =>
          MaterialRectCenterArcTween(begin: begin, end: end),
      child: Material(
        color: GpTokens.cardCanvas,
        elevation: 0,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: 707 / 445,
          child: LayoutBuilder(
            builder: (context, constraints) => Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  GeekPayAssets.cardFull,
                  gaplessPlayback: true,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
                if (!compact || constraints.maxWidth >= 120)
                  Positioned(
                    left: compact ? 14 : 22,
                    right: compact ? 14 : 22,
                    bottom: compact ? 10 : 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            card.ownerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF242428),
                              fontSize: compact ? 10 : 15,
                              fontWeight: FontWeight.w600,
                              height: 1.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        MaskedCardNumberText(
                          maskedNumber: card.maskedNumber,
                          style: TextStyle(
                            color: const Color(0xFF242428),
                            fontSize: compact ? 9 : 14,
                            fontWeight: FontWeight.w500,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    return Semantics(
      button: onTap != null,
      label: '上海科技大学 eCard',
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.13),
                blurRadius: compact ? 12 : 26,
                offset: Offset(0, compact ? 6 : 14),
              ),
            ],
          ),
          child: onTap == null
              ? cardView
              : Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(radius),
                    onTap: onTap,
                    child: cardView,
                  ),
                ),
        ),
      ),
    );
  }
}

final class AppleSegmentedControl extends StatelessWidget {
  const AppleSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    return SizedBox(
      width: double.infinity,
      child: CupertinoSlidingSegmentedControl<int>(
        groupValue: selectedIndex,
        backgroundColor: c.surfaceDisabled,
        thumbColor: c.surface,
        children: {
          for (var index = 0; index < labels.length; index++)
            index: Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Text(
                labels[index],
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        },
        onValueChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

final class AppleSection extends StatelessWidget {
  const AppleSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.padding = EdgeInsets.zero,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 8),
              child: Text(
                header!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: c.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                for (var index = 0; index < children.length; index++) ...[
                  children[index],
                  if (index != children.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 18, right: 18),
                      child: Divider(height: 1, color: c.border),
                    ),
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Text(
                footer!,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: c.textSecondary,
                      height: 1.4,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

final class AppleListRow extends StatelessWidget {
  const AppleListRow({
    super.key,
    required this.label,
    this.value,
    this.icon,
    this.iconColor,
    this.onTap,
    this.trailing,
    this.destructive = false,
    this.valueMaxLines = 1,
    this.verticalPadding = 11,
  });

  final String label;
  final String? value;
  final IconData? icon;
  final Color? iconColor;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool destructive;
  final int? valueMaxLines;
  final double verticalPadding;

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    final foreground = destructive ? c.danger : c.textPrimary;
    return MergeSemantics(
      child: Semantics(
        button: onTap != null,
        onTap: onTap,
        child: _ImmediatePressSurface(
          onTap: onTap,
          pressedColor: c.surfaceDisabled,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: 18,
                vertical: verticalPadding,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    SizedBox.square(
                      dimension: 24,
                      child: Center(
                        child: Icon(
                          icon,
                          size: 22,
                          color: iconColor ?? foreground,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 24,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          label,
                          textAlign: TextAlign.left,
                          style: TextStyle(
                            color: foreground,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (value != null) ...[
                    const SizedBox(width: 12),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          value!,
                          maxLines: valueMaxLines,
                          overflow: valueMaxLines == 1
                              ? TextOverflow.ellipsis
                              : TextOverflow.visible,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                  if (trailing != null) ...[
                    const SizedBox(width: 10),
                    trailing!,
                  ] else if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      GpPlatformIcons.forward(context),
                      size: 17,
                      color: c.textDisabled,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A grouped transaction sliver that builds rows near the viewport only.
final class TransactionList extends StatelessWidget {
  const TransactionList({
    super.key,
    required this.items,
    this.onTap,
    this.emptyLabel,
  });

  final List<TransactionRecord> items;
  final ValueChanged<TransactionRecord>? onTap;
  final String? emptyLabel;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return SliverToBoxAdapter(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 18),
          decoration: BoxDecoration(
            color: context.gpColors.surface,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            emptyLabel ?? '这个时间范围内没有交易',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.gpColors.textSecondary),
          ),
        ),
      );
    }
    return SliverList.builder(
      itemCount: items.length,
      itemBuilder: (context, index) {
        final first = index == 0;
        final last = index == items.length - 1;
        final row = ColoredBox(
          color: context.gpColors.surface,
          child: Column(
            children: [
              _TransactionRow(record: items[index], onTap: onTap),
              if (!last)
                Padding(
                  padding: const EdgeInsets.only(left: 72, right: 18),
                  child: Divider(height: 1, color: context.gpColors.border),
                ),
            ],
          ),
        );
        return ClipRRect(
          key: ValueKey(items[index].id),
          borderRadius: BorderRadius.vertical(
            top: first ? const Radius.circular(24) : Radius.zero,
            bottom: last ? const Radius.circular(24) : Radius.zero,
          ),
          child: row,
        );
      },
    );
  }
}

final class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.record, required this.onTap});

  final TransactionRecord record;
  final ValueChanged<TransactionRecord>? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.gpColors;
    final incoming = transactionIsIncoming(record);
    final amount = formatTransactionAmount(record);
    final date = DateFormat('yyyy-MM-dd HH:mm:ss').format(
      record.occurredAt.toLocal(),
    );
    final icon = transactionIcon(context, record);
    return _ImmediatePressSurface(
      onTap: onTap == null ? null : () => onTap!(record),
      pressedColor: c.surfaceDisabled,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.action.withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 21, color: c.action),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    record.merchantName?.trim().isNotEmpty == true
                        ? record.merchantName!
                        : '--',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    date,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amount,
              style: TextStyle(
                color: incoming ? c.success : c.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 5),
              Icon(
                GpPlatformIcons.forward(context),
                size: 15,
                color: c.textDisabled,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _ImmediatePressSurface extends StatefulWidget {
  const _ImmediatePressSurface({
    required this.onTap,
    required this.pressedColor,
    required this.child,
  });

  final VoidCallback? onTap;
  final Color pressedColor;
  final Widget child;

  @override
  State<_ImmediatePressSurface> createState() => _ImmediatePressSurfaceState();
}

final class _ImmediatePressSurfaceState extends State<_ImmediatePressSurface> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value || (value && widget.onTap == null)) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _ImmediatePressSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.onTap == null && _pressed) _pressed = false;
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
          child: ColoredBox(
            color: _pressed ? widget.pressedColor : Colors.transparent,
            child: widget.child,
          ),
        ),
      );
}

final class AnimatedSuccessCheck extends StatefulWidget {
  const AnimatedSuccessCheck({
    super.key,
    this.size = 104,
    this.color,
    this.reduceMotion = false,
    this.feedback,
  });

  final double size;
  final Color? color;
  final bool reduceMotion;
  final FeedbackPort? feedback;

  @override
  State<AnimatedSuccessCheck> createState() => _AnimatedSuccessCheckState();
}

class _AnimatedSuccessCheckState extends State<AnimatedSuccessCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _circle;
  late final Animation<double> _check;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    final duration = widget.reduceMotion
        ? const Duration(milliseconds: 240)
        : const Duration(milliseconds: 720);
    _controller = AnimationController(vsync: this, duration: duration);
    _circle = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0, 0.58, curve: Curves.easeOutCubic),
    );
    _check = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.42, 0.88, curve: Curves.easeOutCubic),
    );
    _scale = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0.84, end: 1.07), weight: 72),
        TweenSequenceItem(tween: Tween(begin: 1.07, end: 1), weight: 28),
      ],
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(widget.feedback?.play(FeedbackEvent.paymentSuccess));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.color ?? context.gpColors.action;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Transform.scale(
        scale: widget.reduceMotion ? 1 : _scale.value,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SuccessCheckPainter(
            circleProgress: _circle.value,
            checkProgress: _check.value,
            color: color,
          ),
        ),
      ),
    );
  }
}

final class _SuccessCheckPainter extends CustomPainter {
  const _SuccessCheckPainter({
    required this.circleProgress,
    required this.checkProgress,
    required this.color,
  });

  final double circleProgress;
  final double checkProgress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );
    canvas.drawArc(rect, -1.5708, 6.28318 * circleProgress, false, paint);

    final check = Path()
      ..moveTo(size.width * 0.28, size.height * 0.53)
      ..lineTo(size.width * 0.44, size.height * 0.68)
      ..lineTo(size.width * 0.75, size.height * 0.35);
    final metric = check.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * checkProgress),
      paint,
    );
  }

  @override
  bool shouldRepaint(_SuccessCheckPainter old) =>
      old.circleProgress != circleProgress ||
      old.checkProgress != checkProgress ||
      old.color != color;
}
