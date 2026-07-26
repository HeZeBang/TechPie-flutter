import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../models/third_party_account.dart';
import '../http_client.dart';
import 'cookie_provider.dart';

/// Callback the facade ([ThirdPartyAuthService]) installs so a top-level
/// node can persist a refreshed [ThirdPartyAccount] back into secure storage
/// and fire the external change notification (listeners + cloud-sync push
/// hook) in one place. Returns nothing; the node owns the in-memory account
/// afterwards. Only meaningful for top-level nodes (renewMode cpdailySession
/// or password); non-top-level nodes skip persist (derived cookies are
/// ephemeral).
typedef PersistAccount = Future<void> Function(ThirdPartyAccount updated);

/// Callback a non-top-level node installs to persist its derived downstream
/// cookie into secure storage (so cold start can skip the SSO bounce) or
/// clear it (when the parent renews and invalidates it). Receives the node
/// id and the cookie string (null to clear).
typedef PersistDerivedCookie = Future<void> Function(
  String nodeId,
  String? cookie,
);

/// Callback to read the current API base URL (depends on storage settings).
typedef BaseUrlGetter = String Function();

/// How a [SessionNode] renews its credentials.
enum RenewMode {
  /// CpDaily session keep-alive: POST /auth/renew with stored
  /// sessionToken/tgc/userId/tenantId. Top-level only.
  cpdailySession,

  /// Password re-authentication: POST /auth/third-party/<apiPath> with
  /// account/password. Top-level only (gradescope, hydro).
  password,

  /// Downstream cookie minting: POST /auth/third-party/<id> with the parent
  /// node's tgc. Non-top-level only (eams, elearning).
  parentCookie,
}

/// One node in the unified session tree.
///
/// Topology:
/// ```
/// SessionTree
/// ├── cpdaily     (top-level, account+password/SMS bind, /auth/renew)
/// │   ├── eams        (child, /auth/third-party/eams, parent tgc)
/// │   └── elearning   (child, /auth/third-party/elearning, parent tgc)
/// ├── gradescope  (top-level, account+password bind, bearer token)
/// └── hydro       (top-level, account+password bind, sid cookie)
/// ```
///
/// Every node exposes:
/// - [cookieProvider] — the [CookieProvider] view downstream apps read. For
///   top-level nodes the credential comes from the bound account (cpdaily:
///   CASTGC+cookies; gradescope/hydro: bearer token). For non-top-level
///   nodes it comes from the derived downstream cookie string.
/// - [renew()] — refresh this node's credentials. Single-flighted: concurrent
///   callers share ONE in-flight renew and observe the same result.
/// - [epoch] — monotonically increasing, bumped on every successful renew.
///   Callers capture the epoch when they read cookies, then pass it to
///   [renewIfNeeded] so a concurrent renew that already refreshed the cookie
///   is NOT re-triggered (anti-renew-storm).
///
/// The 401-renew-retry pattern (with two-level parent fallback for child
/// nodes) lives in [SessionTree.withCookie].
class SessionNode extends ChangeNotifier {
  SessionNode({
    required this.id,
    required this.persist,
    required this.http,
    required this.baseUrl,
    this.parent,
    this.renewPath,
    this.renewMode,
    this.apiPath,
    this.persistDerived,
  });

  /// Stable identifier (matches storage key / platform id, except cpdaily
  /// whose storage id is 'cpdaily' but whose backend bind route is 'egate').
  final String id;

  /// Optional parent — set when this node's session is derived from another
  /// (e.g. eams/elearning cookies are minted from the cpdaily CASTGC). Null
  /// for roots.
  SessionNode? parent;

  /// Full backend renew path (e.g. '/auth/renew', '/auth/third-party/eams').
  final String? renewPath;

  /// How this node renews. Null only for nodes that never renew.
  final RenewMode? renewMode;

  /// Backend bind route name. For cpdaily this is 'egate' (the backend route
  /// was not renamed); for gradescope/hydro it equals [id]. Null for
  /// non-top-level nodes.
  final String? apiPath;
  final PersistAccount persist;
  final PersistDerivedCookie? persistDerived;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;

  final List<SessionNode> _children = [];
  List<SessionNode> get children => List.unmodifiable(_children);

  /// Top-level nodes hold the bound account; non-top-level nodes leave this
  /// null (their credential is the ephemeral [_derivedCookie]).
  ThirdPartyAccount? _account;
  ThirdPartyAccount? get account => _account;

  /// Non-top-level nodes hold the downstream cookie string minted by the
  /// last successful renew; top-level nodes leave this null.
  String? _derivedCookie;

  /// Raw fields from the bound account (top-level only). Downstream services
  /// (OA gym) and child nodes read tgc/sessionToken/userId/tenantId through
  /// this. Returns an empty map for non-top-level nodes.
  Map<String, dynamic> get rawFields => _account?.raw ?? const {};

  /// Set the bound account. Only meaningful for top-level nodes; calling on
  /// a non-top-level node is a no-op.
  void setAccount(ThirdPartyAccount? acc) {
    if (parent != null) return; // non-top-level: no account
    _account = acc;
    notifyListeners();
  }

  /// Hydrate the derived cookie from persistent storage at boot. Only
  /// meaningful for non-top-level nodes; calling on a top-level node is a
  /// no-op. Does NOT notify — this is a boot-time hydration, not a state
  /// change the UI needs to react to.
  void setDerivedCookie(String? cookie) {
    if (parent == null) return; // top-level: no derived cookie
    _derivedCookie = (cookie != null && cookie.isNotEmpty) ? cookie : null;
  }

  void attachChild(SessionNode child) {
    child.parent = this;
    _children.add(child);
  }

  void detachChild(SessionNode child) {
    if (child.parent == this) child.parent = null;
    _children.remove(child);
  }

  // -- Unified cookieProvider --

  /// The cookie view exposed to downstream consumers. For top-level nodes
  /// the credential is extracted from the bound account; for non-top-level
  /// nodes it is the derived downstream cookie. Null when no usable
  /// credential is available.
  CookieProvider? get cookieProvider {
    if (parent == null) {
      // Top-level
      final acc = _account;
      if (acc == null) return null;
      final cookie = _cookieFromAccount(acc);
      if (cookie.isEmpty) return null;
      return CookieProvider(
        cookies: cookie,
        studentId: acc.sid ?? '',
        domain: _domain,
      );
    }
    // Non-top-level: derived cookie
    final c = _derivedCookie;
    if (c == null || c.isEmpty) return null;
    return CookieProvider(cookies: c, domain: _domain);
  }

  /// Top-level credential extraction: cpdaily concatenates CASTGC onto the
  /// session cookies; gradescope/hydro use the bearer token directly.
  String _cookieFromAccount(ThirdPartyAccount acc) {
    if (id == 'cpdaily') {
      final base = (acc.raw['cookies'] as String?) ?? '';
      final tgc = (acc.raw['tgc'] as String?) ?? '';
      return tgc.isEmpty
          ? base
          : (base.isNotEmpty ? '$base; CASTGC=$tgc' : 'CASTGC=$tgc');
    }
    return acc.token;
  }

  String get _domain => switch (id) {
        'cpdaily' => 'ids.shanghaitech.edu.cn',
        'eams' => 'eams.shanghaitech.edu.cn',
        'elearning' => 'elearning.shanghaitech.edu.cn',
        _ => '',
      };

  /// True when this node has a usable session.
  bool get isAvailable {
    if (parent == null) {
      final cp = cookieProvider;
      return _account != null && cp != null && !cp.isEmpty;
    }
    return (parent?.isAvailable ?? false) &&
        _derivedCookie != null &&
        _derivedCookie!.isNotEmpty;
  }

  // -- Renewal: single-flight + stale-epoch skip --

  int _epoch = 0;
  Future<bool>? _renewInFlight;

  /// Whether the last [doRenew] failure was a credential-level error
  /// (HTTP 401 from the renew endpoint), as opposed to a server error (500)
  /// or network issue. [SessionTree.withCookie] uses this to decide whether
  /// the two-level parent-renew fallback is worth attempting: a 500 from the
  /// downstream endpoint won't be fixed by re-minting the parent tgc, so we
  /// skip the escalation entirely.
  bool _lastRenewWasCredentialError = false;
  bool get lastRenewWasCredentialError => _lastRenewWasCredentialError;

  /// Current epoch. Bumped after every successful [renew]. Callers capture
  /// this when reading cookies and pass it to [renewIfNeeded].
  int get epoch => _epoch;

  /// Bump epoch and cascade to children (clear their derived cookies).
  /// Does NOT call notifyListeners() on this node — the caller is
  /// responsible for notifying: top-level nodes are notified by
  /// [persist]→[setAccount] (which fires before this), and non-top-level
  /// nodes call notifyListeners() explicitly after this. This avoids a
  /// double-notify storm where both persist and markRenewed fire on the
  /// same node, each cascading through SessionTree → ThirdPartyAuthService
  /// → AssignmentService.fetchAssignments + SyncService.pushIfDue.
  @protected
  void markRenewed() {
    _epoch++;
    // Cascade: parent renewed → children's derived cookies are now stale.
    for (final child in _children) {
      child.onParentRenewed();
    }
  }

  /// Called by the parent's [markRenewed] when the parent's credentials
  /// changed. Non-top-level nodes clear their derived cookie (it was minted
  /// from the old parent credential and is now invalid); top-level nodes
  /// are unaffected.
  @protected
  void onParentRenewed() {
    if (parent != null) {
      _derivedCookie = null;
      // Clear persisted cookie too — it was minted from the old parent tgc
      // and is now invalid. The next withCookie call will re-mint.
      final pd = persistDerived;
      if (pd != null) {
        unawaited(pd(id, null));
      }
      notifyListeners();
    }
  }

  /// Mode-specific renew. MUST persist refreshed credentials (top-level) or
  /// mint the downstream cookie (non-top-level) and call [markRenewed] on
  /// success. Returns true on success, false on failure.
  Future<bool> doRenew() async {
    switch (renewMode) {
      case RenewMode.cpdailySession:
        return _renewCpdailySession();
      case RenewMode.password:
        return _renewWithPassword();
      case RenewMode.parentCookie:
        return _renewWithParentCookie();
      case null:
        return false;
    }
  }

  /// CpDaily keep-alive: POST /auth/renew with stored session fields.
  Future<bool> _renewCpdailySession() async {
    final acc = _account;
    if (acc == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('${baseUrl()}${renewPath ?? '/auth/renew'}'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'sessionToken': acc.raw['sessionToken'] ?? '',
          'tgc': acc.raw['tgc'] ?? '',
          'userId': acc.raw['userId'] ?? '',
          'tenantId': acc.raw['tenantId'] ?? '',
        }),
        tag: 'cpdailyRenew',
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return false;

      final newRaw = {
        ...acc.raw,
        'sessionToken':
            data['sessionToken'] as String? ?? acc.raw['sessionToken'] ?? '',
        'tgc': data['tgc'] as String? ?? acc.raw['tgc'] ?? '',
        'userId': data['userId'] as String? ?? acc.raw['userId'] ?? '',
        'tenantId':
            data['tenantId'] as String? ?? acc.raw['tenantId'] ?? '',
        'cookies': data['cookies'] as String? ?? acc.raw['cookies'] ?? '',
      };
      final updated = ThirdPartyAccount(
        platform: acc.platform,
        account: acc.account,
        sid: acc.sid,
        name: acc.name,
        email: acc.email,
        token: acc.token,
        expire: acc.expire,
        raw: newRaw,
        hydroOrigin: acc.hydroOrigin,
        hydroDomains: acc.hydroDomains,
        boundAt: acc.boundAt,
        autoRenew: acc.autoRenew,
        password: acc.password,
      );
      _account = updated;
      await persist(updated);
      markRenewed();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Password re-authentication (gradescope, hydro): POST the stored
  /// account+password, receive a fresh token.
  Future<bool> _renewWithPassword() async {
    final acc = _account;
    if (acc == null || !acc.autoRenew) return false;
    final pw = acc.password;
    if (pw == null || pw.isEmpty) return false;
    try {
      final body = <String, dynamic>{
        'account': acc.account,
        'password': pw,
      };
      if (id == 'hydro' &&
          acc.hydroOrigin != null &&
          acc.hydroOrigin!.isNotEmpty) {
        body['args'] = {'url': acc.hydroOrigin};
      }
      final resp = await http.post(
        Uri.parse('${baseUrl()}${renewPath ?? '/auth/third-party/$id'}'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(body),
        tag: 'thirdPartyRenew:$id',
      );
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return false;
      final d = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final token = d['token'] as String?;
      if (token == null || token.isEmpty) return false;
      final renewed = ThirdPartyAccount(
        platform: acc.platform,
        account: acc.account,
        sid: d['sid'] as String? ?? acc.sid,
        name: d['name'] as String? ?? acc.name,
        email: d['email'] as String? ?? acc.email,
        token: token,
        expire: (d['expire'] as num?)?.toInt() ?? acc.expire,
        raw: (d['raw'] as Map?)?.cast<String, dynamic>() ?? acc.raw,
        hydroOrigin: acc.hydroOrigin,
        hydroDomains: acc.hydroDomains,
        boundAt: acc.boundAt,
        autoRenew: true,
        password: pw,
      );
      _account = renewed;
      await persist(renewed);
      markRenewed();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Downstream cookie minting (eams, elearning): POST the parent's tgc,
  /// receive a downstream cookie string.
  Future<bool> _renewWithParentCookie() async {
    final tgc = parent?.rawFields['tgc'] as String? ?? '';
    if (tgc.isEmpty) {
      _lastRenewWasCredentialError = true;
      return false;
    }
    try {
      final resp = await http.post(
        Uri.parse('${baseUrl()}${renewPath ?? '/auth/third-party/$id'}'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({'tgc': tgc}),
        tag: 'downstreamRenew:$id',
      );
      // 401 → parent tgc is stale/invalid → credential error (worth
      // escalating to parent renew). 5xx → server/transient failure →
      // NOT a credential error (escalation won't help).
      _lastRenewWasCredentialError = resp.statusCode == 401;
      if (resp.statusCode != 200) return false;
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      if (data['success'] != true) return false;
      final d = (data['data'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cookie = d['token'] as String?;
      if (cookie == null || cookie.isEmpty) return false;
      _derivedCookie = cookie;
      // Persist so cold start can skip the SSO bounce.
      final pd = persistDerived;
      if (pd != null) {
        unawaited(pd(id, cookie));
      }
      // markRenewed cascades to children (none here) but does NOT notify
      // this node — notify explicitly for the downstream cookie change.
      markRenewed();
      notifyListeners();
      return true;
    } catch (_) {
      _lastRenewWasCredentialError = false;
      return false;
    }
  }

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
  String toString() => 'SessionNode($id)';
}
