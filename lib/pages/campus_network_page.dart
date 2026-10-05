import 'dart:async';

import 'package:flutter/material.dart';

import '../services/atrust_control_client.dart';
import '../services/atrust_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

/// The campus network, as a feature rather than a lab experiment.
///
/// The campus systems the app talks to — the eGate pages, the schedule, the
/// Blackboard deadlines — are only reachable from inside the campus network.
/// This is what puts the device inside it from anywhere else: it signs in to the
/// aTrust controller, brings the tunnel up, and says plainly what state it is
/// in. The account side is the eGate binding; nothing here asks for a password.
class CampusNetworkPage extends StatefulWidget {
  const CampusNetworkPage({super.key});

  @override
  State<CampusNetworkPage> createState() => _CampusNetworkPageState();
}

class _CampusNetworkPageState extends State<CampusNetworkPage> {
  /// The engine dials the gateway in the background, so the status line only
  /// tells the truth while someone keeps asking. The ABI calls the snapshot
  /// cheap and meant to be polled.
  Timer? _poll;

  bool _probing = false;
  String _probeResult = '';

  /// Whether the list has been asked for since the tunnel came up.
  bool _trustAsked = false;

  AtrustService get _service => ServiceProvider.of(context).atrustService;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(_refresh);
    });
    // The trusted-terminal list is answerable as soon as there is a session, so
    // ask on open rather than only right after a login.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_service.refreshSystemVpn());
      if (_service.session != null) {
        unawaited(_service.refreshTrust());
      }
    });
  }

  /// One poll tick: re-read the engine, and ask for the trusted-terminal list
  /// once per connection while it is still unknown. Reachability is what that
  /// query needs, and a tunnel that is up is the proof that a controller is
  /// reachable — which is exactly what was missing when it last failed.
  void _refresh() {
    final service = _service;
    service.refreshTunnelStatus();
    // The platform's own disconnect happens outside the app — in the system's
    // VPN entry — so its verdict is re-read, slowly: it is a channel call, and
    // the state it reports changes at human speed.
    if (service.systemVpnSupported && ++_ticks % 5 == 0) {
      unawaited(service.refreshSystemVpn());
    }
    final alive = service.tunnelStatus?.alive == true;
    if (!alive) {
      _trustAsked = false;
    } else if (!_trustAsked && service.session != null && service.trust == null) {
      _trustAsked = true;
      unawaited(service.refreshTrust());
    }
  }

  /// Poll ticks since the page was opened, for the slow platform re-read.
  int _ticks = 0;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = _service;
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      // The list scrolls behind the bar, which is what the bar's blur is for.
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '校园网 VPN',
              leadingItems: [
                if (Navigator.canPop(context))
                  const IosNativeNavigationBarItem(
                    id: 'back',
                    title: 'Home',
                    sfSymbol: 'chevron.left',
                    accessibilityLabel: '返回 Home',
                  ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(maybePopAdaptivePage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('校园网 VPN')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) => ListView(
          // The bar is not reserved twice: the list starts under it and its
          // own height is the only space taken, so the first card sits against
          // the bar and everything after it scrolls underneath.
          padding: EdgeInsets.only(
            top: topInset,
            bottom: AppShellMetrics.bottomContentPaddingOf(context),
          ),
          children: [
            _status(context, service),
            const Divider(height: 1),
            ..._actions(context, service),
            const Divider(height: 1),
            _devices(context, service),
            const Divider(height: 1),
            _diagnostics(context, service),
          ],
        ),
      ),
    );
  }

  // --- state ----------------------------------------------------------------

  Widget _status(BuildContext context, AtrustService service) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = service.session;
    final tunnel = service.tunnelStatus;
    final trust = service.trust;
    final login = service.login;
    final tunnelAlive = tunnel?.alive == true;

    final (IconData icon, String headline, Color color) = switch (session) {
      final AtrustSession _ when tunnelAlive => (
          Icons.shield_outlined,
          '校园网 VPN 已连接',
          scheme.primary,
        ),
      _ when login?.stage == AtrustStage.needSms => (
          Icons.sms_outlined,
          '等待短信验证码',
          scheme.tertiary,
        ),
      _ => (Icons.shield_outlined, '校园网 VPN 未连接', scheme.outline),
    };

    // One labelled fact per layer, so the three states read as three answers
    // instead of one sentence. The engine's counters are diagnostics and live in
    // 诊断: a cumulative dial count on the summary line says nothing about
    // whether the tunnel is up.
    final rows = <(String, String)>[
      (
        '账号',
        session == null
            ? '未登录'
            : '${session.username} · ${_trustLabel(trust, session)}',
      ),
      (
        '隧道',
        tunnelAlive
            ? (tunnel!.vip.isEmpty ? '在线' : '在线 · ${tunnel.vip}')
            : (tunnel == null ? '未运行' : '未连接'),
      ),
      if (tunnelAlive && tunnel!.gateway.isNotEmpty) ('网关', tunnel.gateway),
      if (service.systemVpnSupported)
        ('系统 VPN', service.systemVpnActive ? '全局模式' : '未启用'),
      if (service.tunnelSupported && !service.systemVpnSupported)
        ('代理端口', _proxyPortsLabel(service)),
      if (service.busy && service.detail.isNotEmpty) ('状态', service.detail),
      if (!service.tunnelSupported)
        ('隧道库', service.tunnelUnsupportedReason),
      if (session == null && !service.busy && service.detail.isNotEmpty)
        ('状态', service.detail),
    ];

    // One control for the data channel, and it says what it will do: start when
    // nothing is up, stop when it is, and *retry* only after an attempt that
    // failed — a tunnel that was never started has nothing to retry. The
    // account's own step is separate: with no session, this is the way back in.
    final ({String label, IconData actionIcon}) action = switch (
      (session, tunnelAlive, service.tunnelFailed)
    ) {
      (null, _, _) => (label: '重试登录', actionIcon: Icons.refresh),
      (_, true, _) => (label: '停止隧道', actionIcon: Icons.stop_circle_outlined),
      (_, false, true) => (label: '重试启动隧道', actionIcon: Icons.refresh),
      (_, false, false) => (
          label: '启动隧道',
          actionIcon: Icons.play_circle_outline,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        elevation: 0,
        color: scheme.surfaceContainerHigh,
        // A hairline: in the dark scheme the container colours sit too close to
        // the page to read as a card on their own.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 22, color: color),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      headline,
                      style: theme.textTheme.titleMedium?.copyWith(color: color),
                    ),
                  ),
                  if (service.error != null)
                    // The failure text is long and technical; it belongs behind
                    // a button, not in the middle of the card.
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 18),
                      visualDensity: VisualDensity.compact,
                      tooltip: '查看错误详情',
                      onPressed: () => unawaited(_showError(service.error!)),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 0, 0, 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 64,
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                      Expanded(
                        child: Text(value, style: theme.textTheme.bodyMedium),
                      ),
                    ],
                  ),
                ),
              if (!service.busy)
                Padding(
                  padding: const EdgeInsets.fromLTRB(32, 4, 0, 0),
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(_run(action.label)),
                    icon: Icon(action.actionIcon, size: 18),
                    label: Text(action.label),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The desktop's two listeners, in the shape the config has them.
  static String _proxyPortsLabel(AtrustService service) {
    final listeners = [
      if (service.socksProxy.isNotEmpty) 'SOCKS5 ${service.socksProxy}',
      if (service.httpProxy.isNotEmpty) 'HTTP ${service.httpProxy}',
    ];
    return listeners.isEmpty ? '未开启' : listeners.join(' · ');
  }

  /// What a binding would run into, said before it is attempted.
  ///
  /// The campus caps how many terminals of this kind the account may trust and
  /// states that limit itself (`pcLimit` / `mobileLimit` in the policy), so when
  /// the count already sits at it, the tile can name the step that has to come
  /// first instead of looking like a broken button.
  static String _bindHint(AtrustService service) {
    final slots = service.trustSlots;
    if (slots == null) return '之后同一台设备免短信';
    final (used, limit) = slots;
    return used >= limit
        ? '授信位已满（$used/$limit），先解除一台'
        : '之后同一台设备免短信';
  }

  /// Whether this device is a trusted terminal, said in one phrase.
  ///
  /// The controller answers `queryDevice`, and the session carries the verdict it
  /// gave at the last login. A binding that succeeded *this* session is a third
  /// fact: the controller records it for the next login and leaves the running
  /// session's own `currentTrustStatus` at 0, so believing only the live field
  /// would report "未授信" immediately after a successful bind. Whichever of the
  /// two says trusted wins.
  static String _trustLabel(AtrustTrustState? trust, AtrustSession session) =>
      switch (trust) {
        final AtrustTrustState state when !state.enable => '校园未开启授信',
        final AtrustTrustState state when state.isTrusted || session.trusted =>
          '已授信',
        final AtrustTrustState _ => '未授信（登录需短信）',
        null => session.trusted ? '已授信（上次登录）' : '未授信（上次登录）',
      };

  /// Whether offering to bind this device is worth it: the campus has to allow it
  /// and the device must not already be on the list.
  ///
  /// When the controller has not answered, the session's own record decides —
  /// the same fallback the label uses, so the row and the action can never
  /// disagree. Gating this on a live answer alone would hide the button exactly
  /// when the controller is hard to reach, which is when someone goes looking
  /// for it.
  static bool _canBind(AtrustTrustState? trust, AtrustSession session) =>
      switch (trust) {
        final AtrustTrustState state =>
          state.enable && !state.isTrusted && !session.trusted,
        null => !session.trusted,
      };

  /// The account's trusted terminals, with the one action that matters when the
  /// list is full: remove one, so another can take its place.
  Widget _devices(BuildContext context, AtrustService service) {
    final theme = Theme.of(context);
    final session = service.session;
    final trust = service.trust;
    if (session == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(
            children: [
              Icon(
                Icons.devices_outlined,
                size: 18,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                trust == null
                    ? '已授信设备'
                    : '已授信设备（${trust.devices.length}）',
                style: theme.textTheme.titleSmall,
              ),
              const Spacer(),
              TextButton(
                onPressed: service.busy
                    ? null
                    : () => unawaited(service.refreshTrust()),
                child: const Text('刷新'),
              ),
            ],
          ),
        ),
        if (trust == null)
          const ListTile(
            dense: true,
            leading: Icon(Icons.help_outline, size: 18),
            title: Text('未取到列表：控制器不可达'),
          )
        else if (trust.devices.isEmpty)
          const ListTile(
            dense: true,
            leading: Icon(Icons.inbox_outlined, size: 18),
            title: Text('账号下还没有授信终端'),
          )
        else
          for (final device in trust.devices)
            _deviceTile(device, trust, service),
      ],
    );
  }

  Widget _deviceTile(
    AtrustTrustedDevice device,
    AtrustTrustState trust,
    AtrustService service,
  ) {
    final isSelf = device.id == trust.selfId;
    final name = device.name.isEmpty ? device.id : device.name;
    return ListTile(
      dense: true,
      leading: Icon(
        device.online ? Icons.smartphone : Icons.smartphone_outlined,
        size: 18,
      ),
      title: Text(name),
      subtitle: Text(
        [
          if (device.deviceType.isNotEmpty) device.deviceType,
          if (isSelf) '本机',
          device.online ? '在线' : '离线',
        ].join(' · '),
      ),
      // This device's own entry is not a thing to remove from here: unbinding
      // yourself while you are using the session is a different decision.
      trailing: isSelf
          ? null
          : TextButton(
              onPressed: service.busy
                  ? null
                  : () => unawaited(_untrust(device, name, service)),
              child: const Text('解除授信'),
            ),
    );
  }

  Future<void> _untrust(
    AtrustTrustedDevice device,
    String name,
    AtrustService service,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('解除授信'),
        content: Text('“$name”将不再免短信，它下次登录需要验证码。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final done = await service.untrustDevice(device.id);
    if (!mounted) return;
    _toast(done ? '已解除「$name」的授信' : service.detail, ok: done);
  }

  /// Runs whatever the card's one button currently says — the account's way back
  /// in, or the tunnel's start, stop and retry.
  Future<void> _run(String label) async {
    switch (label) {
      case '重试登录':
        await _connect();
      case '停止隧道':
        await _service.stopTunnel();
        // A stop the platform would not honour has something to say — where the
        // interface can be released — and that belongs in front of the user, not
        // only in the status line.
        if (mounted) _toast(_service.detail, ok: !_service.systemVpnActive);
      default:
        await _service.startTunnel();
    }
  }

  Future<void> _showError(String error) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('错误详情'),
        content: SingleChildScrollView(child: SelectableText(error)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // --- actions --------------------------------------------------------------

  List<Widget> _actions(BuildContext context, AtrustService service) {
    final session = service.session;
    final trust = service.trust;
    final busy = service.busy || _probing;
    final tunnelAlive = service.tunnelStatus?.alive == true;
    return [
      ListTile(
        leading: Icon(service.session == null ? Icons.login : Icons.logout),
        title: Text(service.session == null ? '登录 VPN 账号' : '退出登录'),
        subtitle: Text(
          service.session == null ? '登录并注册设备会话' : '停止隧道并退出登录的会话',
        ),
        enabled: !busy,
        onTap: busy
            ? null
            : () => unawaited(
                  service.session == null ? _connect() : _disconnect(),
                ),
      ),
      if (session != null && _canBind(trust, session))
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: const Text('把本机设为授信终端'),
          subtitle: Text(_bindHint(service)),
          enabled: !busy,
          onTap: () => unawaited(_bind()),
        ),
      SwitchListTile(
        secondary: const Icon(Icons.route_outlined),
        title: const Text('仅校园网段代理'),
        subtitle: const Text('仅 *.shanghaitech.edu.cn，其余保持直连'),
        value: service.routingEnabled,
        onChanged: tunnelAlive ? service.setRouting : null,
      ),
      if (service.systemVpnSupported)
        ListTile(
          leading: const Icon(Icons.battery_saver_outlined),
          title: const Text('忽略电池优化'),
          subtitle: const Text('添加 TechPie 到电池优化白名单，防止 VPN 意外中断'),
          enabled: !busy,
          onTap: busy ? null : () => unawaited(service.openBatterySettings()),
        ),
      if (service.tunnelSupported && !service.systemVpnSupported) ...[
        ListTile(
          leading: const Icon(Icons.vpn_lock_outlined),
          title: const Text('SOCKS5 端口'),
          subtitle: Text(
            service.socksProxy.isEmpty ? '未开启' : service.socksProxy,
          ),
          enabled: !busy,
          onTap: busy ? null : () => unawaited(_editProxy(service, socks: true)),
        ),
        ListTile(
          leading: const Icon(Icons.http_outlined),
          title: const Text('HTTP 端口'),
          subtitle: Text(service.httpProxy.isEmpty ? '未开启' : service.httpProxy),
          enabled: !busy,
          onTap:
              busy ? null : () => unawaited(_editProxy(service, socks: false)),
        ),
      ],
    ];
  }

  /// Edits one local listener. An empty address turns that listener off, which is
  /// how the engine says it and how geektrust's config says it.
  Future<void> _editProxy(AtrustService service, {required bool socks}) async {
    final current = socks ? service.socksProxy : service.httpProxy;
    final controller = TextEditingController(text: current);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(socks ? 'SOCKS5 端口' : 'HTTP 端口'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '127.0.0.1:1080',
            helperText: 'host:port；留空则不开启这个监听',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (value == null) return;
    if (value.isNotEmpty && !_isHostPort(value)) {
      _toast('要写成 host:port，例如 127.0.0.1:1080', ok: false);
      return;
    }
    await service.setProxies(
      socks: socks ? value : service.socksProxy,
      http: socks ? service.httpProxy : value,
    );
    if (!mounted) return;
    _toast(service.detail, ok: true);
  }

  /// `host:port`, with a port in range — the engine binds this address itself.
  static bool _isHostPort(String value) {
    final parts = value.split(':');
    if (parts.length != 2) return false;
    final host = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    return host.isNotEmpty && port != null && port > 0 && port < 65536;
  }

  Future<void> _connect() async {
    final service = _service;
    // A stored session costs nothing and needs no SMS: try it before asking the
    // controller for a fresh one. If restore already reached the SMS step,
    // reuse that state — do not start a second serialized login chain.
    final restored = await service.restore();
    if (restored.isOnline) return;

    final state = restored.stage == AtrustStage.needSms
        ? restored
        : await service.signIn();
    if (!mounted) return;
    if (state.stage != AtrustStage.needSms) return;
    final code = await _askForCode(state.hint);
    if (code.isEmpty) return;
    await service.submitSms(code);
  }

  Future<void> _disconnect() => _service.signOut();

  Future<void> _bind() async {
    final service = _service;
    final bound = await service.bindTrustedTerminal();
    if (!mounted) return;
    _toast(service.detail, ok: bound);
  }

  void _toast(String message, {required bool ok}) {
    if (message.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<String> _askForCode(String hint) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('短信验证码'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    return code ?? '';
  }

  // --- diagnostics ----------------------------------------------------------

  /// What to do when it does not work. Kept on the same page because the
  /// answers are only useful next to the state they explain.
  Widget _diagnostics(BuildContext context, AtrustService service) {
    return ExpansionTile(
      leading: const Icon(Icons.troubleshoot_outlined),
      title: const Text('诊断'),
      children: [
        SwitchListTile(
          title: const Text('客户端模式（SDPClient）'),
          subtitle: const Text('只有客户端模式的会话可以被授信；关掉可对照浏览器模式'),
          value: service.clientType == AtrustClientType.desktop,
          onChanged: service.busy
              ? null
              : (desktop) => setState(() {
                    service.clientType = desktop
                        ? AtrustClientType.desktop
                        : AtrustClientType.browser;
                  }),
        ),
        ListTile(
          leading: const Icon(Icons.verified_outlined),
          title: const Text('授信策略'),
          subtitle: Text(
            service.trust == null
                ? '未取到（控制器不可达或尚未查询）'
                : _trustDiagnostics(service.trust!),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.network_check),
          title: Text(_probing ? '测试中…' : '测试校内地址'),
          subtitle: Text(
            _probeResult.isEmpty
                ? 'netinfo.shanghaitech.edu.cn 与 10.15.89.181'
                : _probeResult,
          ),
          onTap: _probing ? null : () => unawaited(_probe(service)),
        ),
        ListTile(
          leading: const Icon(Icons.speed_outlined),
          title: const Text('引擎网卡计数'),
          subtitle: Text(_counters(service)),
        ),
        ListTile(
          leading: const Icon(Icons.sync_alt_outlined),
          title: const Text('引擎连接尝试'),
          // The engine's cumulative count of dials the inbound asked it for
          // (proxy requests and tun flows). It is history, not current activity,
          // and it says nothing about whether the tunnel is up — which is why it
          // lives here and not on the status card.
          subtitle: Text(_dials(service)),
        ),
        ListTile(
          leading: const Icon(Icons.memory_outlined),
          title: const Text('核心库'),
          subtitle: Text(
            service.tunnelSupported
                ? '${service.tunnelVersion}（ABI ${service.tunnel.abi}）'
                : '不可用：${service.tunnelUnsupportedReason}',
          ),
        ),
      ],
    );
  }

  String _counters(AtrustService service) {
    final tun = service.tunnelStatus?.tun ?? const <String, int>{};
    if (tun.isEmpty) return '没有已连接的网卡';
    return tun.entries.map((entry) => '${entry.key}=${entry.value}').join(' ');
  }

  /// What the controller said about trusted terminals, verbatim enough to be
  /// read rather than guessed at: this device's id, its own verdict, how many
  /// terminals the account already has, and the policy as it was sent.
  String _trustDiagnostics(AtrustTrustState trust) {
    final config = trust.config.isEmpty
        ? '（未下发 trustDeviceConfig）'
        : trust.config.entries
            .map((entry) => '${entry.key}=${entry.value}')
            .join(' · ');
    return 'selfId=${trust.selfId} · 本机状态=${trust.currentTrustStatus} · '
        '已有终端 ${trust.devices.length} 台 · $config';
  }

  /// `dial_attempts`: every destination dial the engine has been asked to make
  /// since it started, counted cumulatively. A tunnel that is up with a frozen
  /// count is normal; a count that climbs while `alive` stays false means the
  /// destination is being retried.
  String _dials(AtrustService service) {
    final status = service.tunnelStatus;
    if (status == null) return '引擎未运行';
    return '累计 ${status.dialAttempts} 次'
        '${status.alive ? '（隧道在线）' : '（隧道未连接）'}';
  }

  Future<void> _probe(AtrustService service) async {
    setState(() {
      _probing = true;
      _probeResult = '测试中…';
    });
    final results = <String>[];
    try {
      for (final target in atrustCampusTargets) {
        results.add(await probeCampusTarget(target));
      }
    } finally {
      debugPrint('[atrust] probe: ${results.join(' | ')}');
      if (mounted) {
        setState(() {
          _probing = false;
          _probeResult = results.join('\n');
        });
      }
    }
  }
}
