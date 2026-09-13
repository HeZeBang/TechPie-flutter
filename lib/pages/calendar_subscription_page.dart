import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/calendar_subscription_service.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import 'login_page.dart';

class CalendarSubscriptionPage extends StatefulWidget {
  const CalendarSubscriptionPage({super.key});
  @override
  State<CalendarSubscriptionPage> createState() =>
      _CalendarSubscriptionPageState();
}

class _CalendarSubscriptionPageState extends State<CalendarSubscriptionPage> {
  CalendarSubscriptionService? _service;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_service != null) return;
    _service = ServiceProvider.of(context).calendarSubscriptionService;
    unawaited(_act(_service!.reload));
  }

  Future<void> _act(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {/* The service exposes the failure. */}
  }

  Future<void> _publish() async {
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: _service!.enabled ? '更新为当前课表？' : '开启课表订阅？',
      message: '服务器会保存当前学期的日历内容。此后 App 成功同步同一校园账号、同一学期的课表时，会更新订阅。'
          '校园登录凭据不会随订阅上传。每个 TechPie 主账号保留一个订阅，持有链接的人可以读取课表。',
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '确认', value: true, isDefault: true),
      ],
    );
    if (confirmed == true) await _act(_service!.publish);
  }

  Future<void> _revoke() async {
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '撤销课表订阅？',
      message: '原链接将失效。日历 App 已保存的日程需要在日历 App 中删除。',
      actions: const [
        AdaptiveAlertAction(label: '取消', value: false),
        AdaptiveAlertAction(label: '撤销', value: true, isDestructive: true),
      ],
    );
    if (confirmed == true) await _act(_service!.revoke);
  }

  @override
  Widget build(BuildContext context) {
    final service = _service!;
    return Scaffold(
      appBar: AppBar(title: const Text('课表订阅')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text('日历 App 定期读取订阅链接；只有 TechPie 成功同步课表后，链接内容才会更新。'
                '更新频率由日历 App 决定。180 天没有更新，链接自动失效。'),
            const SizedBox(height: 20),
            if (service.busy) const LinearProgressIndicator(),
            if (service.error != null) ...[
              Text(service.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),),
              TextButton(
                  onPressed: service.busy
                      ? null
                      : () => unawaited(_act(service.reload)),
                  child: const Text('重新加载'),),
              TextButton(
                onPressed: service.busy
                    ? null
                    : () async {
                        await presentLoginPage(context);
                        if (mounted) await _act(service.reload);
                      },
                child: const Text('登录 TechPie 主账号'),
              ),
            ],
            if (service.enabled) ...[
              Text('上次上传：${service.updatedAt ?? "未知"}'),
              Text('有效期至：${service.expiresAt ?? "未知"}'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('复制订阅链接'),
                onPressed: service.busy
                    ? null
                    : () async {
                        await Clipboard.setData(
                            ClipboardData(text: service.url!.toString()),);
                        if (!context.mounted) return;
                        showAdaptiveFeedback(
                            context: context, message: '订阅链接已复制',);
                      },
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.calendar_month),
                label: const Text('在日历 App 中订阅'),
                onPressed: service.busy
                    ? null
                    : () async {
                        final opened = await launchUrl(
                            service.url!.replace(scheme: 'webcal'),
                            mode: LaunchMode.externalApplication,);
                        if (!opened && context.mounted) {
                          showAdaptiveFeedback(
                              context: context, message: '请复制链接，在日历 App 中添加订阅',);
                        }
                      },
              ),
            ],
            FilledButton(
              onPressed: service.busy ? null : _publish,
              child: Text(service.enabled ? '更新为当前课表' : '开启订阅'),
            ),
            if (service.enabled)
              TextButton(
                  onPressed: service.busy ? null : _revoke,
                  child: const Text('撤销订阅'),),
          ],
        ),
      ),
    );
  }
}
