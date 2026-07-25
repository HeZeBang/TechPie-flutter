import 'dart:async';

import 'package:flutter/foundation.dart';

import 'cookie_provider.dart';

/// One node in the unified session tree.
///
/// Topology (master branch):
/// ```
/// SessionTree
/// ├── gradescope  : LeafSessionNode   (token-only, no cookies)
/// ├── hydro       : LeafSessionNode   (token-only, no cookies)
/// └── egate       : CpdailySessionNode (CASTGC + CpDaily session)
///     └── ids     : IdsSessionNode    (IDS cookies refreshed via parent)
/// ```
///
/// Every node exposes:
/// - [cookieProvider] — the [CookieProvider] view downstream apps read. Null
///   for leaf nodes that authenticate via bearer tokens server-side.
/// - [renew()] — refresh this node's credentials. Single-flighted: concurrent
///   callers share ONE in-flight renew and observe the same result.
/// - [epoch] — monotonically increasing, bumped on every successful renew.
///   Callers capture the epoch when they read cookies, then pass it to
///   [renewIfNeeded] so a concurrent renew that already refreshed the cookie
///   is NOT re-triggered (anti-renew-storm).
///
/// The 401-renew-retry pattern lives in [SessionTree.withCookie] so individual
/// services stop hand-rolling it.
abstract class SessionNode extends ChangeNotifier {
  SessionNode({required this.id});

  /// Stable identifier (matches storage key / platform id).
  final String id;

  /// Optional parent — set when this node's session is derived from another
  /// (e.g. IDS cookies are minted from the CpDaily session). Null for roots.
  SessionNode? parent;

  final List<SessionNode> _children = [];
  List<SessionNode> get children => List.unmodifiable(_children);

  void attachChild(SessionNode child) {
    child.parent = this;
    _children.add(child);
  }

  void detachChild(SessionNode child) {
    if (child.parent == this) child.parent = null;
    _children.remove(child);
  }

  /// The cookie view exposed to downstream consumers, or null when this node
  /// authenticates via bearer tokens (Gradescope/Hydro) and has no cookies.
  CookieProvider? get cookieProvider => null;

  /// True when this node has a usable session (bound + non-empty credentials).
  bool get isAvailable;

  // -- Renewal: single-flight + stale-epoch skip --

  int _epoch = 0;
  Future<bool>? _renewInFlight;

  /// Current epoch. Bumped after every successful [renew]. Callers capture
  /// this when reading cookies and pass it to [renewIfNeeded].
  int get epoch => _epoch;

  /// Bump epoch and notify. Called by subclasses after persisting refreshed
  /// credentials into the wrapped account.
  @protected
  void markRenewed() {
    _epoch++;
    notifyListeners();
  }

  /// Subclass-specific renew. MUST persist refreshed credentials and call
  /// [markRenewed] on success. Returns true on success, false on failure.
  @protected
  Future<bool> doRenew();

  /// Refresh this node's credentials. Single-flighted: concurrent callers
  /// share one in-flight renew and observe the same result.
  Future<bool> renew() {
    if (_renewInFlight != null) return _renewInFlight!;
    final f = doRenew().whenComplete(() => _renewInFlight = null);
    _renewInFlight = f;
    return f;
  }

  /// Renew only if no renew has completed since [beforeEpoch]. This is the
  /// anti-storm gate: a caller that captured cookies at epoch N, hit a 401,
  /// and now wants to renew will skip if another caller already renewed
  /// (epoch > N) — it just re-reads the fresh cookies instead.
  ///
  /// Returns true if a renew ran and succeeded OR was already done by a
  /// concurrent caller (epoch advanced). Returns false only when a renew
  /// actually ran and failed, or the node is unavailable.
  Future<bool> renewIfNeeded(int beforeEpoch) async {
    if (!isAvailable) return false;
    // A concurrent renew already advanced past the caller's snapshot —
    // the cookies the caller will re-read are already fresh. Skip.
    if (_epoch > beforeEpoch) return true;
    return renew();
  }

  @override
  String toString() => '$runtimeType($id)';
}
