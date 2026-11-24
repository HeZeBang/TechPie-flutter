import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/library_reservation_service.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class LibraryReservationRecordsPage extends StatefulWidget {
  const LibraryReservationRecordsPage({
    super.key,
    required this.service,
    required this.onCancelled,
  });

  final LibraryReservationService service;
  final VoidCallback onCancelled;

  @override
  State<LibraryReservationRecordsPage> createState() =>
      _LibraryReservationRecordsPageState();
}

class _LibraryReservationRecordsPageState
    extends State<LibraryReservationRecordsPage> {
  AuthService? _auth;
  ThirdPartyAuthService? _thirdPartyAuth;
  String? _primaryOwner;
  String? _campusOwner;
  List<LibraryReservationRecord> _records = const [];
  bool _history = false;
  bool _loading = true;
  bool _hasMore = false;
  bool _reopenRequired = false;
  int _page = 1;
  int _request = 0;
  String? _error;
  String? _cancellingId;
  bool _confirming = false;

  bool get _sameIdentity =>
      _auth!.isLoggedIn &&
      _auth!.session?.userId == _primaryOwner &&
      _thirdPartyAuth!.campusWebSession.owner == _campusOwner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_auth != null) return;
    final services = ServiceProvider.of(context);
    _auth = services.authService;
    _thirdPartyAuth = services.thirdPartyAuthService;
    _primaryOwner = _auth!.session?.userId;
    _campusOwner = _thirdPartyAuth!.campusWebSession.owner;
    _auth!.addListener(_identityChanged);
    _thirdPartyAuth!.addListener(_identityChanged);
    if (_auth!.isLoggedIn) {
      unawaited(_load());
    } else {
      _loading = false;
    }
  }

  @override
  void dispose() {
    _auth?.removeListener(_identityChanged);
    _thirdPartyAuth?.removeListener(_identityChanged);
    super.dispose();
  }

  void _identityChanged() {
    if (!mounted || _reopenRequired || _sameIdentity) return;
    _request++;
    setState(() {
      _reopenRequired = true;
      _loading = false;
      _records = const [];
      _error = null;
      _cancellingId = null;
    });
  }

  Future<void> _load({int? page}) async {
    if (_cancellingId != null || _confirming) return;
    if (_reopenRequired || !_sameIdentity) {
      _identityChanged();
      return;
    }
    final requestedPage = page ?? _page;
    final request = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await widget.service.listReservations(
        history: _history,
        page: requestedPage,
      );
      if (!mounted || request != _request || !_sameIdentity) return;
      setState(() {
        _records = result.records;
        _hasMore = result.hasMore;
        _page = requestedPage;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || request != _request || !_sameIdentity) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _selectHistory(bool history) {
    if (_history == history || _cancellingId != null) return;
    setState(() {
      _history = history;
      _page = 1;
      _records = const [];
      _hasMore = false;
    });
    unawaited(_load(page: 1));
  }

  Future<void> _confirmCancel(LibraryReservationRecord record) async {
    if (_history || _loading || !record.canCancel || _cancellingId != null ||
        _confirming || !_sameIdentity) {
      return;
    }
    setState(() => _confirming = true);
    final bool? confirmed;
    try {
      confirmed = await showAdaptiveAlertDialog<bool>(
        context: context,
        title: '取消预约？',
        message: '${record.name}\n${record.date}  ${record.startTime}–${record.endTime}',
        actions: const [
          AdaptiveAlertAction(label: '保留预约', value: false),
          AdaptiveAlertAction(label: '取消预约', value: true, isDestructive: true),
        ],
      );
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
    if (confirmed != true || !mounted || !_sameIdentity || _reopenRequired) return;

    final request = _request;
    setState(() => _cancellingId = record.id);
    try {
      if (!_sameIdentity || request != _request) return;
      await widget.service.cancelReservation(record);
      if (!mounted || request != _request || !_sameIdentity) return;
      widget.onCancelled();
      showAdaptiveFeedback(
        context: context,
        message: '预约已取消',
        style: AdaptiveFeedbackStyle.success,
      );
      setState(() => _cancellingId = null);
      await _load(page: 1);
    } catch (error) {
      if (!mounted || request != _request || !_sameIdentity) return;
      setState(() => _cancellingId = null);
      showAdaptiveFeedback(
        context: context,
        message: error.toString(),
        style: AdaptiveFeedbackStyle.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final canRefresh = !_reopenRequired && !_loading && !_confirming && _cancellingId == null;
    return Scaffold(
      appBar: isIos()
          ? IosNativeNavigationBar(
              title: '我的预约',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回图书馆预约',
                ),
              ],
              trailingItems: [
                IosNativeNavigationBarItem(
                  id: 'refresh',
                  sfSymbol: 'arrow.clockwise',
                  accessibilityLabel: '刷新预约记录',
                  enabled: canRefresh,
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
                if (id == 'refresh' && canRefresh) unawaited(_load(page: 1));
              },
            )
          : BlurredAppBar(
              leading: const BackButton(),
              title: const Text('我的预约'),
              actions: [
                IconButton(
                  tooltip: '刷新预约记录',
                  onPressed: canRefresh ? () => _load(page: 1) : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: AdaptiveSegmentedControl(
                      value: _history ? 1 : 0,
                      segments: const ['当前预约', '历史记录'],
                      onChanged: _reopenRequired || _confirming || _cancellingId != null
                          ? null
                          : (index) => _selectHistory(index == 1),
                    ),
                  ),
                ),
                Expanded(child: _buildBody(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_reopenRequired) {
      return const _Message(
        icon: Icons.manage_accounts_outlined,
        title: '账户已变更',
        detail: '请关闭此页面后重新打开，避免查看或修改另一账户的预约。',
      );
    }
    if (_loading && _records.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _records.isEmpty) {
      return _Message(
        icon: Icons.error_outline,
        title: '无法加载预约',
        detail: _error!,
        action: SizedBox(
          width: 120,
          child: AdaptiveButton(
            onPressed: _load,
            icon: Icons.refresh,
            sfSymbol: 'arrow.clockwise',
            label: '重试',
            height: 44,
          ),
        ),
      );
    }

    final canPage = !_loading && !_confirming && _cancellingId == null;
    return RefreshIndicator.adaptive(
      onRefresh: () => _load(page: 1),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          if (_error != null)
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                leading: const Icon(Icons.error_outline),
                title: Text(_error!),
                trailing: IconButton(
                  tooltip: '重试',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
          if (_records.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 96),
              child: _Message(
                icon: Icons.event_available_outlined,
                title: '暂无预约',
                detail: '这里还没有可显示的预约记录。',
              ),
            )
          else
            for (final record in _records) _recordCard(context, record),
          if (_page > 1 || _hasMore) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  width: 105,
                  child: AdaptiveButton(
                    onPressed: _page > 1 && canPage ? () => _load(page: _page - 1) : null,
                    icon: Icons.chevron_left,
                    sfSymbol: 'chevron.left',
                    label: '上一页',
                    role: AdaptiveButtonRole.plain,
                    height: 44,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Semantics(label: '第 $_page 页', child: Text('第 $_page 页')),
                ),
                SizedBox(
                  width: 105,
                  child: AdaptiveButton(
                    onPressed: _hasMore && canPage ? () => _load(page: _page + 1) : null,
                    icon: Icons.chevron_right,
                    sfSymbol: 'chevron.right',
                    label: '下一页',
                    role: AdaptiveButtonRole.plain,
                    height: 44,
                  ),
                ),
              ],
            ),
          ],
          if (_loading) const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }

  Widget _recordCard(BuildContext context, LibraryReservationRecord record) {
    final theme = Theme.of(context);
    final cancelling = _cancellingId == record.id;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(record.name),
              subtitle: Text(
                '${record.typeLabel} · ${record.statusLabel}\n'
                '${record.date} · ${record.startTime}–${record.endTime}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (!_history && record.canCancel)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: SizedBox(
                  width: 124,
                  child: AdaptiveButton(
                    onPressed: _loading || _confirming || _cancellingId != null
                        ? null
                        : () => _confirmCancel(record),
                    icon: Icons.event_busy_outlined,
                    sfSymbol: 'calendar.badge.minus',
                    label: '取消预约',
                    role: AdaptiveButtonRole.destructive,
                    loading: cancelling,
                    height: 44,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });

  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Semantics(
          liveRegion: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: theme.colorScheme.secondary),
              const SizedBox(height: 16),
              Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 20), action!],
            ],
          ),
        ),
      ),
    );
  }
}
