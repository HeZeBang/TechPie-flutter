import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'http_client.dart';
import 'storage_service.dart';

/// Which path the controller is asked to open the session on.
///
/// [browser] is the plain web session, but the controller re-verifies the
/// device with an SMS on every fresh login. [desktop] marks the session as
/// "client mode" — only such a session can be bound with
/// [AtrustControlClient.bindDevice], and only a trusted terminal skips the SMS
/// on later logins.
///
/// The distinction is exactly one query parameter on `reportEnv`
/// (`clientType=SDPClient`) and nothing else: the controller picks client mode
/// from that parameter alone (protocol notes §3.9), so no anti-MITM challenge
/// proof and no request signature is involved — which is also what keeps this
/// path free of the byte-exactness a signed request would demand (§10.3).
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
    final policyJson = str('policy');
    final storedDns = list('dns');
    final session = AtrustSession(
      sid: str('sid'),
      deviceId: str('device_id'),
      username: str('username'),
      baseUrl: str('base_url'),
      csrfToken: str('csrf_token'),
      cookies: cookies,
      gateways: list('gateways'),
      dns: storedDns.isEmpty
          ? AtrustControlClient._extractPolicyDns(policyJson)
          : storedDns,
      policyJson: policyJson,
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

  /// The device's row id, which is also what a removal names: `trustDevice`
  /// takes an `untrustIdList` of these (the entry's `trusDevDbId` is not used by
  /// the captured portal flow).
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
    this.config = const {},
  });

  final String selfId;

  /// The controller's verdict for *this* device: non-zero means trusted.
  final int currentTrustStatus;
  final bool enable;
  final List<AtrustTrustedDevice> devices;

  /// How many terminals of [deviceType] the account trusts, and how many the
  /// policy allows — `null` when the policy states no limit for that kind.
  ///
  /// Both numbers are the controller's own: the limits are `pcLimit` /
  /// `mobileLimit` inside `trustDeviceConfig`, and the device type on each entry
  /// is the `clientType` the session reported. So a full list is visible before
  /// a binding is attempted — which is the only reason a binding to a full list
  /// is refused at all.
  (int, int)? slotsFor(String deviceType) {
    final limit = switch (deviceType) {
      'SDPClient' => config['pcLimit'],
      'MobileClient' => config['mobileLimit'],
      _ => null,
    };
    if (limit is! num) return null;
    final used = devices.where((d) => d.deviceType == deviceType).length;
    return (used, limit.toInt());
  }

  /// `trustDeviceConfig` as the controller sent it.
  ///
  /// Only `enable` is interpreted, deliberately: a campus can put a quota or a
  /// policy in here that no public document describes, and a binding refused for
  /// a reason the app threw away is undiagnosable. Keeping the raw map means the
  /// next attempt against a reachable controller can be read rather than guessed
  /// at.
  final Map<String, dynamic> config;

  bool get isTrusted => currentTrustStatus != 0;
}

/// A control-plane failure. [code] is the step that failed (the request's tag),
/// [message] is meant for a log line (never for the user verbatim), and
/// [controllerCode] is the controller's own numeric code when the failure was
/// one — the only thing worth branching on.
class AtrustException implements Exception {
  const AtrustException(this.code, this.message, {this.controllerCode});

  final String code;
  final String message;
  final int? controllerCode;

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

  /// The controller's own name for [clientType] — the value `reportEnv` is
  /// addressed with, which is the sole thing that makes the session "client
  /// mode" and so bindable as a trusted terminal.
  String get wireClientType =>
      clientType == AtrustClientType.desktop ? 'SDPClient' : 'SDPBrowserClient';

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
    await _trace('authConfig ok');
    if (csrf.isEmpty) {
      throw const AtrustException('authConfig', 'missing security.csrfToken');
    }
    _cookies.addAll(_parseCookieHeader(castgc));

    final casTicket = await _casTicket();
    await _trace('CAS ok, ticket ${casTicket.length}B');
    await _reportEnv(casTicket, deviceId, config, csrf);
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
    final policy = await _clientResource(csrf);
    final policyDns = _extractPolicyDns(policy);
    await _trace('policy DNS: ${policyDns.join(',')}');
    final trusted = await bindDevice();
    final session = AtrustSession(
      sid: _cookies['sid'] ?? '',
      deviceId: deviceId,
      username: (info['username'] as String?) ?? '',
      baseUrl: baseUrl.toString(),
      csrfToken: csrf,
      cookies: Map<String, String>.from(_cookies),
      gateways: const [],
      dns: policyDns,
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

  /// The environment report — the one call whose `clientType` decides whether
  /// the session comes out as "client mode" (protocol notes §3.9).
  ///
  /// `antiMITMAttackData.enable` stays 0 even on the desktop path: client mode
  /// is picked from the query parameter alone, and submitting a challenge proof
  /// is what makes the controller run its anti-MITM check — a proof it cannot
  /// satisfy is answered with a passport-layer signature failure (the SDK's
  /// "检测到中间人攻击"), failing the whole login. geekTrust's working client
  /// mode sends `enable: 0` with the same public-key fields.
  Future<void> _reportEnv(
    String casTicket,
    String deviceId,
    Map<String, dynamic> config,
    String csrf,
  ) async {
    final antiMitm = (config['antiMITMAttackData'] as Map?) ?? const {};
    await _controller(
      'POST',
      '/controller/v1/public/reportEnv',
      csrf: csrf,
      tag: 'reportEnv',
      desktopPath: clientType == AtrustClientType.desktop,
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
          'enable': 0,
          'devicePubKeyMod': antiMitm['devicePubKeyMod'] ?? '',
          'devicePubKeyExp': antiMitm['devicePubKeyExp'] ?? '10001',
          'rsaCert': antiMitm['rsaCert'] ?? '',
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

  /// A repeated `sendsms` inside a code's lifetime is answered with this instead
  /// of a new text (protocol notes §11.1; geekTrust calls it `CodeSMSStillValid`).
  static const int _smsStillValid = 75500401;

  /// Asks the controller to text a code, and returns the line the UI shows while
  /// the code is typed.
  ///
  /// The controller refuses a second `sendsms` while a code is alive, because
  /// there is nothing to send: the user already holds one. That refusal is not a
  /// failure — the login continues into the code prompt, which is exactly what
  /// the retry was after.
  Future<String> _sendSms(String csrf) async {
    try {
      final data = await _controller(
        'POST',
        '/passport/v1/auth/sms',
        query: {'action': 'sendsms'},
        csrf: csrf,
        tag: 'sendsms',
        body: const <String, dynamic>{},
      );
      return (data['tips'] as String?) ?? '';
    } on AtrustException catch (error) {
      if (error.controllerCode != _smsStillValid) rethrow;
      await _trace('a code from an earlier attempt is still valid');
      return '验证码仍在有效期内，请输入上一条短信中的验证码';
    }
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
  ///
  /// Stays on the browser shape and unsigned: the notes' signed desktop variant
  /// only answers env config, and it makes the controller verify an interface
  /// signature over a body that has to match the official client byte for byte
  /// (§4.1, §10.3). The browser shape returns the full policy on a client-mode
  /// session too.
  Future<String> _clientResource(String csrf) async {
    final data = await _controller(
      'POST',
      '/controller/v1/user/clientResource',
      csrf: csrf,
      tag: 'clientResource',
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

  /// The controller places split-horizon resolvers in both legacy and V2 client
  /// options. Keep valid IPv4 entries in first-seen order; the VPN extension
  /// must receive these or names such as netinfo.shanghaitech.edu.cn cannot be
  /// resolved inside the tunnel.
  static List<String> _extractPolicyDns(String policyJson) {
    final decoded = jsonDecode(policyJson);
    if (decoded is! Map<String, dynamic>) return const [];
    final sdpPolicy = decoded['sdpPolicy'];
    if (sdpPolicy is! Map) return const [];
    final data = sdpPolicy['data'];
    if (data is! Map) return const [];
    final clientOption = data['clientOption'];
    if (clientOption is! Map) return const [];

    final result = <String>[];
    for (final optionName in const ['dnsOption', 'dnsOptionV2']) {
      final option = clientOption[optionName];
      if (option is! Map) continue;
      for (final key in const ['firstDNS', 'secondDNS']) {
        final value = option[key];
        if (value is String && _isIpv4(value) && !result.contains(value)) {
          result.add(value);
        }
      }
    }
    return result;
  }

  static bool _isIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((part) {
      final number = int.tryParse(part);
      return number != null && number >= 0 && number <= 255;
    });
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
      config: {
        if (data['trustDeviceConfig'] case final Map<dynamic, dynamic> config)
          for (final entry in config.entries) '${entry.key}': entry.value,
      },
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

  /// Records the controller's verdict on this device.
  ///
  /// Without it a successful binding leaves the stored session saying
  /// "untrusted", and the app keeps asking for a code it no longer needs.
  Future<void> _recordTrusted() async {
    final session = _session;
    if (session == null || session.trusted) return;
    final stored = Map<String, dynamic>.from(session.toJson())..['trusted'] = true;
    final updated = AtrustSession.fromJson(stored);
    if (updated == null) return;
    _session = updated;
    await _storage.saveAtrustSession(jsonEncode(stored));
  }

  /// Removes terminals from the account's trusted list, by the ids [trustState]
  /// reports for them.
  ///
  /// The endpoint is `trustDevice` again — the *same* call that binds — with
  /// `untrustIdList` instead of `idList` (captured from the campus portal: the
  /// `/security/untrustDevice` path and its `idList` are the reference client's
  /// invention, and this controller answers it `75510008 授信记录未找到` for
  /// every id its own list hands out). The id is the device's row id, exactly
  /// what [AtrustTrustedDevice.id] carries.
  ///
  /// The list has a limit, so removing a terminal is how a device that no longer
  /// belongs — or a new one that cannot fit — makes room.
  Future<void> untrustDevices(List<String> deviceIds) async {
    if (deviceIds.isEmpty) {
      throw const AtrustException('trustDevice', 'untrustIdList must not be empty');
    }
    await _controller(
      'POST',
      '/passport/v1/security/trustDevice',
      csrf: _session?.csrfToken ?? '',
      tag: 'untrustDevice',
      body: {'untrustIdList': deviceIds},
    );
  }

  /// Ends another terminal's session on the account, leaving it on the list.
  Future<void> logoutDevice(String id) async {
    if (id.isEmpty) {
      throw const AtrustException('logoutDevice', 'id must not be empty');
    }
    await _controller(
      'POST',
      '/passport/v1/security/logoutDevice',
      csrf: _session?.csrfToken ?? '',
      tag: 'logoutDevice',
      body: {'id': id},
    );
  }


  /// Binds this device as a trusted terminal.
  ///
  /// The controller is addressed with the `idList` of *this device's own row* —
  /// the `selfId` its `queryDevice` reports — which is what the campus portal
  /// sends (captured). An empty body names no device to bind.
  Future<bool> bindDevice() async {
    if (clientType != AtrustClientType.desktop) return false;
    try {
      final state = await trustState();
      if (state.selfId.isEmpty) {
        throw const AtrustException(
          'trustDevice',
          'the controller reported no selfId to bind',
        );
      }
      await _controller(
        'POST',
        '/passport/v1/security/trustDevice',
        csrf: _session?.csrfToken ?? '',
        tag: 'trustDevice',
        body: {
          'idList': [state.selfId],
        },
      );
      await _recordTrusted();
      await _trace('device bound as a trusted terminal');
      return true;
    } on AtrustException catch (error) {
      // Binding is an optimisation: a refusal must not fail the login. The
      // controller's own code is what says why, and the caller can act on two of
      // them: 75500311 is a full list of trusted terminals for this kind of
      // device (remove one), and 73700001 is the policy's `enhanceAuthType`
      // demanding a verified session — which the login flow has, having just
      // taken an SMS code, and a restored session has not.
      _lastBindRefusal = error.controllerCode;
      await _trace(
        'trusted-terminal binding refused: code=${error.controllerCode} '
        'detail=${error.message}',
      );
      return false;
    }
  }

  /// The controller's code from the last refused binding, or null when the last
  /// one was accepted (or never attempted).
  int? get lastBindRefusal => _lastBindRefusal;
  int? _lastBindRefusal;

  // --- plumbing -------------------------------------------------------------

  Future<Map<String, dynamic>> _controller(
    String method,
    String path, {
    Map<String, String>? query,
    String csrf = '',
    String? tag,
    Object? body,
    bool desktopPath = false,
  }) async {
    // `desktopPath` is set by `reportEnv` alone: it is the one call whose
    // `clientType` the controller reads to decide client mode (protocol notes
    // §3.9). Every other call is the browser path.
    //
    // `platform` and `lang` are sent on every call, exactly as the working
    // reference client sends them. The platform-first, no-`lang` shape §10.3
    // describes is a requirement for a *signed* request, and nothing here is
    // signed any more — keeping the deviation for no reason is how a controller
    // ends up refusing a request the reference gets accepted.
    final url = Uri.parse('$baseUrl$path').replace(
      queryParameters: {
        'clientType': desktopPath ? wireClientType : 'SDPBrowserClient',
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
    };
    final response = await _bounded(
      tag ?? path,
      method == 'POST'
          ? _http.post(
              url,
              headers: headers,
              body: bodyText.isEmpty ? null : bodyText,
              tag: tag,
            )
          : _http.get(url, headers: headers, tag: tag),
    );
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
        controllerCode: code,
      );
    }
    final data = decoded['data'];
    if (data is Map<String, dynamic>) return data;
    if (data == null) return <String, dynamic>{};
    throw AtrustException(tag ?? path, 'unexpected data shape');
  }

  /// How long one control-plane request is given.
  ///
  /// Every name here is a campus one, and a campus route that goes nowhere — an
  /// interface whose engine is gone, which the platform can leave behind — does
  /// not refuse the connection, it swallows it. Without this bound the CAS hop of
  /// a login sits there for good, which is what "正在恢复校园会话…" forever was.
  static const _requestTimeout = Duration(seconds: 15);

  /// Runs [request] under [_requestTimeout], in the vocabulary the rest of this
  /// class uses, so every caller's existing handling applies.
  Future<http.Response> _bounded(
    String tag,
    Future<http.Response> request,
  ) async {
    try {
      return await request.timeout(_requestTimeout);
    } on TimeoutException {
      throw AtrustException(tag, '请求超时（校园路由可能不可达）');
    }
  }

  Future<http.Response> _get(
    Uri url, {
    required String tag,
    bool follow = true,
    String? cookieHeader,
  }) async {
    if (follow) {
      return _bounded(
        tag,
        _http.get(url, headers: _headers(cookieHeader), tag: tag),
      );
    }
    final request = http.Request('GET', url)
      ..followRedirects = false
      ..headers.addAll(_headers(cookieHeader));
    return _bounded(tag, _http.send(request, tag: tag));
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
