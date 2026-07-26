import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../models/third_party_account.dart';
import '../http_client.dart';
import 'cookie_provider.dart';
import 'session_node.dart';

/// The unified session tree.
///
/// Topology (built once at construction):
/// ```
/// SessionTree
/// ├── cpdaily     (top-level, account+password/SMS bind, /auth/renew)
/// │   ├── eams        (child, /auth/third-party/eams, parent tgc)
/// │   └── elearning   (child, /auth/third-party/elearning, parent tgc)
/// ├── gradescope  (top-level, account+password bind, bearer token)
/// └── hydro       (top-level, account+password bind, sid cookie)
/// ```
///
/// The facade ([ThirdPartyAuthService]) feeds account mutations in via
/// [setAccount]. Child nodes (eams/elearning) carry no account — their
/// credential is a derived cookie minted on demand from the parent's tgc.
class SessionTree extends ChangeNotifier {
  SessionTree({
    required this.persist,
    required this.http,
    required this.baseUrl,
    this.persistDerived,
  }) {
    cpdaily = SessionNode(
      id: 'cpdaily',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/renew',
      renewMode: RenewMode.cpdailySession,
      apiPath: 'egate',
    );
    gradescope = SessionNode(
      id: 'gradescope',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/third-party/gradescope',
      renewMode: RenewMode.password,
      apiPath: 'gradescope',
    );
    hydro = SessionNode(
      id: 'hydro',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/third-party/hydro',
      renewMode: RenewMode.password,
      apiPath: 'hydro',
    );
    eams = SessionNode(
      id: 'eams',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      parent: cpdaily,
      renewPath: '/auth/third-party/eams',
      renewMode: RenewMode.parentCookie,
      persistDerived: persistDerived,
    );
    elearning = SessionNode(
      id: 'elearning',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      parent: cpdaily,
      renewPath: '/auth/third-party/elearning',
      renewMode: RenewMode.parentCookie,
      persistDerived: persistDerived,
    );
    cpdaily.attachChild(eams);
    cpdaily.attachChild(elearning);

    // Only top-level node notifications propagate up to the tree (facade →
    // UI / sync / auto-refetch). Child nodes (eams/elearning) mint cookies
    // as a side-effect of withCookie — their notifyListeners would otherwise
    // trigger _onDepsChanged → fetchAssignments → re-mint, a feedback loop.
    // Child notifications still fire for direct listeners on the node itself
    // (e.g. withCookie's epoch checks read node state directly, not via tree).
    for (final n in [cpdaily, gradescope, hydro]) {
      n.addListener(notifyListeners);
    }
  }
  final PersistAccount persist;
  final PersistDerivedCookie? persistDerived;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;

  late final SessionNode cpdaily;
  late final SessionNode gradescope;
  late final SessionNode hydro;
  late final SessionNode eams;
  late final SessionNode elearning;

  /// All top-level nodes in a stable order.
  List<SessionNode> get roots => [cpdaily, gradescope, hydro];

  /// Lookup a top-level node by [ThirdPartyPlatform]. Child nodes (eams/
  /// elearning) are accessed directly via [eams]/[elearning].
  SessionNode nodeFor(ThirdPartyPlatform p) => switch (p) {
        ThirdPartyPlatform.cpdaily => cpdaily,
        ThirdPartyPlatform.gradescope => gradescope,
        ThirdPartyPlatform.hydro => hydro,
      };

  /// Feed an account mutation from the facade into the matching top-level
  /// node. Used by bind/unbind/replaceAll/updateRaw. Child nodes ignore
  /// this (they carry no account).
  void setAccount(ThirdPartyPlatform p, ThirdPartyAccount? acc) {
    nodeFor(p).setAccount(acc);
  }

  /// Hydrate a child node's derived cookie from persistent storage at boot.
  /// Called by the facade after accounts are loaded so cold start can skip
  /// the SSO bounce if a valid derived cookie is still on disk.
  void setDerivedCookie(String nodeId, String? cookie) {
    final node = switch (nodeId) {
      'eams' => eams,
      'elearning' => elearning,
      _ => null,
    };
    node?.setDerivedCookie(cookie);
  }

  // -- The anti-storm 401-renew-retry helper (two-level) --

  /// Run [action] with the cookie view from [node]. On a response the caller
  /// flags as expired (via [isExpired]), renew the node exactly once (shared
  /// across all concurrent callers) and retry with the fresh cookie. If a
  /// concurrent renew already advanced the cookie epoch since [action]
  /// captured it, skip the renew entirely and just retry with the new cookie.
  ///
  /// For non-top-level nodes (eams/elearning), a failed first-level retry
  /// triggers a second-level fallback ONLY if the child's renew failure was
  /// a credential error (HTTP 401 = parent tgc stale). Server errors (5xx)
  /// and network failures do NOT escalate — re-minting the parent tgc won't
  /// fix a broken backend, so the escalation is skipped to avoid wasteful
  /// /auth/renew calls.
  ///
  /// Retry budget: at most 1 child renew (first level) + 1 parent renew +
  /// 1 child re-mint (second level) per withCookie call. The single-flight
  /// gate on each node ensures concurrent callers share these renews.
  ///
  /// [action] receives the current [CookieProvider] (non-null — callers
  /// gate on [node.isAvailable] first) and returns its result + whether the
  /// result should be treated as "cookie expired, please renew+retry".
  ///
  /// Returns the (possibly retried) result, or null if the node was
  /// unavailable or renew failed.
  Future<T?> withCookie<T>(
    SessionNode node,
    Future<CookieAction<T>> Function(CookieProvider provider) action,
  ) async {
    // First level: single-node renew-retry (handles initial minting + 401).
    var result = await _renewRetry(node, action);
    if (result != null) return result;

    // Second level: for child nodes whose first-level retry returned null.
    // ONLY escalate to parent renew if the child's renew failure was a
    // credential error (HTTP 401 = parent tgc stale). A 500 from the
    // downstream endpoint is a server error — re-minting the parent tgc
    // won't fix it, so we skip the escalation and return null immediately.
    // This prevents wasteful /auth/renew calls on transient backend errors.
    if (node.parent == null) return null;
    if (!node.lastRenewWasCredentialError) return null;
    final parentOk = await node.parent!.renewIfNeeded(node.parent!.epoch);
    if (!parentOk) return null;
    final childOk = await node.renew();
    if (!childOk) return null;
    final cp = node.cookieProvider;
    if (cp == null) return null;
    final retried = await action(cp);
    return retried.value;
  }

  /// Single-node 401-renew-retry. If the node is not yet available (e.g. a
  /// child node whose downstream cookie hasn't been minted), attempt an
  /// initial renew first. Returns null if the renew failed (caller may
  /// attempt two-level fallback for child nodes).
  Future<T?> _renewRetry<T>(
    SessionNode node,
    Future<CookieAction<T>> Function(CookieProvider provider) action,
  ) async {
    // If not available, try to mint credentials first (initial minting for
    // child nodes, or a no-op for top-level nodes that are already bound).
    if (!node.isAvailable) {
      final ok = await node.renew();
      if (!ok) return null;
    }
    var cp = node.cookieProvider;
    if (cp == null) return null;

    var result = await action(cp);
    if (!result.expired) return result.value;

    // 401: renew if the cookie hasn't already been refreshed since we read it.
    final beforeEpoch = node.epoch;
    final ok = await node.renewIfNeeded(beforeEpoch);
    if (!ok) return null;

    cp = node.cookieProvider;
    if (cp == null) return null;
    final retried = await action(cp);
    return retried.value;
  }

  @override
  void dispose() {
    for (final n in [cpdaily, gradescope, hydro]) {
      n.removeListener(notifyListeners);
    }
    for (final n in [cpdaily, gradescope, hydro, eams, elearning]) {
      n.dispose();
    }
    super.dispose();
  }
}

/// The result of a cookie-bearing action, tagged by the caller so
/// [SessionTree.withCookie] knows whether to trigger a renew+retry.
class CookieAction<T> {
  final T value;
  final bool expired;
  const CookieAction(this.value, {required this.expired});
}
