import 'dart:async';

import 'package:flutter/material.dart';

/// Brief branded page shown while the app hands off from the platform launch
/// screen to the first Flutter page.
class StartupPage extends StatefulWidget {
  const StartupPage({
    super.key,
    required this.child,
    this.minimumDuration = const Duration(milliseconds: 800),
  });

  final Widget child;
  final Duration minimumDuration;

  @override
  State<StartupPage> createState() => _StartupPageState();
}

class _StartupPageState extends State<StartupPage> {
  bool _finished = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.minimumDuration, () {
      if (!mounted) return;
      setState(() => _finished = true);
    });
  }

  @override
  void didUpdateWidget(covariant StartupPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.minimumDuration != widget.minimumDuration) {
      _timer?.cancel();
      _timer = Timer(widget.minimumDuration, () {
        if (!mounted) return;
        setState(() => _finished = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (!_finished)
          ColoredBox(
            color: colorScheme.surface,
            child: SafeArea(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/logo/Logo-1.png',
                      width: 120,
                      height: 120,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'TechPie',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
