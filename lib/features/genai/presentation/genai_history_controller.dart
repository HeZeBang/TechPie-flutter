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
  List<GenAiConversationSummary> _conversations = const [];
  Timer? _searchTimer;
  GenAiCancellation? _historyCancellation;
  GenAiFailure? _historyFailure;
  String _sidebarQuery = '';
  int _historyPage = 1;
  bool _hasMoreHistory = false;
  bool _loadingHistory = false;
  bool _historyRequested = false;
  bool _refreshPending = false;
  bool _disposed = false;
  late Object? _accountScope;
  late int _sessionRevision;
  late int _finishedTurnRevision;

  List<GenAiConversationSummary> get conversations => _conversations;
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
    _finishedTurnRevision = _workspace.finishedTurnRevision;
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
    final historyChanged = _finishedTurnRevision != _workspace.finishedTurnRevision;
    _rememberWorkspace();
    _refreshPending |= historyChanged;
    if (_workspace.connected && !(_searchTimer?.isActive ?? false)) {
      if (!_historyRequested) {
        unawaited(load());
      } else {
        _refreshWhenIdle();
      }
    }
  }

  void _refreshWhenIdle() {
    if (!_disposed &&
        _refreshPending &&
        !_loadingHistory &&
        _workspace.connected &&
        !(_searchTimer?.isActive ?? false)) {
      _refreshPending = false;
      unawaited(load(refresh: true));
    }
  }

  void remove(String id) {
    _update(() {
      _conversations = List.unmodifiable(_conversations.where((item) => item.id != id));
    });
  }

  void _reset() {
    _historyCancellation?.cancel();
    _historyCancellation = null;
    _searchTimer?.cancel();
    searchController.clear();
    _sidebarQuery = '';
    _conversations = const [];
    _historyPage = 1;
    _hasMoreHistory = false;
    _loadingHistory = false;
    _historyRequested = false;
    _refreshPending = false;
    _historyFailure = null;
  }

  Future<void> load({bool more = false, String? query, bool refresh = false}) async {
    if (_disposed || !_workspace.connected || (more && _loadingHistory)) return;
    _historyCancellation?.cancel();
    final cancellation = GenAiCancellation();
    _historyCancellation = cancellation;
    final page = more ? _historyPage + 1 : 1;
    final targetQuery = query ?? _sidebarQuery;
    final lastPage = refresh && targetQuery == _sidebarQuery ? _historyPage : page;
    if (!more) _refreshPending = false;
    _update(() {
      _historyRequested = true;
      _loadingHistory = true;
      _historyFailure = null;
      if (!more) {
        if (_sidebarQuery != targetQuery) _conversations = const [];
        _sidebarQuery = targetQuery;
        if (!refresh) {
          _historyPage = 0;
          _hasMoreHistory = false;
        }
      }
    });
    try {
      final records = <GenAiConversationSummary>[];
      var loadedPage = page;
      var hasMore = false;
      for (var next = page; next <= lastPage || next == page; next++) {
        final result = await _workspace.listConversations(
          cancellation,
          page: next,
          query: targetQuery,
        );
        if (_disposed || cancellation.isCancelled) return;
        records.addAll(result.records);
        loadedPage = next;
        hasMore = result.hasMore;
        if (!hasMore) break;
      }
      final byId = {
        if (more)
          for (final item in _conversations) item.id: item,
        for (final item in records) item.id: item,
      };
      _conversations = List.unmodifiable(
        byId.values.toList()..sort(GenAiConversationSummary.newestFirst),
      );
      _hasMoreHistory = hasMore;
      _historyPage = loadedPage;
    } catch (error) {
      if (!_disposed && !cancellation.isCancelled) {
        _historyFailure =
            error is GenAiFailure ? error : const GenAiFailure(GenAiFailureKind.transport);
      }
    } finally {
      if (identical(_historyCancellation, cancellation)) {
        _historyCancellation = null;
        if (!_disposed) {
          _update(() => _loadingHistory = false);
          _refreshWhenIdle();
        }
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
    _refreshPending = false;
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
