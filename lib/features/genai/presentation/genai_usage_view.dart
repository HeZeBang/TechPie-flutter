import 'dart:async';

import 'package:flutter/material.dart';

import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';
import 'genai_copy.dart';

class GenAiUsageView extends StatefulWidget {
  const GenAiUsageView({super.key, required this.workspace});
  final GenAiWorkspaceController workspace;
  @override
  State<GenAiUsageView> createState() => _GenAiUsageViewState();
}

class _GenAiUsageViewState extends State<GenAiUsageView> {
  final _orders = <GenAiUsageOrder>[];
  GenAiUsageSummary? _usage;
  GenAiCancellation? _operation;
  GenAiFailure? _loadFailure;
  bool _pageFailure = false;
  bool _loading = false;
  bool _more = false;
  int _page = 1;
  late Object? _scope = widget.workspace.accountScope;
  late int _revision = widget.workspace.sessions.revision;

  late bool _connected = widget.workspace.connected;

  @override
  void initState() {
    super.initState();
    widget.workspace.addListener(_changed);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(covariant GenAiUsageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.workspace == widget.workspace) return;
    oldWidget.workspace.removeListener(_changed);
    widget.workspace.addListener(_changed);
    _resetSession();
  }

  void _changed() {
    if (_scope == widget.workspace.accountScope &&
        _revision == widget.workspace.sessions.revision &&
        _connected == widget.workspace.connected) {
      return;
    }
    _resetSession();
  }

  void _resetSession() {
    _operation?.cancel();
    _operation = null;
    setState(() {
      _scope = widget.workspace.accountScope;
      _revision = widget.workspace.sessions.revision;
      _connected = widget.workspace.connected;
      _orders.clear();
      _usage = null;
      _more = false;
      _loading = false;
      _pageFailure = false;
      _loadFailure = _connected
          ? null
          : const GenAiFailure(GenAiFailureKind.authenticationRequired);
    });
    if (_connected) unawaited(_load());
  }

  Future<void> _load({bool more = false}) async {
    if (_loading ||
        _scope != widget.workspace.accountScope ||
        _revision != widget.workspace.sessions.revision) {
      return;
    }
    final operation = GenAiCancellation();
    _operation = operation;
    setState(() {
      _loading = true;
      _loadFailure = null;
      _pageFailure = false;
    });
    try {
      final repository = widget.workspace.repository;
      final page = more ? _page + 1 : 1;
      final summary = more ? _usage : await repository.usageSummary(operation);
      final orders = await repository.usageOrders(operation, page: page);
      operation.throwIfCancelled();
      if (!mounted) return;
      _usage = summary;
      if (!more) _orders.clear();
      _orders.addAll(orders.records);
      _page = page;
      _more = orders.hasMore;
    } catch (error) {
      if (mounted && !operation.isCancelled) {
        _pageFailure = more;
        _loadFailure = error is GenAiFailure
            ? error
            : const GenAiFailure(GenAiFailureKind.transport);
      }
    } finally {
      if (identical(_operation, operation)) {
        _operation = null;
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_changed);
    _operation?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      SizedBox(height: 2, child: _loading ? const LinearProgressIndicator() : null),
      if (_loadFailure != null && !_pageFailure)
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Text(genAiFailureText(_loadFailure!)),
              if (_connected)
                TextButton(onPressed: _loading ? null : _load, child: const Text('重试加载')),
            ],
          ),
        ),
      Expanded(child: _statistics()),
    ],
  );

  Widget _loadMore() => _more
      ? TextButton(
          onPressed: _loading ? null : () => _load(more: true),
          child: Text(_pageFailure ? '重试加载' : '加载更多'),
        )
      : const SizedBox.shrink();

  Widget _statistics() {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final line = theme.colorScheme.outlineVariant;
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
      children: [
        Text('结算可能延迟', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        if (_usage?.hasUnavailableQuotas ?? false) Text('部分额度暂不可用', style: TextStyle(color: muted)),
        for (final quota in _usage?.quotas ?? <GenAiQuota>[])
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(quota.name, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
                const SizedBox(height: 6),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '${quota.remaining}',
                        style: const TextStyle(fontSize: 34, letterSpacing: -1),
                      ),
                      TextSpan(
                        text: ' 剩余',
                        style: TextStyle(fontSize: 15, color: muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    minHeight: 5,
                    value: quota.total <= 0
                        ? 0
                        : (quota.remaining / quota.total).clamp(0, 1).toDouble(),
                    backgroundColor: line,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '已用 ${quota.used} / 总额 ${quota.total}',
                  style: theme.textTheme.bodySmall?.copyWith(color: muted),
                ),
              ],
            ),
          ),
        const SizedBox(height: 32),
        Text('消费明细', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        if (_orders.isEmpty && !_loading && _loadFailure == null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text('没有消费记录', style: TextStyle(color: muted)),
          ),
        for (final order in _orders)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: line)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.model, style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (order.time.isNotEmpty) order.time,
                          '输入 ${order.inputTokens} Token',
                          '输出 ${order.outputTokens} Token',
                          if (order.imageTokens != 0) '图片 ${order.imageTokens} Token',
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(color: muted, height: 1.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Text('${order.used} 额度', style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        if (_pageFailure && _loadFailure != null)
          Text(genAiFailureText(_loadFailure!), textAlign: TextAlign.center),
        _loadMore(),
      ],
    );
  }
}
