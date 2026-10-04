import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../utils/platform.dart';
import 'atrust_control_client.dart';
import 'atrust_routing.dart';
import 'atrust_tunnel_service.dart';
import 'atrust_vpn_service.dart';
import 'http_client.dart';
import 'storage_service.dart';

/// The campus tunnel as one thing the app owns.
///
/// Three parts make it up — the control plane (login, SMS, session), the packet
/// path (the pinned core library) and the platform shell (a system VPN where
/// there is one) — and they used to be wired by hand wherever they were needed.
/// That is fine for one panel and wrong for a feature: two owners in one process
/// would each hold their own engine and their own session, and the second
/// `geektrust_init` silently replaces the first one's tunnel. This is the single
/// owner, and both the feature page and the developer lab drive it.
///
/// It is deliberately thin: every decision it makes is one of the calls below,
/// and nothing here reads a cookie or touches a policy itself.
class AtrustService extends ChangeNotifier {
  AtrustService({
    required LoggingHttpClient http,
    required StorageService storage,
    required String Function() castgc,
    AtrustTunnelService? tunnel,
    AtrustVpnService? vpn,
  })  : _http = http,
        _storage = storage,
        _castgc = castgc,
        _tunnel = tunnel,
        _vpn = vpn ?? AtrustVpnService();

  final LoggingHttpClient _http;
  final StorageService _storage;
  final String Function() _castgc;
  AtrustTunnelService? _tunnel;
  final AtrustVpnService _vpn;

  /// Loading the native library is deferred until the feature is opened or a
  /// tunnel operation is requested. This service is constructed on the
  /// boot-critical path; `DynamicLibrary.open` and ABI inspection must not hold
  /// the splash screen.
  AtrustTunnelService get tunnel => _tunnel ??= AtrustTunnelService.load();

  AtrustClientType _clientType = AtrustClientType.desktop;
  AtrustControlClient? _client;
  AtrustLoginState? _login;
  AtrustTunnelStatus? _tunnelStatus;
  AtrustTrustState? _trust;
  String _detail = '';
  String? _error;
  bool _busy = false;
  bool _systemVpnActive = false;

  AtrustVpnService get vpn => _vpn;

  /// The last login outcome, or null before the first attempt.
  AtrustLoginState? get login => _login;

  /// The live session, when there is one.
  AtrustSession? get session => _client?.session;

  /// The engine's own view of the tunnel.
  AtrustTunnelStatus? get tunnelStatus => _tunnelStatus;

  /// The account's trusted-terminal state, when it has been asked for.
  AtrustTrustState? get trust => _trust;

  /// A short line for the UI: what just happened, or why it did not.
  String get detail => _detail;

  /// The last failure in its own words, or null when the last attempt worked.
  ///
  /// The status line says *what* happened; this is the detail behind it, and it
  /// belongs behind a button rather than in the middle of the card.
  String? get error => _error;

  /// True while a long call is in flight, so a second tap cannot start a second
  /// one over the first one's session.
  bool get busy => _busy;
  bool get routingEnabled => AtrustRouting.enabled;

  bool get tunnelSupported => tunnel.isSupported;
  String get tunnelVersion => tunnel.version;
  String get tunnelUnsupportedReason => tunnel.unsupportedReason;

  /// Which path the *session* is opened on. Client mode is the only kind that
  /// can be bound as a trusted terminal, and so the only kind that ever stops
  /// asking for an SMS — the alternative exists to prove that by contrast.
  AtrustClientType get clientType => _clientType;

  set clientType(AtrustClientType value) {
    if (value == _clientType) return;
    _clientType = value;
    // The session was opened on the other path; a client is per-path.
    _client = null;
    _login = null;
    _trust = null;
    _detail = value == AtrustClientType.desktop
        ? '客户端模式：可绑定授信终端'
        : '浏览器模式：每次都需短信';
    notifyListeners();
  }

  AtrustControlClient get _control => _client ??= AtrustControlClient(
        http: _http,
        storage: _storage,
        castgc: _castgc,
        clientType: _clientType,
        onTrace: (stage) async => debugPrint('[atrust] $stage'),
      );

  /// Opens the controller session only. The packet engine is a separate action.
  Future<AtrustLoginState> signIn() async {
    if (_busy) return _login ?? const AtrustLoginState(AtrustStage.unavailable);
    _busy = true;
    _detail = '正在登录校园账号…';
    _error = null;
    notifyListeners();
    try {
      final state = await _control.login();
      _login = state;
      // Being logged in is what makes the trusted-terminal list answerable, and
      // it is worth answering: it is the difference between "an SMS every time"
      // and "no SMS".
      if (state.isOnline) await refreshTrust();
      _detail = state.stage == AtrustStage.needSms
          ? '验证码已发送，请输入短信验证码'
          : '账号已登录';
      return state;
    } on Object catch (error) {
      _login = null;
      _detail = '登录失败';
      _error = '$error';
      return const AtrustLoginState(AtrustStage.unavailable);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Finishes controller authentication only. The packet engine remains off
  /// until the user presses the separate tunnel action.
  Future<AtrustLoginState> submitSms(String code) async {
    if (_busy) return _login ?? const AtrustLoginState(AtrustStage.unavailable);
    _busy = true;
    notifyListeners();
    _error = null;
    try {
      final state = await _control.submitSms(code);
      _login = state;
      if (state.isOnline) await refreshTrust();
      _detail = '账号已登录';
      return state;
    } on Object catch (error) {
      _login = null;
      _detail = '验证码校验失败';
      _error = '$error';
      return const AtrustLoginState(AtrustStage.unavailable);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Starts only the local packet engine and its SOCKS listeners.
  ///
  /// The engine refuses in its own words — a missing library, an ABI it cannot
  /// speak, a gateway that will not answer — and all of them are reported here
  /// rather than thrown at a button.
  Future<bool> startTunnel() async {
    final session = _control.session;
    if (session == null) {
      _detail = '请先登录校园账号';
      notifyListeners();
      return false;
    }
    _error = null;
    try {
      tunnel.start(
        sessionJson: _sessionJson(session),
        policyJson: session.policyJson,
      );
      tunnel.startProxies(socksAddress: AtrustRouting.socksProxy);
    } on Object catch (error) {
      _detail = '隧道启动失败';
      _error = '$error';
      refreshTunnelStatus();
      notifyListeners();
      return false;
    }
    final alive = await _waitForAlive();
    refreshTunnelStatus();
    if (alive) {
      _detail = '隧道已连接';
    } else {
      _detail = '隧道正在连接';
      _error = '引擎未在 20 秒内报告在线'
          '（已拨号 ${_tunnelDialAttempts()} 次）';
    }
    notifyListeners();
    return alive;
  }

  int _tunnelDialAttempts() {
    try {
      return tunnel.status().dialAttempts;
    } on Object {
      return 0;
    }
  }


  Future<bool> _waitForAlive() async {
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (DateTime.now().isBefore(deadline)) {
      try {
        if (tunnel.status().alive) return true;
      } on Object {
        // The next snapshot is the useful one while the engine is starting.
      }
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return false;
  }

  /// Takes the tunnel (and the system interface, if it is up) down and forgets
  /// the session locally. The controller's session expires on its own.
  Future<void> signOut() async {
    await stopSystemVpn();
    AtrustRouting.enabled = false;
    tunnel.stop();
    await _control.logout();
    _client = null;
    _login = null;
    _trust = null;
    _tunnelStatus = null;
    _detail = '已登出';
    notifyListeners();
  }

  /// Keeps the account session but stops both packet layers. The system VPN is
  /// stopped first; leaving a global interface above a dead engine black-holes
  /// campus traffic.
  Future<void> stopTunnel() async {
    if (_systemVpnActive) await stopSystemVpn();
    AtrustRouting.enabled = false;
    tunnel.stop();
    refreshTunnelStatus();
    _detail = '隧道已停止（会话保留）';
    notifyListeners();
  }

  /// Which campus hosts the app's own requests send through the tunnel.
  void setRouting(bool enabled) {
    AtrustRouting.enabled = enabled;
    _detail = enabled ? '校园请求走隧道' : '校园请求直连';
    notifyListeners();
  }

  /// Asks the controller to remember this device, so later full logins skip the
  /// SMS. Only a client-mode session may be bound; a refusal is reported, not
  /// hidden — it is the difference between paying for a code or not.
  ///
  /// Like every other command here, an unreachable controller is an outcome to
  /// report, not an exception to throw at a button.
  Future<bool> bindTrustedTerminal() async {
    _error = null;
    try {
      final bound = await _control.bindDevice();
      await refreshTrust();
      _detail = bound ? '本机已授信：以后不再要短信' : _refusalReason();
      notifyListeners();
      return bound;
    } on Object catch (error) {
      _detail = '绑定失败';
      _error = '$error';
      notifyListeners();
      return false;
    }
  }

  /// How many terminals of this session's kind the account trusts, out of the
  /// limit the policy states — `null` when the policy does not state one.
  (int, int)? get trustSlots => _trust?.slotsFor(_control.wireClientType);

  /// Why the controller refused a binding, in the account's own numbers.
  ///
  /// Two refusals are actionable, and they are the two the campus's own policy
  /// and portal show:
  ///
  /// * `75500311` — the list of trusted terminals for this kind of device is
  ///   full. The policy states the limits (`pcLimit` / `mobileLimit` in
  ///   `trustDeviceConfig`) and the controller lists what is there, so the count
  ///   is named; a captured campus-portal session was refused with this very code
  ///   while its three PC slots were taken, and its binding went through
  ///   unchanged once it had removed devices.
  /// * `73700001` — the policy's `enhanceAuthType` (`auth/sms/https`) wants a
  ///   verified session for this action. The portal had one because it had just
  ///   logged in with an SMS code; a *restored* session has not, which is why the
  ///   login flow's own binding (right after the code) is the one that works.
  ///
  /// Anything else stays uninterpreted rather than guessed at.
  String _refusalReason() {
    if (_control.lastBindRefusal == 73700001) {
      return '绑定被拒：需要短信验证，重新登录（输码）会自动绑定';
    }
    if (trustSlots case (final used, final limit) when used >= limit) {
      return '绑定被拒：授信位已满（$used/$limit），先解除一台再试';
    }
    return '绑定被拒：本机只能继续用短信';
  }

  /// Removes a terminal from the account's trusted list, named by the device id
  /// [trustState] reports for it.
  ///
  /// This is the lever a user has when the list is full: the campus caps how many
  /// terminals of each kind may be trusted, and a device that cannot fit has to
  /// displace one. The list itself comes from [trust] (`queryDevice`).
  Future<bool> untrustDevice(String deviceId) async {
    if (deviceId.isEmpty) return false;
    _error = null;
    try {
      await _control.untrustDevices([deviceId]);
      _detail = '已解除授信';
      await refreshTrust();
      notifyListeners();
      return true;
    } on Object catch (error) {
      _detail = '解除授信失败';
      _error = '$error';
      notifyListeners();
      return false;
    }
  }

  /// Ends another terminal's session, leaving it on the trusted list.
  Future<bool> logoutDevice(String id) async {
    if (id.isEmpty) return false;
    _error = null;
    try {
      await _control.logoutDevice(id);
      _detail = '已注销该终端';
      await refreshTrust();
      notifyListeners();
      return true;
    } on Object catch (error) {
      _detail = '注销终端失败';
      _error = '$error';
      notifyListeners();
      return false;
    }
  }

  Future<AtrustTrustState?> refreshTrust() async {
    // The list needs a live session; without one there is nothing to ask, and a
    // missing answer is not a failure.
    if (_control.session == null) {
      _trust = null;
      notifyListeners();
      return null;
    }
    try {
      _trust = await _control.trustState();
      _error = null;
    } on Object catch (error) {
      // Needs a reachable controller: when it is not, "未知" has a reason, and
      // the status card offers it behind ⓘ rather than guessing.
      _trust = null;
      _error = '授信状态查询失败：$error';
    }
    notifyListeners();
    return _trust;
  }

  /// Re-reads the engine's snapshot. The ABI calls it cheap and meant to be
  /// polled, which is what lets the UI show the tunnel coming up on its own.
  void refreshTunnelStatus() {
    if (!tunnel.isSupported) {
      _tunnelStatus = null;
      return;
    }
    try {
      _tunnelStatus = tunnel.status();
    } on Object {
      _tunnelStatus = null;
    }
  }

  /// The system-VPN shape, where the platform has one: an interface the whole
  /// device routes through, which is what reaches the campus from WebViews and
  /// from other apps.
  Future<String> startSystemVpn() async {
    var session = _control.session;
    if (session == null) {
      final restored = await restore();
      if (!restored.isOnline || _control.session == null) {
        return 'failed: 先登录，系统 VPN 需要一份会话';
      }
      session = _control.session!;
    }
    if (!(tunnelStatus?.alive ?? false)) {
      final alive = await startTunnel();
      if (!alive) return 'failed: 隧道未连接';
    }
    try {
      final verdict = await _vpn.start(session, engine: tunnel);
      _systemVpnActive = verdict == 'active';
      refreshTunnelStatus();
      _detail = '系统 VPN：$verdict';
      if (verdict != 'active') _error = '系统 VPN 未能建立：$verdict';
      notifyListeners();
      return verdict;
    } on Object catch (error) {
      _detail = '系统 VPN 启动失败';
      _error = '$error';
      notifyListeners();
      return 'failed: $error';
    }
  }

  Future<void> stopSystemVpn() async {
    try {
      await _vpn.stop(engine: tunnel);
    } on Object catch (error) {
      _error = '$error';
    }
    _systemVpnActive = false;
    refreshTunnelStatus();
    _detail = '系统 VPN 已关闭，会话保留，隧道已停止';
    notifyListeners();
  }

  /// Restores only the controller session. It never starts the packet engine.
  ///
  /// A controller that cannot be reached is reported, not thrown: the campus
  /// name is not answered for on every network, and the caller is a button.
  Future<AtrustLoginState> restore() async {
    _busy = true;
    _detail = '正在恢复校园会话…';
    _error = null;
    notifyListeners();
    try {
      final state = await _control.ensureOnline();
      if (state.isOnline) {
        _detail = '账号已恢复';
        await refreshTrust();
      } else if (state.stage == AtrustStage.needSms) {
        _detail = '验证码已发送，请输入短信验证码';
      } else {
        _detail = state.hint.isEmpty ? '未登录' : state.hint;
      }
      _login = state;
      return state;
    } on Object catch (error) {
      // A controller this network cannot reach is an ordinary outcome, not a
      // crash: the campus name is not answered for everywhere, and a dead link
      // fails the lookup outright. A caller here is a button, and an unhandled
      // failure would leave it with nothing to say.
      _detail = '无法连接校园控制器';
      _error = '$error';
      _login = null;
      return const AtrustLoginState(AtrustStage.unavailable);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Whether this platform can raise a whole-device interface at all.
  bool get systemVpnSupported => _vpn.isSupported && (isAndroid() || isOhos());

  /// Whether that interface is up right now.
  bool get systemVpnActive => _systemVpnActive;

  String _sessionJson(AtrustSession session) => jsonEncode({
        'sid': session.sid,
        'device_id': session.deviceId,
        'username': session.username,
        'base_url': session.baseUrl,
        'gateways': session.gateways,
        'dns': session.dns,
      });

  @override
  void dispose() {
    _tunnel?.stop();
    super.dispose();
  }
}

/// The campus destinations the probe walks, literal on purpose: a name would
/// make a DNS failure look like a tunnel failure.
const atrustCampusTargets = <String>[
  'https://netinfo.shanghaitech.edu.cn/',
  'http://10.15.89.181/',
];

/// A plain reachability probe, reported with what a failure actually was.
Future<String> probeCampusTarget(String target) async {
  final uri = Uri.parse(target);
  final stopwatch = Stopwatch()..start();
  final resolved = <String>[];
  try {
    final addresses =
        await InternetAddress.lookup(uri.host).timeout(const Duration(seconds: 8));
    resolved.addAll(addresses.map((address) => address.address));
  } on Object catch (error) {
    resolved.add('解析失败($error)');
  }
  final refused = <String>[];
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 10)
    ..findProxy = ((uri) => 'DIRECT')
    ..badCertificateCallback = (certificate, host, port) {
      refused.add('$host:$port ${certificate.subject} / ${certificate.issuer}');
      return true;
    };
  String tail() =>
      ' · ${uri.host} → ${resolved.join(', ')}'
      '${refused.isEmpty ? '' : ' · 拒绝了证书：${refused.join('; ')}'}';
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 12));
    final response = await request.close().timeout(const Duration(seconds: 12));
    final body = await response
        .fold<int>(0, (sum, chunk) => sum + chunk.length)
        .timeout(const Duration(seconds: 12));
    final peer = response.connectionInfo;
    return '$target → HTTP ${response.statusCode}, $body B'
        '${peer == null ? '' : ', ${peer.remoteAddress.address}:${peer.remotePort}'}'
        ', ${stopwatch.elapsedMilliseconds} ms${tail()}';
  } on Object catch (error) {
    return '$target → ${error.runtimeType}: $error '
        '(${stopwatch.elapsedMilliseconds} ms)${tail()}';
  } finally {
    client.close(force: true);
  }
}
