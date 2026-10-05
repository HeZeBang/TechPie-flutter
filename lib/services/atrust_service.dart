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

  /// Whether the last attempt to raise the tunnel ended without it coming up.
  /// Only then does "retry" mean anything: a tunnel that is up needs no retry,
  /// and one that was never started needs a start, not a retry.
  bool _tunnelFailed = false;

  /// Whether a stop is waiting on the platform to release the interface. The
  /// system's own disconnect finishes it — see [refreshSystemVpn] — because that
  /// revoke is the only thing that releases an interface here.
  bool _stopPending = false;

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

  /// Whether the system interface is up right now.
  bool get systemVpnActive => _systemVpnActive;

  /// Whether the last tunnel start ended without the engine coming up.
  bool get tunnelFailed => _tunnelFailed;

  /// The tunnel's local listener addresses (`host:port`; empty = that listener
  /// is off). The desktop shape, and what geektrust's own config carries.
  String get socksProxy => AtrustRouting.socksProxy;
  String get httpProxy => AtrustRouting.httpProxy;

  /// Reads the listener addresses from storage, so the page shows — and the
  /// engine binds — what was last chosen.
  Future<void> hydrateProxies() async {
    final socks = await _storage.loadAtrustSocksProxy();
    final http = await _storage.loadAtrustHttpProxy();
    AtrustRouting.socksProxy = socks ?? AtrustRouting.socksProxy;
    AtrustRouting.httpProxy = http ?? AtrustRouting.httpProxy;
  }

  /// Reads the platform's verdict on the interface into [systemVpnActive].
  ///
  /// Asked rather than remembered: the system's own VPN entry can disconnect the
  /// interface without the app, and that is the only lever that releases it. A
  /// stop that was waiting on the platform finishes here, once the interface is
  /// really gone.
  Future<void> refreshSystemVpn() async {
    if (!systemVpnSupported) return;
    final active = await _vpn.active();
    final wasActive = _systemVpnActive;
    _systemVpnActive = active;
    if (!active && _stopPending) {
      _stopPending = false;
      tunnel.stop();
      _tunnelFailed = false;
      refreshTunnelStatus();
      _detail = '系统 VPN 已关闭，隧道已停止';
    } else if (active != wasActive) {
      _detail = active ? '系统 VPN：全局模式' : '系统 VPN 已关闭';
    } else {
      return;
    }
    notifyListeners();
  }

  /// Sets the listener addresses. They are applied when the tunnel next starts:
  /// the engine binds each listener once, at start, and rebinding a live one is
  /// not something it does.
  Future<void> setProxies({required String socks, required String http}) async {
    AtrustRouting.socksProxy = socks.trim();
    AtrustRouting.httpProxy = http.trim();
    await _storage.saveAtrustProxies(
      socks: AtrustRouting.socksProxy,
      http: AtrustRouting.httpProxy,
    );
    _detail = '端口已保存，下次启动隧道生效';
    notifyListeners();
  }

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
    _detail = '正在登录 VPN 账号…';
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
      _detail = '请先登录 VPN 账号';
      notifyListeners();
      return false;
    }
    _error = null;
    try {
      tunnel.start(
        sessionJson: _sessionJson(session),
        policyJson: session.policyJson,
      );
      // The desktop shape: the engine's local listeners, the addresses from the
      // page (geektrust's own default ports until one is chosen).
      tunnel.startProxies(
        socksAddress: AtrustRouting.socksProxy,
        httpAddress: AtrustRouting.httpProxy,
      );
    } on Object catch (error) {
      _detail = '隧道启动失败';
      _error = '$error';
      _tunnelFailed = true;
      refreshTunnelStatus();
      notifyListeners();
      return false;
    }
    final alive = await _waitForAlive();
    refreshTunnelStatus();
    _tunnelFailed = !alive;
    if (alive) {
      _detail = '隧道已连接';
    } else {
      _detail = '隧道正在连接';
      _error = '引擎未在 20 秒内报告在线'
          '（已拨号 ${_tunnelDialAttempts()} 次）';
    }
    notifyListeners();
    if (alive && systemVpnSupported) {
      // The mobile shape: the whole device comes up with the tunnel, one action.
      // There is no separate switch for it, because a system interface that has
      // to be *asked for* separately is one the app cannot reliably take back —
      // the platform binds the service for as long as the interface exists (see
      // AtrustVpnService).
      await startSystemVpn();
    }
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

  /// Forgets the session, and takes the packet layers down as far as the platform
  /// allows.
  ///
  /// The interface is stopped first and the result is *checked*: where the
  /// platform refuses to release it (see [AtrustVpnService.stop]) the engine is
  /// deliberately left running. An interface whose routes outlive its engine is
  /// worse than a tunnel that stays up — every campus destination, the controller
  /// and the CAS host included, is then dropped into a descriptor nobody reads,
  /// and the next login hangs on the way there.
  Future<void> signOut() async {
    final released = await _releaseSystemVpn();
    AtrustRouting.enabled = false;
    if (released) {
      tunnel.stop();
      _stopPending = false;
    } else {
      // The platform will not let the interface go, and it must not be left
      // without an engine: that is the black hole that made the next login hang.
      // Signing out keeps the tunnel until the interface is really gone, which
      // the system's own disconnect can do — [refreshSystemVpn] finishes it.
      _stopPending = true;
    }
    await _control.logout();
    _client = null;
    _login = null;
    _trust = null;
    _tunnelStatus = null;
    _tunnelFailed = false;
    _detail = released
        ? '已登出'
        : '已登出；系统 VPN 未释放';
    notifyListeners();
  }

  /// Stops the system interface when there is one, and answers whether the
  /// platform let it go. Platforms without such an interface have nothing to
  /// release, so they answer yes.
  Future<bool> _releaseSystemVpn() async {
    if (!systemVpnSupported || !_systemVpnActive) return true;
    await stopSystemVpn();
    return !_systemVpnActive;
  }

  /// Keeps the account session but stops the packet layers — as far as the
  /// platform allows.
  ///
  /// The interface goes first, and only if it really went does the engine stop:
  /// an interface whose routes outlive its engine drops every campus destination
  /// into a descriptor nobody reads (see [signOut]). Where the platform refuses
  /// to release it, that refusal is what the status line says.
  Future<void> stopTunnel() async {
    final released = await _releaseSystemVpn();
    AtrustRouting.enabled = false;
    if (released) {
      _stopPending = false;
      tunnel.stop();
      _tunnelFailed = false;
      refreshTunnelStatus();
      _detail = '隧道已停止（会话保留）';
    } else {
      // The interface is still carrying traffic, so the engine stays: one whose
      // routes outlive its engine drops every campus destination into a
      // descriptor nobody reads. The ask is kept, and the system's own
      // disconnect completes it ([refreshSystemVpn]).
      _stopPending = true;
      _detail = '系统 VPN 未释放，隧道保留';
    }
    notifyListeners();
  }

  /// Which campus hosts the app's own requests send through the tunnel.
  void setRouting(bool enabled) {
    AtrustRouting.enabled = enabled;
    _detail = enabled ? '仅校园网段代理' : '校园网段直连';
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
      _detail = bound ? '已授信：以后不再要短信' : _refusalReason();
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

  /// The system interface's shape: an interface the whole device routes through,
  /// which is what reaches the campus from WebViews and from other apps. Mobile
  /// raises it with the tunnel; the desktops have no such interface and use the
  /// local listeners instead.
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

  /// Takes the interface down and leaves the tunnel it sits above running.
  ///
  /// The platform does not always let go — see [AtrustVpnService.stop] — so the
  /// verdict is what the status line reports rather than what was asked for.
  Future<void> stopSystemVpn() async {
    try {
      final released = await _vpn.stop();
      _systemVpnActive = !released;
      _detail = released ? '系统 VPN 已关闭' : '系统 VPN 未释放';
    } on Object catch (error) {
      _error = '$error';
      _detail = '系统 VPN 未能关闭';
    }
    refreshTunnelStatus();
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
