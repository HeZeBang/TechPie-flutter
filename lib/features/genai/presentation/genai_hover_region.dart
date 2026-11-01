import 'package:flutter/material.dart';

/// Reveals secondary actions while a pointer hovers the region or focus is
/// inside it. Hidden actions stay laid out and tappable, so layout never
/// jumps and touch layouts can simply pass [always].
class GenAiHoverRegion extends StatefulWidget {
  const GenAiHoverRegion({super.key, required this.builder, this.always = false});

  final Widget Function(BuildContext context, bool revealed) builder;
  final bool always;

  @override
  State<GenAiHoverRegion> createState() => _GenAiHoverRegionState();
}

class _GenAiHoverRegionState extends State<GenAiHoverRegion> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: widget.builder(context, widget.always || _hovered || _focused),
        ),
      );
}

/// Fades secondary actions in and out without removing them from hit testing.
class GenAiReveal extends StatelessWidget {
  const GenAiReveal({super.key, required this.visible, required this.child});

  final bool visible;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: const Duration(milliseconds: 120),
        // Screen readers reach the actions without hovering first.
        alwaysIncludeSemantics: true,
        child: child,
      );
}
