import 'dart:async';

import 'package:flutter/widgets.dart';

import '../application/genai_workspace_controller.dart';
import '../domain/genai_cancellation.dart';
import '../domain/genai_failure.dart';
import '../domain/genai_platform_contract.dart';

/// Search, pagination, and request lifetime for the workspace history sidebar.
class GenAiHistoryController extends ChangeNotifier {
  GenAiHistoryController(GenAiWorkspaceController workspace) : _workspace = workspace {
    _rememberWorkspace();
    _workspace.addListener(_workspaceChanged);
    if (_workspace.connected) unawaited(load());
  }

  GenAiWorkspaceController _workspace;
  final searchController = TextEditingController();
  final _conversations = <GenAiConversationSummary>[];
  Timer? _searchTimer;
  GenAiCancellation? _historyCancellation;
  GenAiFailure? _historyFailure;
  String _sidebarQuery = '';
  int _historyPage = 1;
  bool _hasMoreHistory = false;
  bool _loadingHistory = false;
  bool _historyRequested = false;
  bool _disposed = false;
  late Object? _accountScope;
  late int _sessionRevision;
  late String _groupId;
  late bool _wasSending;

  List<GenAiConversationSummary> get conversations => List.unmodifiable(_conversations);
  bool get loading => _loadingHistory;
  bool get hasMore => _hasMoreHistory;
  GenAiFailure? get failure => _historyFailure;
  String get query => _sidebarQuery;

  void _update(VoidCallback update) {
    if (_disposed) return;
    update();
    notifyListeners();
  }

  void _rememberWorkspace() {
    _accountScope = _workspace.accountScope;
    _sessionRevision = _workspace.sessions.revision;
    _groupId = _workspace.groupId;
    _wasSending = _workspace.sending;
  }

  void bindWorkspace(GenAiWorkspaceController workspace) {
    if (identical(workspace, _workspace)) return;
    _workspace.removeListener(_workspaceChanged);
    _reset();
    _workspace = workspace;
    _rememberWorkspace();
    _workspace.addListener(_workspaceChanged);
    if (_workspace.connected) {
      unawaited(load());
    } else {
      notifyListeners();
    }
  }

  void _workspaceChanged() {
    if (_accountScope != _workspace.accountScope ||
        _sessionRevision != _workspace.sessions.revision) {
      _reset();
    }
    final historyChanged = _groupId != _workspace.groupId || (_wasSending && !_workspace.sending);
    _rememberWorkspace();
    if (_workspace.connected &&
        (!_historyRequested || (historyChanged && !(_searchTimer?.isActive ?? false)))) {
      unawaited(load());
    }
  }

  void remove(String id) {
    _update(() => _conversations.removeWhere((item) => item.id == id));
  }

  void _reset() {
    _historyCancellation?.cancel();
    _historyCancellation = null;
    _searchTimer?.cancel();
    searchController.clear();
    _sidebarQuery = '';
    _conversations.clear();
    _historyPage = 1;
    _hasMoreHistory = false;
    _loadingHistory = false;
    _historyRequested = false;
    _historyFailure = null;
  }

  Future<void> load({bool more = false, String? query}) async {
    if (_disposed || !_workspace.connected || (more && _loadingHistory)) return;
    _historyCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _historyCancellation = cancellation;
    final page = more ? _historyPage + 1 : 1;
    final targetQuery = query ?? _sidebarQuery;
    _update(() {
      _historyRequested = true;
      _loadingHistory = true;
      _historyFailure = null;
      if (!more) {
        if (_sidebarQuery != targetQuery) _conversations.clear();
        _sidebarQuery = targetQuery;
      }
    });
    try {
      final result = await _workspace.listConversations(
        cancellation,
        page: page,
        query: targetQuery,
      );
      if (_disposed || cancellation.isCancelled) return;
      _update(() {
        if (!more) _conversations.clear();
        for (final record in result.records) {
          _conversations.removeWhere((item) => item.id == record.id);
          _conversations.add(record);
        }
        _conversations.sort(GenAiConversationSummary.newestFirst);
        _hasMoreHistory = result.hasMore;
        _historyPage = page;
      });
    } catch (error) {
      if (!_disposed && !cancellation.isCancelled) {
        _update(
          () => _historyFailure =
              error is GenAiFailure ? error : const GenAiFailure(GenAiFailureKind.transport),
        );
      }
    } finally {
      if (identical(_historyCancellation, cancellation)) {
        _historyCancellation = null;
        if (!_disposed) _update(() => _loadingHistory = false);
      }
    }
  }

  void searchChanged(String text) {
    _searchTimer?.cancel();
    _historyCancellation?.cancel();
    _historyCancellation = null;
    _loadingHistory = false;
    // Notifications from streaming must not start a competing history load.
    _historyRequested = true;
    _searchTimer = Timer(const Duration(milliseconds: 250), () {
      if (!_disposed) unawaited(load(query: text.trim()));
    });
    _update(() {});
  }

  @override
  void dispose() {
    _disposed = true;
    _workspace.removeListener(_workspaceChanged);
    _historyCancellation?.cancel();
    _searchTimer?.cancel();
    searchController.dispose();
    super.dispose();
  }
}
