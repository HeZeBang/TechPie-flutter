import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http_pkg;

import '../../models/renew_status.dart';
import '../../models/third_party_account.dart';
import '../http_client.dart';
import 'cookie_provider.dart';

/// Callback the facade ([ThirdPartyAuthService]) installs so a top-level
/// node can persist a refreshed [ThirdPartyAccount] back into secure storage
/// and fire the external change notification (listeners + cloud-sync push
/// hook) in one place. Returns nothing; the node owns the in-memory account
/// afterwards. Only meaningful for top-level nodes (renewMode cpdailySession
/// or password); non-top-level nodes skip persist (derived cookies are
/// ephemeral). [force] requests the cloud-sync push bypass its throttle —
/// set by renew() call sites since a successful renew must not wait for the
/// next throttle window.
typedef PersistAccount = Future<void> Function(
  ThirdPartyAccount updated, {
  bool force,
});

/// Callback the facade installs so every node (top-level or derived) can
/// persist its latest renew outcome for the "linked accounts" status
/// indicator. Local-only — never part of the cloud-sync envelope.
typedef PersistRenewStatus = Future<void> Function(
  String nodeId,
  RenewStatus status,
);

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


/// Result of a [SessionNode.probe] keepalive check.
class KeepaliveResult {
  final bool success;
  final String display;
  final int? statusCode;
  final String? rawBody;

  const KeepaliveResult(this.success, {
    required this.display,
    this.statusCode,
    this.rawBody,
  });
}

/// Configuration for a lightweight keepalive probe on a [SessionNode].
///
/// Unlike [SessionNode.renew], a keepalive probe is **read-only**:
/// it does not mutate credentials, bump the epoch, persist, or cascade
/// to children.  It only verifies the current session is still alive
/// and optionally extracts a display name from the response.
///
/// Both [successCheck] and [displayText] have sensible defaults when
/// omitted (status 200, plain "HTTP NNN" display), so the simplest
/// config is just a [method] + [path].
class KeepaliveConfig {
  /// HTTP method. Defaults to GET.
  final String method;

  /// URL path relative to [SessionNode.baseUrl].
  final String path;

  /// Optional JSON-encoded request body (POST only).
  final Map<String, dynamic>? body;

  /// Extra headers merged on top of the injected Cookie header.
  final Map<String, String>? headers;

  /// Determines whether the response indicates a live session.
  /// Default: status code 200 when neither [successCheck] nor [bodyRegex]
  /// is provided.
  final bool Function(http_pkg.Response response)? successCheck;

  /// If non-null, the response body must match this regex for the probe
  /// to be considered successful.  Capture group 1 is used as the display
  /// text (overridden by [displayText] when both are provided).  Falls
  /// back to the full match when no group is present.
  final RegExp? bodyRegex;

  /// Extracts a human-readable status string from the response.
  ///
  /// Default priority: [displayText] > [bodyRegex] group 1 > `"HTTP NNN"`.

  /// Optional pre-flight URL.  If set, [SessionNode.probe] hits this URL
  /// first (always GET) and merges any `Set-Cookie` headers from the
  /// response into the cookie before the main request.  Used when the
  /// target endpoint requires a fresh session token (e.g. egate's
  /// `funauthapp/getAppConfig` refreshes the `_WEU` cookie).
  final String? preFlightPath;
  final String Function(http_pkg.Response response)? displayText;

  const KeepaliveConfig({
    this.method = 'GET',
    required this.path,
    this.preFlightPath,
    this.body,
    this.headers,
    this.successCheck,
    this.bodyRegex,
    this.displayText,
  });
}

/// Merge `Set-Cookie` response header values into an existing cookie string.
/// Extracts `key=value` pairs (ignoring path/domain/expires attributes) and
/// updates or appends them.
String _mergeSetCookie(String existing, String setCookieHeader) {
  final updated = <String, String>{};
  // Preserve existing cookies.
  for (final part in existing.split(';')) {
    final trimmed = part.trim();
    final eq = trimmed.indexOf('=');
    if (eq > 0) {
      updated[trimmed.substring(0, eq).trim()] = trimmed.substring(eq + 1).trim();
    }
  }
  // Apply updates from Set-Cookie.  Multiple cookies may be present in
  // the header, each separated by a comma NOT inside a quoted value.
  // A conservative heuristic: split on `; ` first (each set-cookie ends
  // with attributes terminated by `;`), then extract leading `key=value`.
  for (final entry in setCookieHeader.split('\n')) {
    final semi = entry.indexOf(';');
    final kvPart = semi > 0 ? entry.substring(0, semi) : entry;
    final eq = kvPart.indexOf('=');
    if (eq > 0) {
      updated[kvPart.substring(0, eq).trim()] = kvPart.substring(eq + 1).trim();
    }
  }
  return updated.entries.map((e) => '${e.key}=${e.value}').join('; ');
}

/// How a [SessionNode] renews its credentials.
enum RenewMode {
  /// CpDaily session keep-alive: POST /auth/renew with stored
  /// sessionToken/tgc/userId/tenantId. Top-level only.
  cpdailySession,

  /// Password re-authentication: POST /auth/third-party/`<apiPath>` with
  /// account/password. Top-level only (gradescope, hydro).
  password,

  /// Downstream cookie minting: POST /auth/third-party/`<id>` with the parent
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
/// │   ├── elearning   (child, /auth/third-party/elearning, parent tgc)
/// │   └── egateApp    (child, /auth/third-party/egate-app, parent tgc)
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
    this.recordRenewStatus,
    this.keepaliveConfig,
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
  final PersistRenewStatus? recordRenewStatus;
  final LoggingHttpClient http;
  /// Optional keepalive probe configuration. When non-null, [probe] can be
  /// called to verify the current session without mutating state.
  final KeepaliveConfig? keepaliveConfig;
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

  /// Human-readable display name from the most recent successful [probe].
  /// Null until a probe has ever succeeded.  [displayName] falls back
  /// through account.name -> id when this is null.
  String? _lastProbeDisplay;

  /// Raw fields from the bound account (top-level only). Downstream services
  /// (OA gym) and child nodes read tgc/sessionToken/userId/tenantId through
  /// this. Returns an empty map for non-top-level nodes.
  Map<String, dynamic> get rawFields => _account?.raw ?? const {};

  /// Set the bound account. Only meaningful for top-level nodes; calling on
  /// a non-top-level node is a no-op.
  void setAccount(ThirdPartyAccount? acc) {
    if (parent != null) return; // non-top-level: no account
    _account = acc;
    if (acc == null) _lastProbeDisplay = null;
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
        'egateApp' => 'egate.shanghaitech.edu.cn',
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

  /// Human-readable display name for this node, suitable for UI labels.
  ///
  /// Priority: most recent successful probe display > account name > id.
  String get displayName => _lastProbeDisplay ?? _account?.name ?? id;

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

  /// Outcome of the most recent renew attempt (this session, or seeded from
  /// persisted [RenewStatus] at boot). Null until a renew has ever completed.
  DateTime? _lastRenewAt;
  bool? _lastRenewSucceeded;
  DateTime? get lastRenewAt => _lastRenewAt;
  bool? get lastRenewSucceeded => _lastRenewSucceeded;

  /// Seed the in-memory renew-status cache from a persisted [RenewStatus] at
  /// boot, without notifying (this is hydration, not a state change the UI
  /// needs to react to — mirrors [setDerivedCookie]).
  void seedRenewStatus(RenewStatus? status) {
    _lastRenewAt = status?.at;
    _lastRenewSucceeded = status?.success;
  }

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
      _lastProbeDisplay = null; // session invalidated, probe data is stale
      // Clear persisted cookie too — it was minted from the old parent tgc
      // and is now invalid. The next withCookie call will re-mint.
      final pd = persistDerived;
      if (pd != null) {
        unawaited(pd(id, null));
      }
      notifyListeners();
    }
  }

  /// Lightweight keepalive probe.  Sends the configured request with the
  /// node's current cookies and returns a [KeepaliveResult].  On success
  /// the result's display text is cached for [displayName].
  ///
  /// Does NOT mutate session state, persist, or trigger cascading renews.
  /// Network/probe failures preserve the previous display name.
  Future<KeepaliveResult> probe() async {
    final cfg = keepaliveConfig;
    if (cfg == null) {
      return const KeepaliveResult(false, display: 'no keepalive config');
    }
    final cp = cookieProvider;
    if (cp == null || cp.isEmpty) {
      return const KeepaliveResult(false, display: 'no session');
    }
    String cookies = cp.cookies;
    // Pre-flight: hit config endpoint to refresh session tokens (e.g. _WEU).
    if (cfg.preFlightPath != null) {
      try {
        final preUri = cfg.preFlightPath!.startsWith('http://') ||
                cfg.preFlightPath!.startsWith('https://')
            ? Uri.parse(cfg.preFlightPath!)
            : Uri.parse('${baseUrl()}${cfg.preFlightPath}');
        final preResp = await http.get(
          preUri,
          headers: {'Cookie': cookies},
          tag: 'keepalive-pre:$id',
        );
        final sc = preResp.headers['set-cookie'];
        if (sc != null && sc.isNotEmpty) {
          cookies = _mergeSetCookie(cookies, sc);
        }
      } catch (_) {
        // Pre-flight failure is non-fatal — proceed with original cookies.
      }
    }
    final uri = cfg.path.startsWith('http://') || cfg.path.startsWith('https://')
        ? Uri.parse(cfg.path)
        : Uri.parse('${baseUrl()}${cfg.path}');
    final baseHeaders = <String, String>{
      'Cookie': cookies,
      if (cfg.headers != null) ...cfg.headers!,
    };
    try {
      final http_pkg.Response resp;
      switch (cfg.method.toUpperCase()) {
        case 'POST':
          resp = await http.post(
            uri,
            headers: {
              ...baseHeaders,
              'Content-Type': 'application/json; charset=UTF-8',
            },
            body: cfg.body != null ? jsonEncode(cfg.body) : null,
            tag: 'keepalive:$id',
          );
        case 'HEAD':
          resp = await http.head(
            uri,
            headers: baseHeaders,
            tag: 'keepalive:$id',
          );
        default:
          resp = await http.get(
            uri,
            headers: baseHeaders,
            tag: 'keepalive:$id',
          );
      }
      // Success detection: callback > bodyRegex > statusCode.
      final ok = cfg.successCheck?.call(resp) ??
          cfg.bodyRegex?.hasMatch(resp.body) ??
          (resp.statusCode == 200);
      // Display extraction: callback > bodyRegex group 1 > "HTTP NNN".
      String display;
      if (cfg.displayText != null) {
        display = cfg.displayText!(resp);
      } else if (cfg.bodyRegex != null) {
        final m = cfg.bodyRegex!.firstMatch(resp.body);
        display = m?.group(1) ?? m?.group(0) ?? 'HTTP ${resp.statusCode}';
      } else {
        display = 'HTTP ${resp.statusCode}';
      }
      if (!ok) display = 'HTTP ${resp.statusCode}';
      if (ok) {
        _lastProbeDisplay = display;
        notifyListeners();
      }
      return KeepaliveResult(ok,
        display: display,
        statusCode: resp.statusCode,
        rawBody: resp.body,
      );
    } catch (e) {
      return KeepaliveResult(false, display: e.toString());
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
      // force: true — a successful renew must push to the cloud immediately,
      // not wait for the pushIfDue throttle window.
      await persist(updated, force: true);
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
      // force: true — a successful renew must push to the cloud immediately,
      // not wait for the pushIfDue throttle window.
      await persist(renewed, force: true);
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
  ///
  /// _renewInFlight is only ever cleared via whenComplete on the OUTER
  /// future returned here — never synchronously inside [_renewTracked] —
  /// so a concurrent caller can never slip past the single-flight guard
  /// mid-attempt.
  Future<bool> renew() {
    if (_renewInFlight != null) return _renewInFlight!;
    final f = _renewTracked().whenComplete(() => _renewInFlight = null);
    _renewInFlight = f;
    return f;
  }

  /// Wraps [doRenew] to record the outcome (for the linked-accounts status
  /// indicator) regardless of [RenewMode]. Success already notifies via
  /// [persist]→[setAccount] (top-level) or the explicit notifyListeners()
  /// at the end of [_renewWithParentCookie] (child) — only failure needs a
  /// new notify here, to avoid the double-notify storm [markRenewed]'s doc
  /// comment already explains avoiding.
  Future<bool> _renewTracked() async {
    final ok = await doRenew();
    final status = RenewStatus(
      at: DateTime.now(),
      success: ok,
      error: ok
          ? null
          : (_lastRenewWasCredentialError ? 'credential' : 'transient'),
    );
    _lastRenewAt = status.at;
    _lastRenewSucceeded = ok;
    final rec = recordRenewStatus;
    if (rec != null) unawaited(rec(id, status));
    if (!ok) notifyListeners();
    return ok;
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
