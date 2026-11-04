import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http_pkg;

import '../../models/renew_status.dart';
import '../../models/third_party_account.dart';
import '../http_client.dart';
import '../ids/campus_http.dart';
import 'cookie_provider.dart';

/// Callback the facade ([ThirdPartyAuthService]) installs so a top-level
/// node can persist a refreshed [ThirdPartyAccount] back into secure storage
/// and fire the external change notification (listeners + cloud-sync push
/// hook) in one place. Returns nothing; the node owns the in-memory account
/// afterwards. Only meaningful for top-level nodes (renewMode idsPasskey
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

/// Callback invoked after a successful renew when its keepalive probe also succeeds.
/// Callback the facade installs so every node can persist successful probe data.
typedef PersistProbe = Future<void> Function(
  String nodeId,
  KeepaliveResult result,
);

/// Callback a non-top-level node installs to persist its derived downstream
/// cookie into secure storage (or clear it when the parent renews).
typedef PersistDerivedCookie = Future<void> Function(
  String nodeId,
  String? cookie,
);

/// Callback to read the current API base URL (depends on storage settings).
typedef BaseUrlGetter = String Function();

/// Determines how a node calculates its next scheduled renewal.
enum RenewSchedule {
  none,
  idsDefault,
  accountExpiry,
  derivedCookie,
}

/// Persists the next scheduled renewal timestamp for a session node.
typedef PersistRenewTimestamp = Future<void> Function(
  String nodeId,
  DateTime? timestamp,
);

/// Result of a [SessionNode.probe] keepalive check.
class KeepaliveResult {
  final bool success;
  final String display;
  final int? statusCode;
  final String? rawBody;
  final String? cookies;

  const KeepaliveResult(
    this.success, {
    required this.display,
    this.statusCode,
    this.rawBody,
    this.cookies,
  });
}

/// Configuration for a lightweight keepalive probe on a [SessionNode].
///
/// A manual [SessionNode.probe] call remains read-only from the caller's
/// perspective. The silent probe that follows a successful [renew] may return
/// updated cookies and identity data through [PersistProbe].
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
  /// Local IDS software Passkey login. Top-level campus session only.
  idsPasskey,

  /// Password re-authentication: POST /auth/third-party/`<apiPath>` with
  /// account/password. Top-level only (gradescope, hydro).
  password,

  /// Local CAS cookie exchange using the parent IDS session.
  parentCookie,
}

/// One node in the unified session tree.
///
/// Topology:
/// ```
/// SessionTree
/// ├── ids         (local IDS software Passkey login)
/// │   ├── eams        (child, local CAS login)
/// │   ├── elearning   (child, local CAS login)
/// │   ├── egateApp    (child, local CAS login)
/// │   └── oa          (child, local CAS login)
/// ├── gradescope  (top-level, account+password bind, bearer token)
/// └── hydro       (top-level, account+password bind, sid cookie)
/// ```
///
/// Every node exposes:
/// - [cookieProvider] — the [CookieProvider] view downstream apps read. For
///   top-level nodes the credential comes from the bound account (ids:
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
    this.localAccountRenew,
    this.localCanRenew,
    this.localCookieMint,
    this.persistDerived,
    this.recordRenewStatus,
    this.persistProbe,
    this.persistRenewTimestamp,
    this.renewSchedule = RenewSchedule.none,
    this.keepaliveConfig,
  });

  /// Stable identifier matching the platform id for top-level nodes.
  final String id;

  /// Optional parent — set when this node's session is derived from another
  /// (e.g. eams/elearning cookies are minted from the ids CASTGC). Null
  /// for roots.
  SessionNode? parent;

  /// Backend renew path for non-campus token services (Gradescope/Hydro).
  final String? renewPath;

  /// How this node renews. Null only for nodes that never renew.
  final RenewMode? renewMode;

  /// Backend bind route name for password services (Gradescope/Hydro).
  final String? apiPath;
  final Future<ThirdPartyAccount> Function(ThirdPartyAccount current)? localAccountRenew;
  final bool Function()? localCanRenew;
  final Future<String> Function(String nodeId, Map<String, dynamic> root)? localCookieMint;
  final PersistAccount persist;
  final PersistDerivedCookie? persistDerived;
  final PersistRenewStatus? recordRenewStatus;
  final PersistProbe? persistProbe;
  final PersistRenewTimestamp? persistRenewTimestamp;
  final RenewSchedule renewSchedule;
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
  Map<String, dynamic> get rawFields {
    return _account?.raw ?? const {};
  }

  void setAccount(ThirdPartyAccount? acc) {
    if (parent != null) return; // non-top-level: no account
    _account = acc;
    _nextRenewTimestamp = acc == null ? null : _defaultNextRenewTimestamp();
    if (acc == null) _lastProbeDisplay = null;
    notifyListeners();
  }

  void setDerivedCookie(String? cookie) {
    if (parent == null) return; // top-level: no derived cookie
    _derivedCookie = (cookie != null && cookie.isNotEmpty) ? cookie : null;
    if (_derivedCookie == null) _lastProbeDisplay = null;
    _nextRenewTimestamp =
        _derivedCookie == null ? null : (_nextRenewTimestamp ?? _defaultNextRenewTimestamp());
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
        studentId: id == 'ids' ? acc.idsStudentId : acc.sid ?? '',
        domain: _domain,
      );
    }
    // Non-top-level: derived cookie
    final c = _derivedCookie;
    if (parent?.isAvailable != true || c == null || c.isEmpty) return null;
    return CookieProvider(cookies: c, domain: _domain);
  }

  /// Top-level credential extraction: ids concatenates CASTGC onto the
  /// session cookies; gradescope/hydro use the bearer token directly.
  String _cookieFromAccount(ThirdPartyAccount acc) {
    if (id == 'ids') {
      if (acc.raw['authMethod'] != 'passkey') return '';
      final base = (acc.raw['cookies'] as String?) ?? '';
      if (RegExp(r'(^|;)\s*CASTGC=').hasMatch(base)) return base;
      final tgc = (acc.raw['tgc'] as String?) ?? '';
      return tgc.isEmpty ? base : (base.isNotEmpty ? '$base; CASTGC=$tgc' : 'CASTGC=$tgc');
    }
    return acc.token;
  }

  String get _domain => switch (id) {
        'ids' => 'ids.shanghaitech.edu.cn',
        'eams' => 'eams.shanghaitech.edu.cn',
        'elearning' => 'elearning.shanghaitech.edu.cn',
        'egateApp' => 'egate.shanghaitech.edu.cn',
        'oa' => 'oa.shanghaitech.edu.cn',
        _ => '',
      };

  /// True when this node has a usable session.
  bool get isAvailable {
    if (parent == null) {
      final cp = cookieProvider;
      return _account != null && cp != null && !cp.isEmpty;
    }
    return (parent?.isAvailable ?? false) && _derivedCookie != null && _derivedCookie!.isNotEmpty;
  }

  bool get canRenew {
    if (parent != null) return parent!.isAvailable || parent!.canRenew;
    if (renewMode == RenewMode.idsPasskey) {
      return _account?.raw['authMethod'] == 'passkey' && (localCanRenew?.call() ?? true);
    }
    return _account?.autoRenew == true && _account?.password?.isNotEmpty == true;
  }

  /// Human-readable display name for this node, suitable for UI labels.
  ///
  /// Campus identities come from the authenticated root profile. Probe text
  /// describes connectivity and must never replace a user name or student ID.
  String get displayName {
    final owner = parent?.account;
    if (parent != null) {
      if (owner == null) return '未绑定';
      if (id == 'eams' || id == 'egateApp') {
        final studentId = owner.idsStudentId;
        if (studentId.isNotEmpty) return studentId;
      }
      return owner.displayName;
    }
    if (_account != null) return _account!.displayName;
    return '未绑定';
  }

  String get probeDisplay => _lastProbeDisplay ?? '尚未检测';

  /// The next scheduled renewal event for this node.
  DateTime? _nextRenewTimestamp;
  DateTime? get nextRenewTimestamp => _nextRenewTimestamp;

  bool get isRenewDue {
    final next = _nextRenewTimestamp;
    return next != null && !DateTime.now().isBefore(next);
  }

  DateTime? _defaultNextRenewTimestamp() {
    final now = DateTime.now();
    return switch (renewSchedule) {
      RenewSchedule.idsDefault => now.add(const Duration(minutes: 10)),
      RenewSchedule.accountExpiry => _account?.expireAt?.subtract(
          const Duration(hours: 48),
        ),
      RenewSchedule.derivedCookie => now.add(const Duration(minutes: 10)),
      RenewSchedule.none => null,
    };
  }

  Future<void> scheduleNextRenew() async {
    _nextRenewTimestamp = _defaultNextRenewTimestamp();
    final persist = persistRenewTimestamp;
    if (persist != null) await persist(id, _nextRenewTimestamp);
  }

  void seedNextRenewTimestamp(DateTime? timestamp) {
    _nextRenewTimestamp = timestamp;
  }

  Future<bool> renewIfDue() async {
    if (!canRenew) return false;
    if (!isAvailable) return renew();
    if (!isRenewDue) return true;
    return renew();
  }

  // -- Renewal: single-flight + stale-epoch skip --

  int _epoch = 0;
  Future<void> clearNextRenewTimestamp() async {
    _nextRenewTimestamp = null;
    final persist = persistRenewTimestamp;
    if (persist != null) await persist(id, null);
  }

  Future<bool>? _renewInFlight;

  /// Whether the last [doRenew] failure was a credential-level error
  /// (HTTP 401 from the renew endpoint), as opposed to a server error (500)
  /// or network issue. [SessionTree.withCookie] uses this to decide whether
  /// the two-level parent-renew fallback is worth attempting: a 500 from the
  /// downstream endpoint won't be fixed by re-minting the parent tgc, so we
  /// skip the escalation entirely.
  bool _lastRenewWasCredentialError = false;
  String? lastRenewError;
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
      unawaited(clearNextRenewTimestamp());
      notifyListeners();
    }
  }

  /// Lightweight keepalive probe.  Sends the configured request with the
  /// node's current cookies and returns a [KeepaliveResult].  On success
  /// the result's display text is cached for [displayName].
  ///
  /// Does NOT mutate session state, persist, or trigger cascading renews.
  /// Network/probe failures preserve the previous display name.
  Future<KeepaliveResult> probe({bool silent = false}) async {
    final cfg = keepaliveConfig;
    if (cfg == null) {
      return const KeepaliveResult(false, display: 'no keepalive config');
    }
    final cp = cookieProvider;
    if (cp == null || cp.isEmpty) {
      return const KeepaliveResult(false, display: 'no session');
    }
    final owner = _account;
    final parentOwner = parent?.account;
    final beforeEpoch = _epoch;
    final parentEpoch = parent?.epoch;
    bool stillCurrent() =>
        identical(_account, owner) &&
        identical(parent?.account, parentOwner) &&
        _epoch == beforeEpoch &&
        parent?.epoch == parentEpoch;
    String cookies = cp.cookies;
    // Pre-flight: hit config endpoint to refresh session tokens (e.g. _WEU).
    if (cfg.preFlightPath != null) {
      try {
        final preUri =
            cfg.preFlightPath!.startsWith('http://') || cfg.preFlightPath!.startsWith('https://')
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
      if (!stillCurrent()) return const KeepaliveResult(false, display: 'session changed');
      final ok = cfg.successCheck?.call(resp) ??
          cfg.bodyRegex?.hasMatch(resp.body) ??
          (resp.statusCode == 200);
      String display;
      if (cfg.displayText != null) {
        display = cfg.displayText!(resp);
      } else if (cfg.bodyRegex != null) {
        final m = cfg.bodyRegex!.firstMatch(resp.body);
        display = m?.group(1) ?? m?.group(0) ?? 'HTTP ${resp.statusCode}';
      } else {
        display = 'HTTP ${resp.statusCode}';
      }
      if (display.trim().isEmpty) display = 'HTTP ${resp.statusCode}';
      _lastProbeDisplay = ok
          ? display
          : resp.statusCode == 403
              ? 'HTTP 403（当前账号无此页面权限）'
              : 'HTTP ${resp.statusCode}';
      if (ok) {
        if (silent && parent != null && cookies.isNotEmpty) {
          _derivedCookie = cookies;
          await scheduleNextRenew();
        }
        if (!silent) notifyListeners();
      }
      return KeepaliveResult(
        ok,
        display: _lastProbeDisplay!,
        statusCode: resp.statusCode,
        rawBody: resp.body,
        cookies: cookies,
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
      case RenewMode.idsPasskey:
        return _renewIdsSession();
      case RenewMode.password:
        return _renewWithPassword();
      case RenewMode.parentCookie:
        return _renewWithParentCookie();
      case null:
        return false;
    }
  }

  /// Refresh IDS directly with the app-owned software credential.
  Future<bool> _renewIdsSession() async {
    final current = _account;
    if (current == null || localAccountRenew == null) return false;
    try {
      final updated = await localAccountRenew!(current);
      if (!identical(_account, current)) return false;
      _account = updated;
      markRenewed();
      await persist(updated);
      return true;
    } on IdsException catch (error) {
      _lastRenewWasCredentialError = error.credentialRejected;
      lastRenewError = error.message;
      return false;
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
      if (id == 'hydro' && acc.hydroOrigin != null && acc.hydroOrigin!.isNotEmpty) {
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
      // A restore or rebind may have replaced the owner during this request.
      if (!identical(_account, acc)) return false;
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

  /// Obtain the downstream session locally through its existing CAS flow.
  Future<bool> _renewWithParentCookie() async {
    final root = parent?.account;
    final parentEpoch = parent?.epoch;
    if (root == null || parent?.isAvailable != true || (root.raw['tgc'] as String? ?? '').isEmpty) {
      _lastRenewWasCredentialError = true;
      return false;
    }
    if (localCookieMint == null) return false;
    try {
      final cookie = await localCookieMint!(id, root.raw);
      if (!identical(parent?.account, root) || parent?.epoch != parentEpoch) return false;
      _derivedCookie = cookie;
      final pd = persistDerived;
      if (pd != null) await pd(id, cookie);
      if (!identical(parent?.account, root) || parent?.epoch != parentEpoch) return false;
      markRenewed();
      notifyListeners();
      return true;
    } on IdsException catch (error) {
      _lastRenewWasCredentialError = error.credentialRejected;
      lastRenewError = error.message;
      return false;
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
    _lastRenewWasCredentialError = false;
    lastRenewError = null;
    final ok = await doRenew();
    if (ok) await scheduleNextRenew();
    if (ok && keepaliveConfig != null) {
      final owner = _account;
      final parentOwner = parent?.account;
      final beforeEpoch = _epoch;
      final parentEpoch = parent?.epoch;
      final result = await probe(silent: true);
      if (!identical(_account, owner) ||
          !identical(parent?.account, parentOwner) ||
          _epoch != beforeEpoch ||
          parent?.epoch != parentEpoch) {
        return false;
      }
      if (result.success) {
        final persist = persistProbe;
        if (persist != null) await persist(id, result);
      }
    }
    final status = RenewStatus(
      at: DateTime.now(),
      success: ok,
      error: ok
          ? null
          : (lastRenewError ?? (_lastRenewWasCredentialError ? 'credential' : 'transient')),
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
    if (!isAvailable && !canRenew) return false;
    // A concurrent renew already advanced past the caller's snapshot —
    // the cookies the caller will re-read are already fresh. Skip.
    if (_epoch > beforeEpoch) return true;
    return renew();
  }

  @override
  String toString() => 'SessionNode($id)';
}
