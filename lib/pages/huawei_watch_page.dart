import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../services/wear/wear_engine_service.dart';
import '../services/wear/wear_protocol.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class HuaweiWatchPage extends StatelessWidget {
  const HuaweiWatchPage({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: 'HUAWEI WATCH',
          leadingItems: [
            if (Navigator.canPop(context))
              const IosNativeNavigationBarItem(
                id: 'back',
                title: '我的',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回我的',
              ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => const BlurredAppBar(title: Text('HUAWEI WATCH')),
      ),
      body: HuaweiWatchContent(
        service: ServiceProvider.of(context).wearEngineService,
        topPadding: topInset,
      ),
    );
  }
}

class HuaweiWatchContent extends StatefulWidget {
  const HuaweiWatchContent({
    super.key,
    required this.service,
    this.topPadding,
  });

  final WearEngineService? service;
  final double? topPadding;

  @override
  State<HuaweiWatchContent> createState() => _HuaweiWatchContentState();
}

class _HuaweiWatchContentState extends State<HuaweiWatchContent>
    with WidgetsBindingObserver {
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
      'OFFLINE_GRANT_REQUIRED' => '请先在校园卡页面开通有效的不限次离线授权，再同步到手表。',
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

  ({String label, TpBadgeTone tone}) _syncBadge(
    WearEngineService service,
    String resource,
  ) {
    final sync = (service.getStatus()['sync'] as Map)[resource] as Map?;
    return switch (sync?['state']) {
      'applied' => (label: '已同步', tone: TpBadgeTone.success),
      'pending' => (label: '正在同步', tone: TpBadgeTone.info),
      'failed' => (label: '同步未完成，请重试', tone: TpBadgeTone.danger),
      _ => (label: '等待同步', tone: TpBadgeTone.muted),
    };
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.service;
    final connected = service?.ready == true;
    final user = service?.displayAccount;
    final colors = context.tpColors;

    final statusText = _busy
        ? _busyLabel
        : connected
            ? '正在同步'
            : service?.autoSyncEnabled == true
                ? '等待自动恢复同步'
                : '等待首次配对';
    final statusFg = connected
        ? colors.successGreen
        : _busy
            ? colors.infoBlue
            : colors.brandInk;
    final statusBg = connected
        ? colors.successGreen.withValues(alpha: colors.isDark ? 0.16 : 0.10)
        : _busy
            ? colors.infoBlue.withValues(alpha: colors.isDark ? 0.16 : 0.10)
            : colors.brandSoft;

    final bottomPadding = AppShellMetrics.bottomContentPaddingOf(context);

    return ListView(
      padding: EdgeInsets.fromLTRB(
        TpTokens.pageHorizontalPadding,
        widget.topPadding ?? TpTokens.space4,
        TpTokens.pageHorizontalPadding,
        bottomPadding,
      ),
      children: [
        TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Hero status & primary action card
              TpCard(
                padding: const EdgeInsets.all(TpTokens.space5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: connected
                                ? colors.brandSoft
                                : colors.surfaceSubtle,
                            borderRadius:
                                BorderRadius.circular(TpTokens.radiusM),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            TpIcons.watch,
                            size: TpTokens.iconL + 2,
                            color: connected
                                ? colors.brandInk
                                : colors.textMuted,
                          ),
                        ),
                        const SizedBox(width: TpTokens.space4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                connected
                                    ? (_deviceName ?? 'HUAWEI WATCH')
                                    : '连接你的手表',
                                style: TpTypography.cardTitle(colors)
                                    .copyWith(fontSize: 18),
                              ),
                              const SizedBox(height: 6),
                              Semantics(
                                liveRegion: true,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: TpTokens.space2,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: statusBg,
                                    borderRadius: BorderRadius.circular(
                                      TpTokens.radiusPill,
                                    ),
                                  ),
                                  child: Text(
                                    statusText,
                                    key: const Key('huawei-watch-connection'),
                                    style: TpTypography.badge(statusFg),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TpTokens.space4),
                    Text(
                      connected
                          ? '同步手机当前显示的课表和待办。同步完成后可在手表离线查看。'
                          : '首次使用先在运动健康中配对，并打开两端 TechPie。之后打开应用会自动恢复同步。',
                      style: TpTypography.itemMeta(colors)
                          .copyWith(fontSize: 13.5, height: 1.45),
                    ),
                    const SizedBox(height: TpTokens.space5),
                    if (service != null)
                      AdaptiveButton(
                        label: connected ? '同步到手表' : '授权并查找手表',
                        sfSymbol: connected
                            ? 'arrow.triangle.2.circlepath'
                            : 'magnifyingglass',
                        icon: connected ? TpIcons.refresh : TpIcons.search,
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: TpTokens.space3,
                          vertical: TpTokens.space3,
                        ),
                        decoration: BoxDecoration(
                          color: colors.surfaceSubtle,
                          borderRadius:
                              BorderRadius.circular(TpTokens.radiusS),
                        ),
                        child: Text(
                          '当前平台暂不支持此连接方式，请使用 Android 手机连接。',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ),
                  ],
                ),
              ),

              if (_error != null) ...[
                const SizedBox(height: TpTokens.space3),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(TpTokens.space4),
                    decoration: BoxDecoration(
                      color: colors.dangerRed.withValues(
                        alpha: colors.isDark ? 0.16 : 0.08,
                      ),
                      borderRadius: BorderRadius.circular(TpTokens.radiusM),
                      border: Border.all(
                        color: colors.dangerRed.withValues(alpha: 0.28),
                        width: 0.75,
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          TpIcons.info,
                          size: TpTokens.iconM,
                          color: colors.dangerRed,
                        ),
                        const SizedBox(width: TpTokens.space3),
                        Expanded(
                          child: SelectableText(
                            _error!,
                            style: TpTypography.itemMeta(colors).copyWith(
                              color: colors.dangerRed,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],

              // 2. Discovered watches list (preserves ListTile enabled contract)
              if (!connected && _devices.isNotEmpty) ...[
                const SizedBox(height: TpTokens.sectionGap),
                TpCard(
                  title: '选择手表',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < _devices.length; i++) ...[
                        Builder(
                          builder: (context) {
                            final device = _devices[i];
                            final deviceConnected =
                                device['connected'] == true;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: TpTokens.cardPaddingHorizontal,
                                vertical: 2,
                              ),
                              leading: Icon(
                                TpIcons.watch,
                                size: TpTokens.iconM,
                                color: deviceConnected
                                    ? colors.brandInk
                                    : colors.textMuted,
                              ),
                              title: Text(
                                '${device['name'] ?? device['model'] ?? 'HUAWEI WATCH'}',
                                style: TpTypography.itemTitle(colors).copyWith(
                                  fontWeight: FontWeight.w500,
                                  color: deviceConnected
                                      ? colors.textPrimary
                                      : colors.textMuted,
                                ),
                              ),
                              subtitle: Text(
                                deviceConnected
                                    ? '点击连接 TechPie'
                                    : '请先在运动健康中连接',
                                style: TpTypography.itemMeta(colors),
                              ),
                              trailing: deviceConnected
                                  ? Icon(
                                      TpIcons.chevronRight,
                                      size: TpTokens.iconS,
                                      color: colors.textMuted,
                                    )
                                  : null,
                              enabled: !_busy && deviceConnected,
                              onTap: () => unawaited(
                                _run(() async {
                                  _deviceName =
                                      '${device['name'] ?? device['model'] ?? 'HUAWEI WATCH'}';
                                  await service!.open(
                                    device['id'] as String,
                                    watchFingerprint: _fingerprint.text.trim(),
                                  );
                                }),
                              ),
                            );
                          },
                        ),
                        if (i < _devices.length - 1)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: TpTokens.cardPaddingHorizontal +
                                  TpTokens.iconM +
                                  TpTokens.space3,
                              right: TpTokens.cardPaddingHorizontal,
                            ),
                            child: Divider(
                              height: 1,
                              thickness: 0.5,
                              color: colors.divider,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],

              if (!connected && _queried && _devices.isEmpty && _error == null) ...[
                const SizedBox(height: TpTokens.space3),
                TpCard(
                  padding: const EdgeInsets.all(TpTokens.space4),
                  child: Text(
                    '尚未发现手表，请完成配对后重新查找。',
                    style: TpTypography.itemMeta(colors),
                  ),
                ),
              ],

              // 3. Device user
              const SizedBox(height: TpTokens.sectionGap),
              TpCard(
                title: '设备用户',
                child: TpListRow(
                  icon: TpIcons.profile,
                  iconColor:
                      user != null ? colors.brandInk : colors.textMuted,
                  title: user?['name'] ?? '暂无设备用户',
                  subtitle: user == null
                      ? '连接并同步后显示姓名与学号'
                      : '学号：${user['studentId']}',
                ),
              ),

              // 4. Connected watch features & disconnect
              if (connected) ...[
                const SizedBox(height: TpTokens.sectionGap),
                Builder(
                  builder: (context) {
                    final ddlSupported = service!.supports('ddl.display');
                    final ddlStatus = ddlSupported
                        ? _syncBadge(service, 'ddl')
                        : null;
                    final scheduleSupported =
                        service.supports('schedule.display');
                    final scheduleStatus = scheduleSupported
                        ? _syncBadge(service, 'schedule')
                        : null;
                    final hasReminders =
                        service.supports('reminder.watchLocal');
                    final hasOfflineSm2 =
                        service.supports('campusCode.offlineSm2');

                    return TpCard(
                      title: '手表功能',
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TpListRow(
                            icon: TpIcons.deadlines,
                            iconColor: colors.brandInk,
                            title: '待办 DDL',
                            subtitle: ddlSupported
                                ? null
                                : '请更新手表应用以使用此功能',
                            trailing: ddlStatus != null
                                ? TpBadge(
                                    label: ddlStatus.label,
                                    tone: ddlStatus.tone,
                                  )
                                : null,
                            showDivider: true,
                          ),
                          TpListRow(
                            icon: TpIcons.schedule,
                            iconColor: colors.brandInk,
                            title: '未来 7 天课表',
                            subtitle: scheduleSupported
                                ? null
                                : '请更新手表应用以使用此功能',
                            trailing: scheduleStatus != null
                                ? TpBadge(
                                    label: scheduleStatus.label,
                                    tone: scheduleStatus.tone,
                                  )
                                : null,
                            showDivider: true,
                          ),
                          if (hasReminders)
                            TpListRow(
                              icon: TpIcons.bell,
                              iconColor: colors.brandInk,
                              title: 'DDL 提醒',
                              subtitle: '截止前 1 小时振动 · 手表应用在前台时生效',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: service.watchRemindersEnabled,
                                enabled: !_busy,
                                onChanged: (enabled) => unawaited(
                                  _run(
                                    () => service.setWatchRemindersEnabled(
                                      enabled,
                                    ),
                                    label: '正在更新提醒',
                                  ),
                                ),
                              ),
                            ),
                          TpListRow(
                            icon: TpIcons.qrCode,
                            iconColor: colors.brandInk,
                            title: '校园码',
                            subtitle: service.supports('campusCode.qrMatrix') ||
                                    service.supports('campusCode.qrBytes')
                                ? (hasOfflineSm2
                                    ? '同步离线授权后，手表可独立生成校园码。'
                                    : '可从手机获取校园码。手表离线授权状态：${service.offlineStatus ?? '设备未报告'}。')
                                : '请更新手表应用以使用此功能',
                            showDivider: hasOfflineSm2,
                          ),
                          if (hasOfflineSm2)
                            TpListRow(
                              icon: TpIcons.lock,
                              iconColor: colors.brandInk,
                              title: '同步离线校园码授权',
                              subtitle: service.offlineCampusCodeApplied
                                  ? '授权已保存到手表，可在完全断连时生成校园码。'
                                  : '将现有不限次离线授权和签名密钥保存到这块手表。',
                              trailing: AdaptiveSwitch(
                                value: service.offlineCampusCodeEnabled,
                                enabled: !_busy,
                                onChanged: (value) => unawaited(
                                  _run(
                                    () => service.setOfflineCampusCodeEnabled(
                                      value,
                                    ),
                                    label: '正在同步离线授权',
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: TpTokens.space3),
                TpCard(
                  child: TpListRow(
                    icon: TpIcons.unlink,
                    title: '暂停自动同步',
                    destructive: true,
                    onTap: _busy
                        ? null
                        : () => unawaited(_run(service!.close, label: '正在断开')),
                  ),
                ),
              ],

              // 5. Connection guide
              const SizedBox(height: TpTokens.sectionGap),
              TpCard(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    dividerColor: Colors.transparent,
                  ),
                  child: ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(
                      horizontal: TpTokens.cardPaddingHorizontal,
                    ),
                    shape: const Border(),
                    collapsedShape: const Border(),
                    leading: Icon(
                      TpIcons.help,
                      size: TpTokens.iconM,
                      color: colors.brandInk,
                    ),
                    title: Text(
                      '连接帮助',
                      style: TpTypography.itemTitle(colors).copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    children: [
                      const _GuideStep(
                        number: '1',
                        title: '在运动健康中配对',
                        detail: '开启蓝牙，确认手表显示已连接。',
                      ),
                      const _GuideStep(
                        number: '2',
                        title: '打开手表上的 TechPie',
                        detail: '打开应用后自动同步，断连时使用已保存的数据。',
                      ),
                      const _GuideStep(
                        number: '3',
                        title: '登录并授权手机 TechPie',
                        detail: '点击“授权并查找手表”，选择你的手表。',
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space2,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space4,
                        ),
                        child: Text(
                          '课表和待办可离线查看。校园码由已连接的手机联网获取。',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              if (kDebugMode) ...[
                const SizedBox(height: TpTokens.space3),
                TpCard(
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      dividerColor: Colors.transparent,
                    ),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: TpTokens.cardPaddingHorizontal,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(
                        TpTokens.cardPaddingHorizontal,
                        0,
                        TpTokens.cardPaddingHorizontal,
                        TpTokens.space4,
                      ),
                      shape: const Border(),
                      collapsedShape: const Border(),
                      title: Text(
                        '开发连接配置',
                        style: TpTypography.itemTitle(colors).copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
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
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
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
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.cardPaddingHorizontal,
        vertical: TpTokens.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colors.brandSoft,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: TpTypography.badge(colors.brandInk),
            ),
          ),
          const SizedBox(width: TpTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TpTypography.itemTitle(colors).copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(detail, style: TpTypography.itemMeta(colors)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
