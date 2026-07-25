import 'dart:async';
import 'dart:convert';


import '../../models/third_party_account.dart';
import '../http_client.dart';
import 'cookie_provider.dart';
import 'session_node.dart';

/// Callback the facade ([ThirdPartyAuthService]) installs so a node can
/// persist a refreshed [ThirdPartyAccount] back into secure storage and fire
/// the external change notification (listeners + cloud-sync push hook) in one
/// place. Returns nothing; the node owns the in-memory account afterwards.
typedef PersistAccount = Future<void> Function(ThirdPartyAccount updated);

/// Callback to read the current API base URL (depends on storage settings).
typedef BaseUrlGetter = String Function();

/// The CpDaily session node — the single source of CASTGC / CpDaily cookies.
///
/// Wraps the `egate` [ThirdPartyAccount]. Renewal POSTs to `/auth/renew` with
/// the stored session token + tgc; the response rotates the CpDaily session.
/// On success the refreshed raw is persisted via [persist] and [markRenewed]
/// bumps the epoch so concurrent 401-retry callers skip their own renew.
///
/// This node is the **parent** of [IdsSessionNode]: the IDS SSO cookies are
/// derived from (and refreshed via) this CpDaily session.
class CpdailySessionNode extends SessionNode {
  CpdailySessionNode({
    required this.persist,
    required this.http,
    required this.baseUrl,
  }) : super(id: 'egate');

  final PersistAccount persist;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;
  ThirdPartyAccount? _account;

  /// The wrapped account. Set by the facade on bind/unbind/replaceAll.
  ThirdPartyAccount? get account => _account;

  void setAccount(ThirdPartyAccount? acc) {
    _account = acc;
    notifyListeners();
  }

  @override
  bool get isAvailable => _account != null && cookieProvider != null;

  @override
  CookieProvider? get cookieProvider {
    final acc = _account;
    if (acc == null) return null;
    final raw = acc.raw;
    final baseCookies = (raw['cookies'] as String?) ?? '';
    final tgc = (raw['tgc'] as String?) ?? '';
    final cookies = tgc.isEmpty
        ? baseCookies
        : (baseCookies.isNotEmpty
            ? '$baseCookies; CASTGC=$tgc'
            : 'CASTGC=$tgc');
    if (cookies.isEmpty) return null;
    return CookieProvider(
      cookies: cookies,
      studentId: acc.sid ?? '',
      domain: 'ids.shanghaitech.edu.cn',
    );
  }

  /// Raw fields downstream services (OA gym) read alongside cookies.
  Map<String, dynamic> get rawFields => _account?.raw ?? const {};

  @override
  Future<bool> doRenew() async {
    final acc = _account;
    if (acc == null) return false;
    try {
      final resp = await http.post(
        Uri.parse('${baseUrl()}/auth/renew'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode({
          'sessionToken': acc.raw['sessionToken'] ?? '',
          'tgc': acc.raw['tgc'] ?? '',
          'userId': acc.raw['userId'] ?? '',
          'tenantId': acc.raw['tenantId'] ?? '',
        }),
        tag: 'egateCpDailyRenew',
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
}

/// The IDS SSO cookie node — a **child** of [CpdailySessionNode].
///
/// IDS cookies are minted from the CpDaily session (CASTGC) via an SSO bounce.
/// Renewal walks up to the parent CpDaily session, renews *it* if stale, then
/// re-derives the IDS cookies. This is the "ids 走 ids cpdaily renew" path:
/// independent renew implementation that delegates the underlying session
/// refresh to the parent.
///
/// The IDS cookies live in the same egate [ThirdPartyAccount.raw] under
/// `idsCookies` / `idsDomain`, so no separate storage entry is needed.
class IdsSessionNode extends SessionNode {
  IdsSessionNode({required CpdailySessionNode cpdaily})
      : _cpdaily = cpdaily,
        super(id: 'ids') {
    _cpdaily.addListener(_onParentChanged);
  }

  final CpdailySessionNode _cpdaily;

  void _onParentChanged() {
    // Parent renewed → our derived IDS cookies may be stale; bump epoch so a
    // pending caller's renewIfNeeded re-reads fresh state. We do NOT clear
    // idsCookies here (they may still be valid); renew will overwrite them.
    notifyListeners();
  }

  @override
  bool get isAvailable => _cpdaily.isAvailable;

  @override
  CookieProvider? get cookieProvider {
    final raw = _cpdaily.rawFields;
    final idsCookies = (raw['idsCookies'] as String?) ?? '';
    if (idsCookies.isEmpty) {
      // Fall back to the parent CpDaily cookies — IDS and CpDaily share the
      // CASTGC-bearing cookie set for ecourse/egate webviews. When a dedicated
      // IDS cookie set has been minted it takes precedence.
      return _cpdaily.cookieProvider;
    }
    return CookieProvider(
      cookies: idsCookies,
      studentId: _cpdaily.cookieProvider?.studentId ?? '',
      domain: (raw['idsDomain'] as String?) ?? 'ids.shanghaitech.edu.cn',
    );
  }

  @override
  Future<bool> doRenew() async {
    // IDS cookies are refreshed via the parent CpDaily session. Renew the
    // parent (single-flighted at its level); on success the parent's raw is
    // updated and our cookieProvider re-derives from it. A dedicated IDS
    // bounce endpoint can be wired here later; for now the CpDaily renew
    // already rotates the CASTGC-bearing cookie set IDS depends on.
    final ok = await _cpdaily.renew();
    if (ok) markRenewed();
    return ok;
  }
}

/// A leaf node for token-only third-party providers (Gradescope, Hydro).
///
/// These authenticate via bearer tokens consumed server-side by the TechPie
/// backend — they expose NO [CookieProvider]. Renewal is password-based
/// re-authentication (only when [ThirdPartyAccount.autoRenew] is set with a
/// stored password); a 401 from the backend means the token is dead and the
/// binding should be unbound, not renewed.
class LeafSessionNode extends SessionNode {
  LeafSessionNode({
    required this.platform,
    required this.persist,
    required this.http,
    required this.baseUrl,
  }) : super(id: platform.id);

  final ThirdPartyPlatform platform;
  final PersistAccount persist;
  final LoggingHttpClient http;
  final BaseUrlGetter baseUrl;

  ThirdPartyAccount? _account;

  ThirdPartyAccount? get account => _account;

  void setAccount(ThirdPartyAccount? acc) {
    _account = acc;
    notifyListeners();
  }

  @override
  bool get isAvailable => _account != null;

  @override
  CookieProvider? get cookieProvider => null;

  @override
  Future<bool> doRenew() async {
    final acc = _account;
    if (acc == null || !acc.autoRenew) return false;
    final pw = acc.password;
    if (pw == null || pw.isEmpty) return false;
    try {
      final body = <String, dynamic>{
        'account': acc.account,
        'password': pw,
      };
      if (platform == ThirdPartyPlatform.hydro &&
          acc.hydroOrigin != null &&
          acc.hydroOrigin!.isNotEmpty) {
        body['args'] = {'url': acc.hydroOrigin};
      }
      final resp = await http.post(
        Uri.parse('${baseUrl()}/auth/third-party/${platform.id}'),
        headers: {'Content-Type': 'application/json; charset=UTF-8'},
        body: jsonEncode(body),
        tag: 'thirdPartyRenew:${platform.id}',
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
}
