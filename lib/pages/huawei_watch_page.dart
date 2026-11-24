import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/wear/wear_engine_service.dart';
import '../services/wear/wear_protocol.dart';
import '../theme/tp_tokens.dart';
import '../widgets/adaptive_button.dart';

class HuaweiWatchPage extends StatelessWidget {
  const HuaweiWatchPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HUAWEI WATCH')),
        body: SafeArea(
          child: HuaweiWatchContent(
            service: ServiceProvider.of(context).wearEngineService,
          ),
        ),
      );
}

class HuaweiWatchContent extends StatefulWidget {
  const HuaweiWatchContent({super.key, required this.service});
  final WearEngineService? service;

  @override
  State<HuaweiWatchContent> createState() => _HuaweiWatchContentState();
}

class _HuaweiWatchContentState extends State<HuaweiWatchContent> with WidgetsBindingObserver {
  bool _busy = false;
  String _busyLabel = '正在连接';
  String? _error;
  String? _deviceName;
  List<Map<String, dynamic>> _devices = [];
  bool _queried = false;
  final _fingerprint = TextEditingController(
    text: const String.fromEnvironment(
      'HUAWEI_WATCH_FINGERPRINT',
      defaultValue:
          'club.geekpie.techpie.wear_BNG6fOHV8gNhi/ONhV+JNBhEqhJ5tpMKaI78sTBxE+oCO4dicZWVdMaoztRQl7dx0CARaD2sL7NJ1pvmFammp6E=',
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service?.addListener(_changed);
    unawaited(widget.service?.refreshStatus());
  }

  @override
  void didUpdateWidget(covariant HuaweiWatchContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service) {
      oldWidget.service?.removeListener(_changed);
      widget.service?.addListener(_changed);
      _devices = [];
      _queried = false;
      _error = null;
      unawaited(widget.service?.refreshStatus());
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.service?.refreshStatus());
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    String label = '正在连接',
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _busyLabel = label;
      _error = null;
    });
    try {
      await operation();
    } catch (error) {
      if (mounted) setState(() => _error = _failure(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _failure(Object error) {
    if (error is WearFailure && error.nativeCode != null) {
      final message = switch (error.nativeCode) {
        2 => '请先安装华为运动健康。',
        3 => '请先在华为运动健康中登录华为账号。',
        4 => '请打开运动健康，确认手表已完成配对。',
        7 => '请先在运动健康中完成用户协议及隐私授权。',
        8 => '应用授权校验未通过，请稍后重试或联系开发者。',
        9 => '未获得设备访问权限，请重新授权。',
        13 || 18 => '当前设备或系统暂不支持此功能。',
        14 => '请更新华为运动健康后重试。',
        15 => '请允许运动健康自启动和后台运行，启动后重试。',
        16 => '请在运动健康中重新连接手表。',
        19 => '连接超时，请打开运动健康后重试。',
        206 => '与手表上的 TechPie 通信失败。请确认运动健康已连接手表，打开手表上的 TechPie 后重试。',
        _ => '连接未完成，请检查运动健康和应用授权。',
      };
      return '$message（SDK 错误码：${error.nativeCode}）';
    }
    final code = error is WearFailure ? error.code : '';
    return switch (code) {
      'PERMISSION_DENIED' => '未获得所需授权，请重新授权。',
      'ACCOUNT_NOT_READY' => '请先登录 TechPie',
      'DEVICE_DISCONNECTED' => '手表未连接，请先在运动健康中完成配对。',
      'SYNC_TIMEOUT' || 'PEER_NOT_READY' => '手表未响应，请保持手表上的 TechPie 打开后重试。',
      'STORAGE_FAILED' => '手表保存失败，请重试同步。',
      'INVALID_PAYLOAD' => '连接配置不匹配，请联系开发者。',
      'UNSUPPORTED_OPERATION' => '手表端 TechPie 需要更新，请前往运动健康完成更新。',
      _ => '操作未完成，请检查两端连接后重试。',
    };
  }

  Future<void> _findDevices() => _run(
        () async {
          setState(() {
            _queried = false;
            _devices = [];
          });
          final service = widget.service!;
          final permissions = await service.requestPermissions();
          if (permissions['p2p'] != true) {
            throw const WearFailure('PERMISSION_DENIED');
          }
          final devices = await service.devices();
          if (mounted) {
            setState(() {
              _devices = devices;
              _queried = true;
            });
          }
        },
        label: '正在查找手表',
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service?.removeListener(_changed);
    _fingerprint.dispose();
    super.dispose();
  }

  Widget _panel(BuildContext context, Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(TpTokens.radiusL),
        ),
        child: child,
      );

  String _syncLabel(WearEngineService service, String resource) {
    final sync = (service.getStatus()['sync'] as Map)[resource] as Map?;
    return switch (sync?['state']) {
      'applied' => '已同步',
      'pending' => '正在同步',
      'failed' => '同步未完成，请重试',
      _ => '等待同步',
    };
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final connected = service?.ready == true;
    final user = service?.displayAccount;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            _panel(
              context,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color:
                              connected ? colors.primaryContainer : colors.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(TpTokens.radiusM),
                        ),
                        child: Icon(
                          Icons.watch_outlined,
                          size: 30,
                          color: connected ? colors.onPrimaryContainer : colors.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? (_deviceName ?? 'HUAWEI WATCH') : '连接你的手表',
                              style: theme.textTheme.titleLarge,
                            ),
                            const SizedBox(height: 4),
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                _busy
                                    ? _busyLabel
                                    : connected
                                        ? '正在同步'
                                        : service?.autoSyncEnabled == true
                                            ? '等待自动恢复同步'
                                            : '等待首次配对',
                                key: const Key('huawei-watch-connection'),
                                style: theme.textTheme.bodyMedium?.copyWith(color: colors.primary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    connected
                        ? '同步手机当前显示的课表和待办。同步完成后可在手表离线查看。'
                        : '首次使用先在运动健康中配对，并打开两端 TechPie。之后打开应用会自动恢复同步。',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  if (service != null)
                    AdaptiveButton(
                      label: connected ? '同步到手表' : '授权并查找手表',
                      sfSymbol: connected ? 'arrow.triangle.2.circlepath' : 'magnifyingglass',
                      icon: connected ? Icons.sync : Icons.search,
                      role: AdaptiveButtonRole.prominent,
                      loading: _busy,
                      width: double.infinity,
                      onPressed: _busy
                          ? null
                          : () => unawaited(
                                connected
                                    ? _run(
                                        service.syncFromPhone,
                                        label: '正在同步',
                                      )
                                    : _findDevices(),
                              ),
                    )
                  else
                    const Text('当前平台暂不支持此连接方式，请使用 Android 手机连接。'),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.errorContainer,
                    borderRadius: BorderRadius.circular(TpTokens.radiusM),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: colors.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: SelectableText(
                          _error!,
                          style: TextStyle(
                            color: colors.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (!connected && _devices.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text('选择手表', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              for (final device in _devices)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  leading: const Icon(Icons.watch_outlined),
                  title: Text(
                    '${device['name'] ?? device['model'] ?? 'HUAWEI WATCH'}',
                  ),
                  subtitle: Text(
                    device['connected'] == true ? '点击连接 TechPie' : '请先在运动健康中连接',
                  ),
                  trailing: device['connected'] == true ? const Icon(Icons.chevron_right) : null,
                  enabled: !_busy && device['connected'] == true,
                  onTap: () => unawaited(
                    _run(() async {
                      _deviceName = '${device['name'] ?? device['model'] ?? 'HUAWEI WATCH'}';
                      await service!.open(
                        device['id'] as String,
                        watchFingerprint: _fingerprint.text.trim(),
                      );
                    }),
                  ),
                ),
            ],
            if (!connected && _queried && _devices.isEmpty && _error == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('尚未发现手表，请完成配对后重新查找。'),
              ),
            const SizedBox(height: 24),
            Text('设备用户', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              leading: const Icon(Icons.person_outline),
              title: Text(user?['name'] ?? '暂无设备用户'),
              subtitle: Text(
                user == null ? '连接并同步后显示姓名与学号' : '学号：${user['studentId']}',
              ),
            ),
            if (connected) ...[
              const SizedBox(height: 16),
              Text('手表功能', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.event_note_outlined),
                title: const Text('待办 DDL'),
                subtitle: Text(
                  service!.supports('ddl.display') ? _syncLabel(service, 'ddl') : '请更新手表应用以使用此功能',
                ),
              ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('未来 7 天课表'),
                subtitle: Text(
                  service.supports('schedule.display')
                      ? _syncLabel(service, 'schedule')
                      : '请更新手表应用以使用此功能',
                ),
              ),
              if (service.supports('reminder.watchLocal'))
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  secondary: const Icon(Icons.notifications_none),
                  title: const Text('DDL 提醒'),
                  subtitle: const Text(
                    '截止前 1 小时振动 · 手表应用在前台时生效',
                  ),
                  value: service.watchRemindersEnabled,
                  onChanged: _busy
                      ? null
                      : (enabled) => unawaited(
                            _run(
                              () => service.setWatchRemindersEnabled(enabled),
                              label: '正在更新提醒',
                            ),
                          ),
                ),
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                leading: const Icon(Icons.qr_code_rounded),
                title: const Text('校园码'),
                subtitle: Text(
                  service.supports('campusCode.qrMatrix') || service.supports('campusCode.qrBytes')
                      ? '手机联网获取校园码，通过已连接的手表显示。'
                      : '请更新手表应用以使用此功能',
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.link_off),
                label: const Text('暂停自动同步'),
                onPressed: _busy ? null : () => unawaited(_run(service.close, label: '正在断开')),
              ),
            ],
            const SizedBox(height: 16),
            const ExpansionTile(
              tilePadding: EdgeInsets.symmetric(horizontal: 8),
              title: Text('连接帮助'),
              leading: Icon(Icons.help_outline),
              children: [
                _GuideStep(
                  number: '1',
                  title: '在运动健康中配对',
                  detail: '开启蓝牙，确认手表显示已连接。',
                ),
                _GuideStep(
                  number: '2',
                  title: '打开手表上的 TechPie',
                  detail: '打开应用后自动同步，断连时使用已保存的数据。',
                ),
                _GuideStep(
                  number: '3',
                  title: '登录并授权手机 TechPie',
                  detail: '点击“授权并查找手表”，选择你的手表。',
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text('课表和待办可离线查看。校园码由已连接的手机联网获取。'),
                ),
              ],
            ),
            if (kDebugMode)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 8),
                title: const Text('开发连接配置'),
                childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                children: [
                  TextField(
                    controller: _fingerprint,
                    enabled: !_busy && !connected,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '手表应用通信指纹',
                      helperText: '使用已签名手表应用的 Wear Engine 指纹',
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _GuideStep extends StatelessWidget {
  const _GuideStep({
    required this.number,
    required this.title,
    required this.detail,
  });
  final String number, title, detail;

  @override
  Widget build(BuildContext context) => ListTile(
        leading: CircleAvatar(radius: 16, child: Text(number)),
        title: Text(title),
        subtitle: Text(detail),
      );
}
