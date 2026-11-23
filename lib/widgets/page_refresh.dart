import 'package:flutter/material.dart';

import '../utils/platform.dart';
import 'adaptive_feedback.dart';

/// A mouse-accessible refresh action for native desktop pages.
///
/// Owns the pending operation so every page awaits its entire refresh before
/// allowing another click. Existing background loads can also disable it.
class PageRefreshButton extends StatefulWidget {
  const PageRefreshButton({
    super.key,
    required this.onRefresh,
    this.enabled = true,
    this.refreshing = false,
  });

  final Future<void> Function() onRefresh;
  final bool enabled;
  final bool refreshing;

  @override
  State<PageRefreshButton> createState() => _PageRefreshButtonState();
}

class _PageRefreshButtonState extends State<PageRefreshButton> {
  bool _pending = false;

  Future<void> _refresh() async {
    if (_pending || widget.refreshing || !widget.enabled) return;
    setState(() => _pending = true);
    try {
      await widget.onRefresh();
    } catch (_) {
      if (mounted) {
        showAdaptiveFeedback(
          context: context,
          message: '刷新失败，请重试',
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _pending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktop()) return const SizedBox.shrink();
    final busy = _pending || widget.refreshing;
    return IconButton(
      tooltip: busy ? '正在刷新' : '刷新',
      onPressed: widget.enabled && !busy ? _refresh : null,
      icon: busy
          ? const SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                semanticsLabel: '正在刷新',
              ),
            )
          : const Icon(Icons.refresh),
    );
  }
}

/// Desktop uses the page action; other platforms retain their pull gesture.
class PageRefreshIndicator extends StatelessWidget {
  const PageRefreshIndicator({
    super.key,
    required this.onRefresh,
    required this.child,
    this.notificationPredicate = defaultScrollNotificationPredicate,
  });

  final Future<void> Function() onRefresh;
  final Widget child;
  final ScrollNotificationPredicate notificationPredicate;

  @override
  Widget build(BuildContext context) => isDesktop()
      ? child
      : RefreshIndicator(
          onRefresh: onRefresh,
          notificationPredicate: notificationPredicate,
          child: child,
        );
}
