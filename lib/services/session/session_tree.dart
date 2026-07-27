import 'dart:async';
import 'dart:convert';

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
/// │   ├── elearning   (child, /auth/third-party/elearning, parent tgc)
/// │   └── egateApp    (child, /auth/third-party/egate-app, parent tgc)
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
    this.recordRenewStatus,
    this.persistProbe,
    this.persistRenewTimestamp,
  }) {
    cpdaily = SessionNode(
      id: 'cpdaily',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/renew',
      renewMode: RenewMode.cpdailySession,
      apiPath: 'egate',
      recordRenewStatus: recordRenewStatus,
      persistProbe: persistProbe,
      persistRenewTimestamp: persistRenewTimestamp,
      renewSchedule: RenewSchedule.cpdailyDefault,
    );
    gradescope = SessionNode(
      id: 'gradescope',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/third-party/gradescope',
      renewMode: RenewMode.password,
      apiPath: 'gradescope',
      recordRenewStatus: recordRenewStatus,
      keepaliveConfig: const KeepaliveConfig(method: 'HEAD', path: '/'),
      persistProbe: persistProbe,
      persistRenewTimestamp: persistRenewTimestamp,
      renewSchedule: RenewSchedule.accountExpiry,
    );
    hydro = SessionNode(
      id: 'hydro',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      renewPath: '/auth/third-party/hydro',
      renewMode: RenewMode.password,
      apiPath: 'hydro',
      recordRenewStatus: recordRenewStatus,
      keepaliveConfig: const KeepaliveConfig(method: 'HEAD', path: '/'),
      persistProbe: persistProbe,
      persistRenewTimestamp: persistRenewTimestamp,
      renewSchedule: RenewSchedule.accountExpiry,
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
      recordRenewStatus: recordRenewStatus,
      persistProbe: persistProbe,
      persistRenewTimestamp: persistRenewTimestamp,
      renewSchedule: RenewSchedule.derivedCookie,
      keepaliveConfig: KeepaliveConfig(
        path: 'https://eams.shanghaitech.edu.cn/eams/stdDetail.action',
        bodyRegex: RegExp(r'姓名[：:]\s*</td>\s*<td[^>]*>([^<]+)</td>'),
      ),
    );
    elearning = SessionNode(
      id: 'elearning',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      parent: cpdaily,
      renewPath: '/auth/third-party/elearning',
      renewMode: RenewMode.parentCookie,
      persistProbe: persistProbe,
      persistRenewTimestamp: persistRenewTimestamp,
      renewSchedule: RenewSchedule.derivedCookie,
      persistDerived: persistDerived,
      recordRenewStatus: recordRenewStatus,
      keepaliveConfig: KeepaliveConfig(
        path:
            'https://elearning.shanghaitech.edu.cn:8443/webapps/portal/execute/tabs/tabAction'
            '?tab_tab_group_id=_1_1',
        bodyRegex: RegExp(r'欢迎[，,]\s*(.+?)\s*&ndash;'),
      ),
    );
    egateApp = SessionNode(
      id: 'egateApp',
      persist: persist,
      http: http,
      baseUrl: baseUrl,
      parent: cpdaily,
      renewPath: '/auth/third-party/egate-app',
      persistProbe: persistProbe,
      renewSchedule: RenewSchedule.derivedCookie,
      persistRenewTimestamp: persistRenewTimestamp,
      renewMode: RenewMode.parentCookie,
      persistDerived: persistDerived,
      recordRenewStatus: recordRenewStatus,
      keepaliveConfig: KeepaliveConfig(
        method: 'POST',
        path:
            'https://egate.shanghaitech.edu.cn/xsfw/sys/jbxxapp/modules/jbxx/hqdlxsjpcxx.do',
        preFlightPath:
            'https://egate.shanghaitech.edu.cn/xsfw/sys/funauthapp/api/getAppConfig/'
            'xshdapp-4770201649822494.do?v=0918614558578972',
        successCheck: (r) {
          if (r.statusCode != 200) return false;
          final data = jsonDecode(r.body);
          return data['code'] == '0';
        },
        displayText: (r) {
          final data = jsonDecode(r.body);
          final rows = ((data['datas'] as Map?)?['hqdlxsjpcxx']
              as Map?)?['rows'] as List?;
          return (rows?.firstOrNull as Map?)?['XSBH'] as String? ?? 'egateApp';
        },
      ),
    );
    cpdaily.attachChild(eams);
    cpdaily.attachChild(elearning);
    cpdaily.attachChild(egateApp);

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
  final PersistProbe? persistProbe;
  final PersistRenewStatus? recordRenewStatus;
  final PersistRenewTimestamp? persistRenewTimestamp;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;

  late final SessionNode cpdaily;
  late final SessionNode gradescope;
  late final SessionNode hydro;
  late final SessionNode eams;
  late final SessionNode elearning;
  late final SessionNode egateApp;

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
      'egateApp' => egateApp,
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
    if (node.parent != null &&
        node.parent!.canRenew &&
        node.parent!.isRenewDue) {
      final parentOk = await node.parent!.renewIfDue();
      if (!parentOk) return null;
    }
    if (!node.isAvailable) {
      final ok = await node.renew();
      if (!ok) return null;
    } else if (node.canRenew && node.isRenewDue) {
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
    for (final n in [cpdaily, gradescope, hydro, eams, elearning, egateApp]) {
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
