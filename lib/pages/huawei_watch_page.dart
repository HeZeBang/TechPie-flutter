import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/wear/wear_engine_service.dart';
import '../services/wear/wear_protocol.dart';
import '../widgets/adaptive_button.dart';

class HuaweiWatchPage extends StatelessWidget {
  const HuaweiWatchPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('HUAWEI WATCH')),
        body: HuaweiWatchContent(
          service: ServiceProvider.of(context).wearEngineService,
        ),
      );
}

class HuaweiWatchContent extends StatefulWidget {
  const HuaweiWatchContent({super.key, required this.service});
  final WearEngineService? service;

  @override
  State<HuaweiWatchContent> createState() => _HuaweiWatchContentState();
}

class _HuaweiWatchContentState extends State<HuaweiWatchContent>
    with WidgetsBindingObserver {
  bool _busy = false;
  String? _error;
  List<Map<String, dynamic>> _devices = [];
  // The peer identity depends on the signed watch package, not on the watch model.
  final _fingerprint = TextEditingController(
    text: const String.fromEnvironment(
      'HUAWEI_WATCH_FINGERPRINT',
      defaultValue:
          'com.geekpie.techpie.watch_BFjBt5qvHo/1DXUCrRMIVMWeFuJfD6GS2ugQUhvqU5jnzucWokWlHWfpowxvojMSEXfV3n792x8buDocrZ7J6Uw=',
    ),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.service?.addListener(_changed);
    unawaited(widget.service?.refreshStatus());
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

  Future<void> _run(Future<void> Function() operation) async {
    if (_busy) return;
    setState(() {
      _busy = true;
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
    final code = error is WearFailure ? error.code : '';
    return switch (code) {
      'PERMISSION_DENIED' => '未获得设备访问授权，请重新授权。',
      'ACCOUNT_NOT_READY' => '请先登录 TechPie，并补齐姓名与学号。',
      'DEVICE_DISCONNECTED' => '手表未连接，请先在华为运动健康中完成配对。',
      'SYNC_TIMEOUT' || 'PEER_NOT_READY' => '手表应用未响应，请打开手表上的 TechPie 后重试。',
      'INVALID_PAYLOAD' => '请在开发连接配置中填写手表应用的通信指纹。',
      _ => '连接失败，请检查运动健康、应用授权及两端签名配置后重试。',
    };
  }

  Future<void> _findDevices() => _run(() async {
        final service = widget.service!;
        final permissions = await service.requestPermissions();
        if (permissions['p2p'] != true) {
          throw const WearFailure('PERMISSION_DENIED');
        }
        final devices = await service.devices();
        if (mounted) setState(() => _devices = devices);
      });

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.service?.removeListener(_changed);
    _fingerprint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final connected = service?.ready == true;
    final user = service?.displayAccount;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            children: [
              ListTile(
                leading:
                    Icon(connected ? Icons.watch : Icons.watch_off_outlined),
                title: Text(
                  connected ? '已连接' : '未连接',
                  key: const Key('huawei-watch-connection'),
                ),
                subtitle:
                    Text(connected ? 'TechPie 手表应用已连接' : '等待连接 TechPie 手表应用'),
              ),
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(user?['name'] ?? '暂无设备用户'),
                subtitle: Text(
                  user == null ? '连接并同步账号后显示姓名与学号' : '学号：${user['studentId']}',
                ),
              ),
            ],
          ),
        ),
        if (!connected) ...[
          const SizedBox(height: 16),
          const Text(
            '连接引导',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text('1. 开启蓝牙，在华为运动健康中配对手表并确认已连接。\n'
              '2. 在手表上安装并打开 TechPie。\n'
              '3. 登录手机 TechPie，授权设备访问并选择下方手表。'),
          const SizedBox(height: 16),
          if (service == null)
            const Text('当前手机平台暂不支持此连接方式，请使用 Android 手机连接。')
          else ...[
            AdaptiveButton(
              label: '授权并查找手表',
              sfSymbol: 'magnifyingglass',
              icon: Icons.search,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_findDevices()),
            ),
            for (final device in _devices)
              ListTile(
                leading: const Icon(Icons.watch_outlined),
                title: Text(
                  '${device['name'] ?? device['model'] ?? 'HUAWEI WATCH'}',
                ),
                subtitle: Text(
                  device['connected'] == true
                      ? '运动健康已连接 · 点击连接 TechPie'
                      : '运动健康未连接',
                ),
                enabled: !_busy && device['connected'] == true,
                onTap: () => unawaited(
                  _run(
                    () => service.open(
                      device['id'] as String,
                      watchFingerprint: _fingerprint.text.trim(),
                    ),
                  ),
                ),
              ),
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text('尚未发现手表，请完成配对后重新查找。'),
              ),
            if (kDebugMode)
              ExpansionTile(
                title: const Text('开发连接配置'),
                children: [
                  TextField(
                    controller: _fingerprint,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: '手表应用通信指纹',
                      helperText: '使用已签名手表应用的 Wear Engine 指纹',
                    ),
                  ),
                ],
              ),
          ],
        ] else ...[
          const SizedBox(height: 16),
          AdaptiveButton(
            label: '同步设备用户',
            sfSymbol: 'arrow.triangle.2.circlepath',
            icon: Icons.sync,
            loading: _busy,
            onPressed: _busy
                ? null
                : () => unawaited(
                      _run(() => service!.refresh(resources: ['account'])),
                    ),
          ),
          const SizedBox(height: 8),
          AdaptiveButton(
            label: '断开连接',
            sfSymbol: 'link',
            icon: Icons.link_off,
            onPressed: _busy ? null : () => unawaited(_run(service!.close)),
          ),
        ],
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
