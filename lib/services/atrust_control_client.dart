import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'atrust_crypto.dart';
import 'http_client.dart';
import 'storage_service.dart';

/// Which path the controller is asked to open the session on.
///
/// [browser] is unsigned and always available, but the controller re-verifies
/// the device with an SMS on every fresh login. [desktop] is what a trusted
/// terminal requires — only a session opened this way can be bound with
/// [AtrustControlClient.bindDevice], and only a trusted terminal skips the SMS
/// on later logins.
enum AtrustClientType { browser, desktop }

/// A login attempt's outcome.
enum AtrustStage {
  /// A live session exists; [AtrustControlClient.session] can be handed on.
  online,

  /// The controller demanded the SMS code it just sent; call [submitSms].
  needSms,

  /// No session, and nothing the user can do right now.
  unavailable,
}

/// Result of [AtrustControlClient.ensureOnline] / [login] / [submitSms].
class AtrustLoginState {
  const AtrustLoginState(this.stage, {this.hint = '', this.restored = false});

  final AtrustStage stage;

  /// What to show the user: the masked phone when a code was sent, otherwise a
  /// short reason.
  final String hint;

  /// True when the session came from storage rather than a fresh login.
  final bool restored;

  bool get isOnline => stage == AtrustStage.online;
}

/// The controller session the tunnel needs: who we are, the controller's own
/// cookies, and the routing policy **verbatim** (the core library parses it, so
/// the two never disagree about a rule).
class AtrustSession {
  const AtrustSession({
    required this.sid,
    required this.deviceId,
    required this.username,
    required this.baseUrl,
    required this.csrfToken,
    required this.cookies,
    required this.gateways,
    required this.dns,
    required this.policyJson,
    required this.savedAt,
    this.trusted = false,
  });

  final String sid;
  final String deviceId;
  final String username;
  final String baseUrl;
  final String csrfToken;

  /// Controller cookies, name → value (`sid`, `sid.sig`, `sid-legacy`, …).
  final Map<String, String> cookies;
  final List<String> gateways;
  final List<String> dns;

  /// The `clientResource` response's `data` object, untouched.
  final String policyJson;
  final DateTime savedAt;

  /// True once the controller lists this device as a trusted terminal, which is
  /// what stops it demanding an SMS on every fresh login.
  final bool trusted;

  Map<String, dynamic> toJson() => {
        'sid': sid,
        'device_id': deviceId,
        'username': username,
        'base_url': baseUrl,
        'csrf_token': csrfToken,
        'cookies': cookies,
        'gateways': gateways,
        'dns': dns,
        'policy': policyJson,
        'trusted': trusted,
        'saved_at': savedAt.toIso8601String(),
      };

  static AtrustSession? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final cookies = <String, String>{};
    final rawCookies = raw['cookies'];
    if (rawCookies is Map) {
      rawCookies.forEach((k, v) {
        if (k is String && v is String) cookies[k] = v;
      });
    }
    String str(String key) => (raw[key] as String?) ?? '';
    List<String> list(String key) =>
        (raw[key] as List?)?.whereType<String>().toList() ?? const [];
    final session = AtrustSession(
      sid: str('sid'),
      deviceId: str('device_id'),
      username: str('username'),
      baseUrl: str('base_url'),
      csrfToken: str('csrf_token'),
      cookies: cookies,
      gateways: list('gateways'),
      dns: list('dns'),
      policyJson: str('policy'),
      trusted: raw['trusted'] == true,
      savedAt: DateTime.tryParse(str('saved_at')) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
    if (session.sid.isEmpty || session.cookies.isEmpty) return null;
    return session;
  }
}

/// A trusted-terminal record, as the controller reports it.
class AtrustTrustedDevice {
  const AtrustTrustedDevice({
    required this.id,
    required this.name,
    required this.deviceType,
    required this.online,
  });

  final String id;
  final String name;
  final String deviceType;
  final bool online;
}

/// The account's trusted-terminal state, including whether this device is one.
class AtrustTrustState {
  const AtrustTrustState({
    required this.selfId,
    required this.currentTrustStatus,
    required this.enable,
    required this.devices,
  });

  final String selfId;

  /// The controller's verdict for *this* device: non-zero means trusted.
  final int currentTrustStatus;
  final bool enable;
  final List<AtrustTrustedDevice> devices;

  bool get isTrusted => currentTrustStatus != 0;
}

/// A control-plane failure. [code] is stable enough to branch on, [message] is
/// meant for a log line (never for the user verbatim).
class AtrustException implements Exception {
  const AtrustException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'AtrustException($code): $message';
}

/// The campus aTrust **control plane**: IDS login through CAS, the controller's
/// session handshake, SMS second factor and the routing policy.
///
/// It is deliberately plain HTTP/JSON — the packet path (frames, gateway TLS,
/// per-connection auth, the gVisor fallback) lives in the core library, which
/// this hands a [AtrustSession] to. Nothing here touches the primary GeekPie
/// session; the CASTGC comes from the campus binding via [castgc].
class AtrustControlClient {
  AtrustControlClient({
    required LoggingHttpClient http,
    required StorageService storage,
    required String Function() castgc,
    Uri? baseUrl,
    this.clientType = AtrustClientType.browser,
    Future<void> Function(String stage)? onTrace,
  })  : _http = http,
        _storage = storage,
        _castgc = castgc,
        _onTrace = onTrace,
        baseUrl = baseUrl ?? defaultBaseUrl;

  static final Uri defaultBaseUrl =
      Uri.parse('https://vpn.shanghaitech.edu.cn');

  static const platform = 'Mac';
  static const lang = 'zh-CN';

  /// The campus's CAS service name for aTrust.
  static const casDomain = 'Shanghaitech.edu.cn';

  static const _maxRedirects = 8;

  final LoggingHttpClient _http;
  final StorageService _storage;
  final String Function() _castgc;
  final Future<void> Function(String stage)? _onTrace;

  final Uri baseUrl;

  /// Which path the session is opened on (see [AtrustClientType]).
  final AtrustClientType clientType;

  AtrustSession? _session;
  final Map<String, String> _cookies = {};

  /// The controller's own name for [clientType]; the desktop one is what a
  /// trusted terminal requires.
  String get wireClientType =>
      clientType == AtrustClientType.desktop ? 'SDPClient' : 'SDPBrowserClient';

  /// §10.1's key, kept for the life of the session: derived from the pre-login
  /// challenge, it also signs post-login trusted requests.
  String _signKey = '';

  /// Serializes the login sequence. Two taps in a row would otherwise run two
  /// handshakes over one controller session: the second one's reportEnv lands on
  /// a session the first already owns, and the controller answers with a refusal
  /// that looks like a credentials problem.
  Future<void> _gate = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() body) {
    final result = _gate.then((_) => body());
    _gate = result.then((_) {}, onError: (Object _) {});
    return result;
  }

  AtrustSession? get session => _session;

  /// A session from storage, or one just obtained. [restored] distinguishes the
  /// two. Returns [AtrustStage.needSms] when the controller wants a code — the
  /// caller then drives the UI and calls [submitSms].
  Future<AtrustLoginState> ensureOnline() =>
      _serialize(() => _ensureOnline());

  Future<AtrustLoginState> _ensureOnline() async {
    if (_session != null) {
      return const AtrustLoginState(AtrustStage.online, restored: true);
    }
    final raw = await _storage.loadAtrustSession();
    if (raw != null) {
      final restored = AtrustSession.fromJson(jsonDecode(raw));
      if (restored != null) {
        _session = restored;
        _cookies
          ..clear()
          ..addAll(restored.cookies);
        try {
          final info = await _onlineInfo();
          if (info['isOnline'] == true) {
            return const AtrustLoginState(AtrustStage.online, restored: true);
          }
        } on AtrustException catch (error) {
          await _trace('restored session rejected: ${error.code}');
        }
        _session = null;
      }
    }
    return _login();
  }

  /// Runs the whole login. Serialized with [ensureOnline]/[submitSms]. Returns [AtrustStage.needSms] when the controller
  /// demanded a code (having asked it to send one), [online] otherwise.
  Future<AtrustLoginState> login() => _serialize(_login);

  Future<AtrustLoginState> _login() async {
    final castgc = _castgc();
    if (castgc.isEmpty) {
      return const AtrustLoginState(
        AtrustStage.unavailable,
        hint: '未绑定校园账号（eGate/CpDaily 会话不可用）',
      );
    }
    final deviceId = await _deviceId();
    final config = await _authConfig();
    final csrf = (config['security'] as Map?)?['csrfToken'] as String? ?? '';
    await _trace('authConfig ok (client $wireClientType)');
    if (csrf.isEmpty) {
      throw const AtrustException('authConfig', 'missing security.csrfToken');
    }
    _cookies.addAll(_parseCookieHeader(castgc));

    // The desktop path has to prove it holds the key the controller derived
    // from the challenge it just issued; that proof is what lets the session be
    // bound as a trusted terminal later.
    String encryptedChallenge = '';
    if (clientType == AtrustClientType.desktop) {
      final antiMitm = (config['antiMITMAttackData'] as Map?) ?? const {};
      final modulus = (antiMitm['devicePubKeyMod'] as String?) ?? '';
      final exponent = (antiMitm['devicePubKeyExp'] as String?) ?? '';
      final challenge = (antiMitm['challenge'] as String?) ?? '';
      if (modulus.isEmpty || challenge.isEmpty) {
        throw const AtrustException(
          'authConfig',
          'desktop login needs antiMITMAttackData.challenge',
        );
      }
      _signKey = AtrustCrypto.signKey(
        devicePubKeyMod: modulus,
        devicePubKeyExp: exponent,
        challenge: challenge,
      );
      encryptedChallenge = await AtrustCrypto.encryptedChallenge(
        devicePubKeyMod: modulus,
        devicePubKeyExp: exponent,
        challenge: challenge,
      );
    }

    final casTicket = await _casTicket();
    await _trace('CAS ok, ticket ${casTicket.length}B');
    await _reportEnv(casTicket, deviceId, config, csrf, encryptedChallenge);
    await _trace('reportEnv ok (desktop=${clientType == AtrustClientType.desktop})');
    final needsSms = await _authCheck(csrf);
    await _trace('authCheck: ${needsSms ? 'SMS required' : 'no SMS required'}');

    String sidTicket;
    String hint = '';
    if (needsSms) {
      hint = await _sendSms(csrf);
      await _trace('SMS requested');
      _pending = _PendingLogin(deviceId: deviceId, csrf: csrf, hint: hint);
      return AtrustLoginState(AtrustStage.needSms, hint: hint);
    }
    // No SMS was demanded. That is the trusted-device path — but a device that
    // is *not* trusted yet refuses it, and the honest recovery is to ask for the
    // code after all rather than to fail with the controller's refusal.
    try {
      sidTicket = await _ticketExchange(csrf);
      await _trace('ticketExchange ok (already trusted)');
    } on AtrustException catch (error) {
      await _trace('ticketExchange refused (${error.code}); asking for SMS');
      hint = await _sendSms(csrf);
      _pending = _PendingLogin(deviceId: deviceId, csrf: csrf, hint: hint);
      return AtrustLoginState(AtrustStage.needSms, hint: hint);
    }
    return _finishLogin(sidTicket, deviceId, csrf, hint);
  }

  /// Completes a login that [login] left at [AtrustStage.needSms].
  Future<AtrustLoginState> submitSms(String code) =>
      _serialize(() => _submitSms(code));

  Future<AtrustLoginState> _submitSms(String code) async {
    final pending = _pending;
    if (pending == null) {
      throw const AtrustException(
          'noSmsFlow', 'submitSms without a pending login',);
    }
    final sidTicket = await _checkSms(code, pending.csrf);
    final state = await _finishLogin(
      sidTicket,
      pending.deviceId,
      pending.csrf,
      pending.hint,
    );
    _pending = null;
    return state;
  }

  /// Drops the session locally and in storage. The controller session expires on
  /// its own; nothing here can revoke it early.
  Future<void> logout() async {
    _session = null;
    _pending = null;
    _cookies.clear();
    await _storage.clearAtrustSession();
  }

  _PendingLogin? _pending;

  Future<AtrustLoginState> _finishLogin(
    String sidTicket,
    String deviceId,
    String csrf,
    String hint,
  ) async {
    await _sessionIdExchange(sidTicket, csrf);
    await _trace('sessionIdExchange ok');
    final info = await _onlineInfo();
    if (info['isOnline'] != true) {
      throw const AtrustException('onlineInfo', 'controller reports offline');
    }
    final trusted = await _tryBindDevice(csrf);
    final policy = await _clientResource(csrf);
    final session = AtrustSession(
      sid: _cookies['sid'] ?? '',
      deviceId: deviceId,
      username: (info['username'] as String?) ?? '',
      baseUrl: baseUrl.toString(),
      csrfToken: csrf,
      cookies: Map<String, String>.from(_cookies),
      gateways: const [],
      dns: const [],
      policyJson: policy,
      trusted: trusted,
      savedAt: DateTime.now(),
    );
    _session = session;
    await _storage.saveAtrustSession(jsonEncode(session.toJson()));
    await _trace('online as ${session.username}');
    return AtrustLoginState(AtrustStage.online, hint: hint, restored: false);
  }

  // --- the sequence ---------------------------------------------------------

  Future<Map<String, dynamic>> _authConfig() async {
    final data = await _controller(
      'GET',
      '/passport/v1/public/authConfig',
      tag: 'authConfig',
    );
    return data;
  }

  /// The CAS handshake. IDS is handed the CASTGC; a live one bounces straight
  /// back through the controller, an expired one answers with its login page
  /// (200), which is a distinct, reportable failure.
  ///
  /// The ticket the controller wants is not the CAS `ST` — it is the string
  /// inside `/portal/shortcut.html`'s `data` parameter, which is where the
  /// bounce ends up.
  Future<String> _casTicket() async {
    final casLogin = Uri.parse(
      '$baseUrl/passport/v1/public/casLogin',
    ).replace(queryParameters: {'sfDomain': casDomain});
    var response = await _get(casLogin, tag: 'casLogin', follow: false);
    if (response.statusCode != 302) {
      throw AtrustException(
        'casLogin',
        'expected a redirect to IDS, got ${response.statusCode}',
      );
    }
    var target = _location(response);
    final header = _cookieHeader({'CASTGC'});
    for (var hop = 0; hop < _maxRedirects; hop++) {
      response = await _get(
        target,
        tag: 'cas hop',
        follow: false,
        cookieHeader: header,
      );
      _absorbCookies(response);
      if (response.statusCode != 302) {
        throw AtrustException(
          'casTicket',
          'CAS stopped at ${response.statusCode} '
              '(${target.host}${target.path}) — the campus session is expired or '
              'IDS is asking for credentials',
        );
      }
      target = _location(response);
      final ticket = _casTicketFrom(target);
      if (ticket != null) return ticket;
    }
    throw const AtrustException('casTicket', 'too many CAS redirects');
  }

  /// The controller's ticket, taken out of the shortcut hop's `data` parameter.
  static String? _casTicketFrom(Uri url) {
    if (!url.path.contains('/portal/shortcut.html')) return null;
    final raw = url.queryParameters['data'];
    if (raw == null || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final ticket = decoded['ticket'];
    return ticket is String && ticket.isNotEmpty ? ticket : null;
  }

  Future<void> _reportEnv(
    String casTicket,
    String deviceId,
    Map<String, dynamic> config,
    String csrf,
    String encryptedChallenge,
  ) async {
    final antiMitm = (config['antiMITMAttackData'] as Map?) ?? const {};
    final desktop = clientType == AtrustClientType.desktop;
    await _controller(
      'POST',
      '/controller/v1/public/reportEnv',
      csrf: csrf,
      tag: 'reportEnv',
      body: {
        'ticket': casTicket,
        'timing': 'pre-login',
        'env': {
          'endpoint': {
            'device_id': deviceId,
            'device': {'type': 'browser'},
          },
        },
        'antiMITMAttackData': {
          'enable': desktop ? 1 : 0,
          'devicePubKeyMod': antiMitm['devicePubKeyMod'] ?? '',
          'devicePubKeyExp': antiMitm['devicePubKeyExp'] ?? '10001',
          'rsaCert': antiMitm['rsaCert'] ?? '',
          if (desktop) 'encryptedChallenge': encryptedChallenge,
        },
      },
    );
  }

  Future<bool> _authCheck(String csrf) async {
    final data = await _controller(
      'GET',
      '/passport/v1/auth/authCheck',
      csrf: csrf,
      tag: 'authCheck',
    );
    final next = data['nextService'] as String?;
    if (next != null) return next == 'auth/sms';
    final list = (data['nextServiceList'] as List?) ?? const [];
    return list.any((e) => (e as Map?)?['authType'] == 'auth/sms');
  }

  Future<String> _sendSms(String csrf) async {
    final data = await _controller(
      'POST',
      '/passport/v1/auth/sms',
      query: {'action': 'sendsms'},
      csrf: csrf,
      tag: 'sendsms',
      body: const <String, dynamic>{},
    );
    return (data['tips'] as String?) ?? '';
  }

  Future<String> _checkSms(String code, String csrf) async {
    final data = await _controller(
      'POST',
      '/passport/v1/auth/sms',
      query: {'action': 'checkcode'},
      csrf: csrf,
      tag: 'checkcode',
      body: {'code': code},
    );
    final ticket = data['sidTicket'] as String? ?? '';
    if (ticket.isEmpty) {
      throw const AtrustException('checkcode', 'response missing sidTicket');
    }
    return ticket;
  }

  /// The path a device the controller already knows takes — no SMS.
  Future<String> _ticketExchange(String csrf) async {
    final data = await _controller(
      'POST',
      '/passport/v1/public/ticketExchange',
      csrf: csrf,
      tag: 'ticketExchange',
      body: const <String, dynamic>{},
    );
    final ticket = data['sidTicket'] as String? ?? '';
    if (ticket.isEmpty) {
      throw const AtrustException(
          'ticketExchange', 'response missing sidTicket',);
    }
    return ticket;
  }

  Future<void> _sessionIdExchange(String sidTicket, String csrf) async {
    await _controller(
      'POST',
      '/passport/v1/public/sessionIdExchange',
      csrf: csrf,
      tag: 'sessionIdExchange',
      body: {'sidTicket': sidTicket},
    );
  }

  Future<Map<String, dynamic>> _onlineInfo() async {
    final data = await _controller(
      'GET',
      '/passport/v1/user/onlineInfo',
      tag: 'onlineInfo',
    );
    return {'isOnline': data['isOnline'] == true, 'username': data['username']};
  }

  /// The routing policy, exactly as the controller states it.
  Future<String> _clientResource(String csrf) async {
    final data = await _controller(
      'POST',
      '/controller/v1/user/clientResource',
      csrf: csrf,
      tag: 'clientResource',
      signed: true,
      body: {
        'resourceType': {
          'sdpPolicy': <String, dynamic>{},
          'appList': <String, dynamic>{},
          'favoriteAppList': <String, dynamic>{},
          'featureCenter': <String, dynamic>{},
          'uemSpace': {
            'params': {'action': 'login'},
          },
        },
      },
    );
    // Re-encoded, not the raw substring: the envelope's `data` is what the
    // policy means, and the core parses JSON either way.
    return jsonEncode(data);
  }

  // --- trusted terminal -----------------------------------------------------

  /// Lists the account's trusted terminals and this device's status in it.
  ///
  /// Only meaningful for a desktop session; a browser session was never able to
  /// bind, which the controller reports as `currentTrustStatus` 0.
  Future<AtrustTrustState> trustState() async {
    final data = await _controller(
      'GET',
      '/passport/v1/security/queryDevice',
      query: {'status': 'trust'},
      csrf: _session?.csrfToken ?? '',
      tag: 'queryDevice',
    );
    final devices = (data['data'] as List?) ?? const [];
    return AtrustTrustState(
      selfId: (data['selfId'] as String?) ?? '',
      currentTrustStatus: (data['currentTrustStatus'] as num?)?.toInt() ?? 0,
      enable: ((data['trustDeviceConfig'] as Map?)?['enable']) == true,
      devices: [
        for (final entry in devices)
          if (entry is Map)
            AtrustTrustedDevice(
              id: (entry['id'] as String?) ?? '',
              name: (entry['deviceName'] as String?) ?? '',
              deviceType: (entry['deviceType'] as String?) ?? '',
              online: entry['onlineStatus'] == true,
            ),
      ],
    );
  }

  /// Binds this device as a trusted terminal. The controller only accepts this
  /// from a session opened on the desktop path; afterwards it stops demanding an
  /// SMS for this device. Returns false when the controller refused (the session
  /// keeps working, it just keeps asking for codes).
  Future<bool> bindDevice() async {
    if (clientType != AtrustClientType.desktop) return false;
    return _tryBindDevice(_session?.csrfToken ?? '');
  }

  Future<bool> _tryBindDevice(String csrf) async {
    if (clientType != AtrustClientType.desktop || csrf.isEmpty) return false;
    try {
      await _controller(
        'POST',
        '/passport/v1/security/trustDevice',
        csrf: csrf,
        tag: 'trustDevice',
        body: const <String, dynamic>{},
      );
      await _trace('device bound as a trusted terminal');
      return true;
    } on AtrustException catch (error) {
      // Binding is an optimisation: a refusal must not fail the login.
      await _trace('trusted-terminal binding refused: ${error.code}');
      return false;
    }
  }

  // --- plumbing -------------------------------------------------------------

  Future<Map<String, dynamic>> _controller(
    String method,
    String path, {
    Map<String, String>? query,
    String csrf = '',
    String? tag,
    Object? body,
    bool signed = false,
  }) async {
    // The desktop path's query is kept to the shape the official client sends —
    // platform first, no `lang` — because a signature would cover it byte for
    // byte (protocol notes §10.3).
    final url = Uri.parse('$baseUrl$path').replace(
      queryParameters: clientType == AtrustClientType.desktop
          ? {'platform': platform, 'clientType': wireClientType, ...?query}
          : {
              'clientType': wireClientType,
              'platform': platform,
              'lang': lang,
              ...?query,
            },
    );
    final bodyText = body == null ? '' : jsonEncode(body);
    final headers = <String, String>{
      'Content-Type': 'application/json;charset=utf-8',
      if (csrf.isNotEmpty) 'x-csrf-token': csrf,
      if (_cookies.isNotEmpty) 'Cookie': _cookieHeader(null),
      // §10.3: a trusted request on the desktop path is signed over the exact
      // request target and the exact body bytes.
      if (signed && _signKey.isNotEmpty)
        'X-Request-Sig': AtrustCrypto.requestSignature(
          signKey: _signKey,
          pathWithQuery: url.path + (url.hasQuery ? '?${url.query}' : ''),
          body: bodyText,
        ),
    };
    final response = method == 'POST'
        ? await _http.post(
            url,
            headers: headers,
            body: bodyText.isEmpty ? null : bodyText,
            tag: tag,
          )
        : await _http.get(url, headers: headers, tag: tag);
    _absorbCookies(response);
    if (response.statusCode >= 400) {
      throw AtrustException(tag ?? path, 'HTTP ${response.statusCode}');
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw AtrustException(tag ?? path, 'response is not a JSON object');
    }
    final code = decoded['code'];
    if (code is int && code != 0) {
      throw AtrustException(
        tag ?? path,
        'controller code $code: ${decoded['message']}',
      );
    }
    final data = decoded['data'];
    if (data is Map<String, dynamic>) return data;
    if (data == null) return <String, dynamic>{};
    throw AtrustException(tag ?? path, 'unexpected data shape');
  }

  Future<http.Response> _get(
    Uri url, {
    required String tag,
    bool follow = true,
    String? cookieHeader,
  }) async {
    if (follow) {
      return _http.get(url, headers: _headers(cookieHeader), tag: tag);
    }
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll(_headers(cookieHeader));
    return _http.send(request, tag: tag);
  }

  Map<String, String> _headers(String? cookieHeader) => {
        'User-Agent': 'TechPie/1.0 (Flutter)',
        if (cookieHeader != null && cookieHeader.isNotEmpty)
          'Cookie': cookieHeader,
      };

  Uri _location(http.Response response) {
    final location =
        response.headers['location'] ?? response.headers['Location'];
    if (location == null || location.isEmpty) {
      throw const AtrustException('redirect', 'response has no Location');
    }
    return Uri.parse(location);
  }

  void _absorbCookies(http.Response response) {
    final setCookies = response.headers['set-cookie'];
    if (setCookies == null) return;
    // `package:http` joins multiple Set-Cookie headers with ',', and a cookie's
    // own Expires value also contains one — so split only where a new
    // `name=` starts.
    final entries = setCookies.split(RegExp(r',(?=\s*[A-Za-z0-9_.\-]+=)'));
    for (final entry in entries) {
      final pair = entry.split(';').first.trim();
      final eq = pair.indexOf('=');
      if (eq <= 0) continue;
      _cookies[pair.substring(0, eq).trim()] = pair.substring(eq + 1).trim();
    }
  }

  String _cookieHeader(Set<String>? only) => _cookies.entries
      .where((e) => only == null || only.contains(e.key))
      .map((e) => '${e.key}=${e.value}')
      .join('; ');

  static Map<String, String> _parseCookieHeader(String header) {
    final out = <String, String>{};
    for (final part in header.split(';')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      out[part.substring(0, eq).trim()] = part.substring(eq + 1).trim();
    }
    return out;
  }

  /// 32 uppercase hex, stable per install: the controller treats a new value as
  /// a new device, which costs the user one SMS.
  Future<String> _deviceId() async {
    final stored = await _storage.loadAtrustDeviceId();
    if (stored != null && stored.isNotEmpty) return stored;
    final random = Random.secure();
    final id = List<int>.generate(16, (_) => random.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .toUpperCase();
    await _storage.saveAtrustDeviceId(id);
    return id;
  }

  Future<void> _trace(String message) async => _onTrace?.call(message);
}

/// What a half-finished login keeps between [AtrustControlClient.login] and
/// [AtrustControlClient.submitSms] — everything except the code itself.
class _PendingLogin {
  const _PendingLogin({
    required this.deviceId,
    required this.csrf,
    required this.hint,
  });

  final String deviceId;
  final String csrf;
  final String hint;
}
