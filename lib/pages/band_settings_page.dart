import 'dart:async';

import 'package:flutter/material.dart';

import '../models/wearable_device.dart';
import '../services/band_service.dart';
import '../theme/tp_icons.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';

class BandSettingsPage extends StatefulWidget {
  const BandSettingsPage({super.key, required this.device});

  final WearableDevice device;

  @override
  State<BandSettingsPage> createState() => _BandSettingsPageState();
}

class _BandSettingsPageState extends State<BandSettingsPage> with WidgetsBindingObserver {
  final BandService _band = BandService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_band.start());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    unawaited(_band.refresh());
    if (_band.reminderEnabled) {
      unawaited(_band.rescheduleReminders());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: BlurredAppBar(title: Text(widget.device.name)),
      body: ListenableBuilder(
        listenable: _band,
        builder: (context, _) {
          if (!matchesConnectedNode(widget.device, _band.nodeName)) {
            return _buildDisconnected(_band.nodeName);
          }
          return ListView(
            padding: const EdgeInsets.only(top: kToolbarHeight + 48),
            children: [
              _statusTile(
                icon: TpIcons.linkedAccounts,
                title: '穿戴服务',
                value: _band.serviceConnected ? '已连接小米运动健康' : '未连接',
                ok: _band.serviceConnected,
              ),
              _statusTile(
                icon: TpIcons.watch,
                title: '手环',
                value: _band.nodeName ?? (_band.hasDevice ? '已发现' : '未发现，请先在小米运动健康中连接'),
                ok: _band.hasDevice,
              ),
              _statusTile(
                icon: TpIcons.privacy,
                title: '通信授权',
                value: _band.permissionGranted ? '已授权' : '未授权',
                ok: _band.permissionGranted,
              ),
              _statusTile(
                icon: TpIcons.activities,
                title: '手环应用',
                value: switch (_band.wearAppInstalled) {
                  true => '已安装',
                  false => '未安装，请用 AstroBox 侧载 rpk',
                  null => '未知',
                },
                ok: _band.wearAppInstalled == true,
              ),
              _statusTile(
                icon: TpIcons.sync,
                title: '最近通信',
                value: _lastActiveText(),
                ok: _linkAlive,
              ),
              if (_band.lastError != null)
                ListTile(
                  leading: const Icon(TpIcons.alertCircle, color: Colors.red),
                  title: const Text('最近错误'),
                  subtitle: Text(_band.lastError!),
                ),
              const Divider(),
              ListTile(
                leading: const Icon(TpIcons.refresh),
                title: const Text('刷新状态'),
                onTap: () => unawaited(_run(_band.refresh, () => '状态已刷新')),
              ),
              ListTile(
                leading: const Icon(TpIcons.lock),
                title: const Text('申请授权'),
                subtitle: const Text('首次使用需要在小米运动健康中允许设备管理'),
                onTap: () => unawaited(
                  _run(
                    _band.requestPermission,
                    () => _band.permissionGranted ? '已授权，无需重复操作' : '授权完成',
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(TpIcons.externalLink),
                title: const Text('发送测试消息'),
                subtitle: const Text('手环应用打开后，应在屏幕上回显 pong'),
                onTap: () => unawaited(_run(_band.sendTest, () => '已发送测试消息')),
              ),
              SwitchListTile(
                secondary: const Icon(TpIcons.qrCode),
                title: const Text('同步离线支付凭证'),
                subtitle: const Text('下发私钥，手环即可离线生成消费码'),
                value: _band.offlineCredEnabled,
                onChanged: _toggleOfflineCredential,
              ),
              const Divider(),
              SwitchListTile(
                secondary: const Icon(TpIcons.bellRing),
                title: const Text('上课提醒'),
                subtitle: const Text('通过手环通知提醒，无需打开手环应用'),
                value: _band.reminderEnabled,
                onChanged: (value) => unawaited(_band.setReminderEnabled(value)),
              ),
              ListTile(
                leading: const Icon(TpIcons.clock),
                title: const Text('提前时间'),
                subtitle: Text('${_band.reminderLeadMinutes} 分钟'),
                enabled: _band.reminderEnabled,
                onTap: _pickLeadMinutes,
              ),
              SwitchListTile(
                secondary: const Icon(TpIcons.document),
                title: const Text('作业提醒'),
                subtitle: const Text('作业/考试截止前一天提醒'),
                value: _band.assignmentReminderEnabled,
                onChanged: (value) => unawaited(_band.setAssignmentReminderEnabled(value)),
              ),
              if (_band.reminderEnabled && !_band.exactAlarms)
                ListTile(
                  leading: const Icon(TpIcons.clock, color: Colors.orange),
                  title: const Text('允许精确提醒'),
                  subtitle: const Text('未授权精确闹钟，提醒可能延迟；点此去系统设置'),
                  onTap: () => unawaited(_band.requestExactAlarmPermission()),
                ),
              if (_band.reminderEnabled)
                ListTile(
                  leading: Icon(
                    (_band.lastReminder?.startsWith('已送达') ?? false)
                        ? TpIcons.checkCircle
                        : TpIcons.alertCircle,
                    color: (_band.lastReminder?.startsWith('已送达') ?? false)
                        ? Colors.green
                        : Colors.orange,
                  ),
                  title: const Text('上次提醒投递'),
                  subtitle: Text(_lastReminderText()),
                ),
              ListTile(
                leading: const Icon(TpIcons.bellRing),
                title: const Text('发送测试通知'),
                subtitle: const Text('手环应立即震动并显示通知'),
                onTap: () => unawaited(
                  _run(_band.sendTestNotification, () => '已发送测试通知'),
                ),
              ),
              const Divider(),
              const ListTile(
                leading: Icon(TpIcons.info),
                title: Text('使用前提'),
                subtitle: Text(
                  '1. 手环通过小米运动健康连接手机\n'
                  '2. 手环上已安装 TechPie 快应用（包名/签名与手机 App 一致）\n'
                  '3. 手环快应用打开时才能收发消息',
                ),
              ),
              if (_band.messages.isNotEmpty) ...[
                const Divider(),
                const ListTile(
                  leading: Icon(TpIcons.feedback),
                  title: Text('最近消息'),
                ),
                for (final message in _band.messages.take(8))
                  ListTile(
                    dense: true,
                    title: Text(
                      message,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// 该条目不是当前连接的设备：只显示围栏说明，不暴露任何控制项。
  Widget _buildDisconnected(String? node) {
    return ListView(
      padding: const EdgeInsets.only(top: kToolbarHeight + 48),
      children: [
        ListTile(
          leading: const Icon(TpIcons.unlink),
          title: Text('${widget.device.name} 未连接'),
          subtitle: Text(
            node == null || node.isEmpty ? '请先在小米运动健康中连接该设备' : '当前连接的是 $node；请在小米运动健康中切换到该设备后再管理',
          ),
        ),
        ListTile(
          leading: const Icon(TpIcons.refresh),
          title: const Text('刷新状态'),
          onTap: () async {
            await _band.refresh();
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _statusTile({
    required IconData icon,
    required String title,
    required String value,
    required bool ok,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: Icon(
        ok ? TpIcons.checkCircle : TpIcons.close,
        color: ok ? Colors.green : Colors.grey,
      ),
    );
  }

  static const _linkWindow = Duration(minutes: 5);

  int? get _lastActiveAt => _band.lastPongAt ?? _band.lastMessageAt;

  bool get _linkAlive {
    final at = _lastActiveAt;
    if (at == null) return false;
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    return elapsed < _linkWindow;
  }

  String _lastActiveText() {
    final at = _lastActiveAt;
    if (at == null) return '暂无消息，打开手环应用并点「同步」';
    final elapsed = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(at),
    );
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds} 秒前';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} 分钟前';
    return '${elapsed.inHours} 小时前';
  }

  /// 上一次上课提醒有没有推到手腕：手机响、手环静时，这一行是判断依据。
  String _lastReminderText() {
    final at = _band.lastReminderAt;
    final text = _band.lastReminder;
    if (at == null || text == null) return '还没有触发过提醒';
    final time = DateTime.fromMillisecondsSinceEpoch(at);
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$hh:$mm · $text';
  }

  Future<void> _pickLeadMinutes() async {
    const options = [5, 10, 15, 20, 30];
    final value = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('提前多久提醒'),
        children: [
          for (final minutes in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(minutes),
              child: Text('$minutes 分钟'),
            ),
        ],
      ),
    );
    if (value != null) {
      await _band.setReminderLeadMinutes(value);
    }
  }

  Future<void> _toggleOfflineCredential(bool value) async {
    if (!value) {
      await _band.setOfflineCredEnabled(false);
      await _run(
        _band.clearOfflineCredential,
        () => '已清除手环上的离线凭证',
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('同步离线支付凭证？'),
        content: const Text(
          '将把离线消费码签名私钥通过穿戴通道下发到手环，并保存在手环本地。\n\n'
          '· 需使用支持离线码协议的手环应用；仓库内示例页面仅供连接诊断\n'
          '· 手环本地签名不占用手机的一次一码配额\n'
          '· 私钥仅用于消费码签名，但手环丢失时请尽快在手机上续期或重置离线授权\n\n'
          '仅在你本人的手环上继续。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认下发'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _band.setOfflineCredEnabled(true);
    await _run(
      _band.pushOfflineCredential,
      () => '凭证消息已发送；需支持离线码协议的手环应用接收',
    );
  }

  Future<void> _run(Future<void> Function() action, String Function() okMessage) async {
    await action();
    if (!mounted) return;
    final error = _band.lastError;
    showAdaptiveFeedback(
      context: context,
      message: error == null ? okMessage() : '出错：$error',
      style: error == null ? AdaptiveFeedbackStyle.success : AdaptiveFeedbackStyle.error,
      duration: const Duration(seconds: 2),
    );
  }
}
