import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/wearable_device.dart';
import '../services/band_service.dart';
import '../services/service_provider.dart';
import '../theme/tp_icons.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'band_settings_page.dart';
import 'watch_settings_page.dart';

/// 穿戴设备列表：右上角添加，长按删除。
class WearablesPage extends StatefulWidget {
  const WearablesPage({super.key});

  static bool get isSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  State<WearablesPage> createState() => _WearablesPageState();
}

class _WearablesPageState extends State<WearablesPage> {
  bool _loaded = false;
  List<WearableDevice> _devices = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    _devices = _load();
  }

  List<WearableDevice> _load() {
    final stored = ServiceProvider.of(context).storageService.storedWearableDevices;
    final isApplePlatform = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    if (stored != null) {
      return stored
          .where((device) => isApplePlatform ? device.isAppleWatch : !device.isAppleWatch)
          .toList();
    }
    // iOS keeps its paired Apple Watch entry; bands are user-added only —
    // an empty list is the truth for a fresh install, not a default model.
    if (isApplePlatform) return const [appleWatchDevice];
    return const [];
  }

  Future<void> _save() async {
    await ServiceProvider.of(context).storageService.setWearableDevices(_devices);
  }

  Future<void> _addDevice() async {
    // 允许重复添加同型号（一人多设备）。
    final options = <WearableDevice>[
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) ...wearableBandCatalog,
      if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) appleWatchDevice,
    ];
    final selected = await showDialog<WearableDevice>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('添加穿戴设备'),
        children: [
          SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final device in options)
                  SimpleDialogOption(
                    onPressed: () => Navigator.of(context).pop(device),
                    child: Text(device.name),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() => _devices = [..._devices, selected]);
    await _save();
  }

  Future<void> _removeDevice(int index) async {
    final device = _devices[index];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${device.name}？'),
        content: const Text('只从本机列表移除，不影响小米运动健康中的设备绑定。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    // 按位置删除：同型号可重复添加（const 目录项实例相同，不能按 id/实例删）。
    setState(
      () => _devices = [
        ..._devices.take(index),
        ..._devices.skip(index + 1),
      ],
    );
    await _save();
  }

  Future<void> _openDevice(WearableDevice device) async {
    await pushAdaptivePage<void>(
      context,
      builder: (_) =>
          device.isAppleWatch ? const WatchSettingsPage() : BandSettingsPage(device: device),
    );
  }

  String _subtitle(WearableDevice device) {
    if (device.isAppleWatch) return '校园卡付款与同步';
    final node = BandService.instance.nodeName;
    if (matchesConnectedNode(device, node)) return '已连接 · $node';
    return '通过小米运动健康连接';
  }

  @override
  Widget build(BuildContext context) {
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);
    return Scaffold(
      extendBodyBehindAppBar: AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '穿戴设备',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: 'Settings',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回 Settings',
            ),
          ],
          trailingItems: const [
            IosNativeNavigationBarItem(
              id: 'add',
              title: 'Add',
              sfSymbol: 'plus',
              accessibilityLabel: '添加设备',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            } else if (id == 'add') {
              unawaited(_addDevice());
            }
          },
        ),
        material: () => BlurredAppBar(
          title: const Text('穿戴设备'),
          actions: [
            IconButton(
              tooltip: '添加设备',
              icon: const Icon(TpIcons.add),
              onPressed: () => unawaited(_addDevice()),
            ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: BandService.instance,
        builder: (context, _) => ListView(
          padding: EdgeInsets.only(top: topInset),
          children: [
            if (_devices.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 48, 24, 24),
                child: Column(
                  children: [
                    Icon(TpIcons.watch, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('暂未添加设备'),
                    SizedBox(height: 4),
                    Text(
                      '点击右上角 + 添加',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            for (final entry in _devices.asMap().entries)
              ListTile(
                leading: Icon(
                  entry.value.isAppleWatch ? TpIcons.watch : TpIcons.linkedAccounts,
                ),
                title: Text(entry.value.name),
                subtitle: Text(_subtitle(entry.value)),
                trailing: const Icon(TpIcons.chevronRight),
                onTap: () => unawaited(_openDevice(entry.value)),
                onLongPress: () => unawaited(_removeDevice(entry.key)),
              ),
            const Divider(),
            const ListTile(
              leading: Icon(TpIcons.info),
              title: Text('提示'),
              subtitle: Text('右上角 + 添加设备；长按设备可删除。手环需先在小米运动健康中完成绑定，华为手表需先在华为运动健康中配对。'),
            ),
          ],
        ),
      ),
    );
  }
}
