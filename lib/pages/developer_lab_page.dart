import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:techpie/services/atrust_control_client.dart';
import 'package:techpie/services/atrust_routing.dart';
import 'package:techpie/services/atrust_tunnel_service.dart';
import 'package:techpie/services/atrust_vpn_service.dart';
import 'package:techpie/services/http_client.dart';
import '../services/ecard_bind_hijack.dart';
import '../services/ecard_bind_service.dart';
import '../services/service_provider.dart';
import '../utils/haptics.dart';
import '../utils/platform.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

/// A place to exercise the device APIs the app depends on, reached from the
/// developer section of the settings page: every waveform the app can play, every
/// sound it ships, and — as more of them arrive — whatever else is worth judging
/// on a real device rather than at a desk.
///
/// The lists are built from [AppHaptics.all], so a waveform added to the
/// dictionary appears here without touching this file. A new kind of probe
/// belongs in its own section at the end.
final class DeveloperLabPage extends StatelessWidget {
  const DeveloperLabPage({super.key});

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topPad = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    final waveforms = AppHaptics.all.values.toList(growable: false);
    final sounds = <String, AppHapticWaveform>{};
    for (final waveform in waveforms) {
      final asset = waveform.soundAsset;
      if (asset != null) sounds.putIfAbsent(asset, () => waveform);
    }
    final designed = waveforms
        .where((waveform) => waveform.soundAsset != null)
        .toList(growable: false);

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'Developer Lab',
              trailingItems: const [],
              onItemPressed: (_) {},
            )
          : const BlurredAppBar(title: Text('Developer Lab')),
      body: ListView(
        padding: EdgeInsets.only(top: topPad, bottom: 32),
        children: [
          if (!AppHaptics.hasPlayer) const _NoPlayerNotice(),
          const _Section(
            key: Key('lab-atrust'),
            header: 'aTrust tunnel',
            footer:
                'The core library carries campus traffic only. Arming the '
                'switch sends this app\'s own campus requests through it; '
                'everything else in the app keeps going direct.',
            children: [_AtrustPanel()],
          ),
          _Section(
            key: const Key('lab-haptics'),
            header: 'Haptics',
            footer: 'Vibration only — the waveform the app plays for this id.',
            children: [
              for (final waveform in waveforms)
                _LabTile(
                  title: waveform.id,
                  subtitle: _summary(waveform),
                  icon: Icons.vibration,
                  onTap: () => unawaited(AppHaptics.play(waveform)),
                ),
            ],
          ),
          _Section(
            key: const Key('lab-sounds'),
            header: 'Sounds',
            footer: 'Sound only — the assets the app ships.',
            children: [
              for (final entry in sounds.entries)
                _LabTile(
                  title: _fileName(entry.key),
                  subtitle: '${entry.value.soundDurationMs ?? entry.value.durationMs} ms'
                      ' · ${entry.value.id}',
                  icon: Icons.volume_up_outlined,
                  onTap: () => unawaited(
                      AppHaptics.play(entry.value, sound: true, vibration: false),
                    ),
                ),
            ],
          ),
          _Section(
            key: const Key('lab-together'),
            header: 'Together',
            footer: 'What the app plays for these two moments: waveform and sound.',
            children: [
              for (final waveform in designed)
                _LabTile(
                  title: waveform.id,
                  subtitle: _summary(waveform),
                  icon: Icons.play_circle_outline,
                  onTap: () => unawaited(AppHaptics.play(waveform, sound: true)),
                ),
            ],
          ),
          const _EcardBindProbe(),
        ],
      ),
    );
  }

  /// What the row says about a waveform: how many pulses, how long, and whether
  /// it also carries a sound.
  static String _summary(AppHapticWaveform waveform) {
    final pulses = waveform.pulses.length == 1 ? '1 pulse' : '${waveform.pulses.length} pulses';
    final sound = waveform.soundAsset == null ? '' : ' · sound';
    return '$pulses · ${waveform.durationMs} ms$sound';
  }

  static String _fileName(String asset) => asset.split('/').last;
}

final class _NoPlayerNotice extends StatelessWidget {
  const _NoPlayerNotice();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.errorContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            'This platform has no player, so nothing here will play. '
            'The developer lab is meant for a phone.',
            style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
          ),
        ),
      );
}

final class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.header,
    required this.footer,
    required this.children,
  });

  final String header;
  final String footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Text(
              header,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ...children,
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Text(
              footer,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
}

final class _LabTile extends StatelessWidget {
  const _LabTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.play_arrow),
        onTap: onTap,
      );
}

/// The eCard bind-code tunnel's diagnosis, moved here from the user-facing
/// account page: the technical readout belongs in a lab, not in front of a user
/// who only needs to agree to the VPN prompt.
final class _EcardBindProbe extends StatefulWidget {
  const _EcardBindProbe();

  @override
  State<_EcardBindProbe> createState() => _EcardBindProbeState();
}

final class _EcardBindProbeState extends State<_EcardBindProbe> {
  bool _busy = false;
  EcardBindDiagnosis? _diagnosis;

  Future<void> _check() async {
    final bind = ServiceProvider.of(context).ecardBindService;
    setState(() => _busy = true);
    final diagnosis = await bind.diagnose();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _diagnosis = diagnosis;
    });
  }

  static String _lines(EcardBindDiagnosis diagnosis) {
    final addresses = diagnosis.lookupError != null
        ? '解析失败（${diagnosis.lookupError}）'
        : '${diagnosis.addresses.join(', ')}'
            '${diagnosis.routesToBindService ? '（已指向绑定服务）' : '（未劫持）'}';
    return '状态：${diagnosis.status.name}\n'
        '解析 ${EcardBindHijackService.host}：$addresses\n'
        '健康检查：${diagnosis.healthLine}';
  }

  @override
  Widget build(BuildContext context) {
    final diagnosis = _diagnosis;
    return _Section(
      key: const Key('lab-ecard-bind'),
      header: 'eCard bind',
      footer: 'The bind-code tunnel: its status, what the host resolves to, and '
          'whether the bind service answers.',
      children: [
        ListTile(
          leading: const Icon(Icons.travel_explore_outlined),
          title: Text(_busy ? '正在自检…' : '自检'),
          subtitle: diagnosis == null ? null : Text(_lines(diagnosis)),
          trailing: _busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.play_arrow),
          onTap: _busy ? null : () => unawaited(_check()),
        ),
      ],
    );
  }
}


/// The campus tunnel, driven by hand. The control plane lives in the app (login,
/// SMS, session), the packet path in the pinned core library; this panel is the
/// seam between them and the only place either is exercised outside a test.
final class _AtrustPanel extends StatefulWidget {
  const _AtrustPanel();

  @override
  State<_AtrustPanel> createState() => _AtrustPanelState();
}

final class _AtrustPanelState extends State<_AtrustPanel> {
  late final AtrustTunnelService _tunnel;
  final AtrustVpnService _vpn = AtrustVpnService();
  AtrustControlClient? _control;
  AtrustLoginState? _login;
  AtrustTunnelStatus? _tunnelStatus;
  AtrustTunnelStatus? _vpnTunnelStatus;
  AtrustClientType _clientType = AtrustClientType.desktop;
  String _detail = '';

  @override
  void initState() {
    super.initState();
    // Loading is cheap and never throws: a platform without the library (or one
    // built for a different ABI) reports itself here instead of breaking boot.
    _tunnel = AtrustTunnelService.load();
  }

  AtrustControlClient _client(BuildContext context) {
    final services = ServiceProvider.of(context);
    return _control ??= AtrustControlClient(
      http: LoggingHttpClient(services.debugLogger),
      storage: services.storageService,
      castgc: services.thirdPartyAuthService.cpdailyCookies,
      clientType: _clientType,
      onTrace: (stage) async => debugPrint('[atrust] $stage'),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    final control = _client(context);
    try {
      var state = await control.login();
      if (state.stage == AtrustStage.needSms) {
        if (!context.mounted) return;
        final code = await _askForCode(context, state.hint);
        if (code.isEmpty) {
          _set(state, '已取消');
          return;
        }
        state = await control.submitSms(code);
      }
      if (state.stage != AtrustStage.online) {
        _set(state, '未登录');
        return;
      }
      final session = control.session!;
      _tunnel.start(
        sessionJson: jsonEncode({
          'sid': session.sid,
          'device_id': session.deviceId,
          'username': session.username,
          'base_url': session.baseUrl,
          'gateways': session.gateways,
          'dns': session.dns,
        }),
        policyJson: session.policyJson,
      );
      _tunnel.startProxies(socksAddress: AtrustRouting.socksProxy);
      _set(
        state,
        '已上线 ${session.username}'
        '${session.trusted ? '（本机已授信）' : '（未授信，下次仍要短信）'}',
      );
    } on Object catch (error) {
      _set(_login, '失败：$error');
    }
  }

  Future<String> _askForCode(BuildContext context, String hint) async {
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

  void _stop({bool logout = false}) {
    AtrustRouting.enabled = false;
    _tunnel.stop();
    if (logout) {
      final control = _control;
      if (control != null) unawaited(control.logout());
      _control = null;
      _login = null;
    }
    _set(_login, logout ? '已登出' : '已停止');
  }

  Future<void> _startVpn(BuildContext context) async {
    // A stored session is enough: asking for a fresh login would spend another
    // SMS for nothing when the campus session is still alive.
    final control = _client(context);
    var session = control.session;
    if (session == null) {
      final restored = await control.ensureOnline();
      if (!restored.isOnline) {
        _set(restored, '先登录，系统 VPN 需要一份会话');
        return;
      }
      session = control.session!;
      _set(restored, restored.restored ? '已恢复会话' : '已上线');
    }
    try {
      var verdict = await _vpn.start(session, engine: _tunnel);
      final extensionStatus = await _vpn.status();
      AtrustTunnelStatus? systemStatus;
      final engineStatus = extensionStatus?['engineStatus'];
      if (engineStatus is String && engineStatus.isNotEmpty) {
        final decoded = jsonDecode(engineStatus);
        if (decoded is Map<String, dynamic>) {
          systemStatus = AtrustTunnelStatus.fromJson(decoded);
        }
      }
      if (verdict.startsWith('failed') &&
          '${extensionStatus?['status']}' == 'active') {
        // The extension won after the app stopped waiting.
        verdict = 'active';
      }
      if (mounted) {
        setState(() => _vpnTunnelStatus = systemStatus);
      }
      _set(
        _login,
        '系统 VPN：$verdict'
        '${engineStatus == null ? '' : ' · $engineStatus'}',
      );
    } on Object catch (error) {
      _set(_login, '系统 VPN 失败：$error');
    }
  }

  Future<void> _stopVpn() async {
    try {
      await _vpn.stop(engine: _tunnel);
      if (mounted) setState(() => _vpnTunnelStatus = null);
      _set(_login, '系统 VPN 已停止');
    } on Object catch (error) {
      _set(_login, '停止系统 VPN 失败：$error');
    }
  }

  void _set(AtrustLoginState? login, String detail) {
    if (!mounted) return;
    setState(() {
      _login = login;
      _detail = detail;
      _tunnelStatus = _tunnel.isSupported ? _tunnel.status() : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _login;
    final status = _vpnTunnelStatus ?? _tunnelStatus;
    final lines = <String>[
      _tunnel.isSupported
          ? '库：${_tunnel.version}（ABI ${_tunnel.abi}）'
          : '库不可用：${_tunnel.unsupportedReason}',
      session == null
          ? '会话：未登录'
          : '会话：${session.restored ? '恢复' : '新建'} · ${session.stage.name}'
                '${session.hint.isEmpty ? '' : ' · ${session.hint}'}',
      status == null
          ? '隧道：未运行'
          : '隧道：${status.alive ? '在线' : '未连'}'
                '${status.vip.isEmpty ? '' : ' · ${status.vip}'}'
                '${status.gateway.isEmpty ? '' : ' · ${status.gateway}'}',
      if (_detail.isNotEmpty) _detail,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            lines.join('\n'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.shield_outlined),
          title: const Text('客户端类型'),
          subtitle: Text(
            _clientType == AtrustClientType.desktop
                ? 'SDPClient — 可绑定授信终端，绑定后不再每次要短信'
                : 'SDPBrowserClient — 每次都需短信',
          ),
          trailing: Switch(
            value: _clientType == AtrustClientType.desktop,
            onChanged: (desktop) => setState(() {
              _clientType = desktop
                  ? AtrustClientType.desktop
                  : AtrustClientType.browser;
              _control = null;
            }),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.login),
          title: const Text('登录并接入隧道'),
          subtitle: const Text('首次会要求短信验证码'),
          onTap: () => unawaited(_signIn(context)),
        ),
        ListTile(
          leading: const Icon(Icons.route_outlined),
          title: const Text('校园请求走隧道'),
          subtitle: const Text('仅 *.shanghaitech.edu.cn，其余保持直连'),
          trailing: Switch(
            value: AtrustRouting.enabled,
            onChanged: (enabled) => setState(() {
              AtrustRouting.enabled = enabled;
              _detail = enabled ? '已启用：校园请求走 SOCKS5' : '已关闭';
            }),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.stop_circle_outlined),
          title: const Text('停止隧道'),
          subtitle: const Text('保留会话，下次可直接恢复'),
          onTap: _stop,
        ),
        if (_vpn.isSupported) ...[
          ListTile(
            leading: const Icon(Icons.vpn_lock),
            title: const Text('启动系统 VPN（实验）'),
            subtitle: const Text('整机路由，WebView 与其它应用也能到校园内网'),
            onTap: () => unawaited(_startVpn(context)),
          ),
          ListTile(
            leading: const Icon(Icons.vpn_lock_outlined),
            title: const Text('停止系统 VPN'),
            subtitle: const Text('只影响系统接口，不动隧道会话'),
            onTap: () => unawaited(_stopVpn()),
          ),
        ],
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('登出'),
          subtitle: const Text('丢弃本地会话'),
          onTap: () => _stop(logout: true),
        ),
      ],
    );
  }
}
