import 'dart:async';

import 'package:flutter/material.dart';

import '../services/feedback_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, required this.service});
  final FeedbackService service;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  final _message = TextEditingController();
  final _contact = TextEditingController();
  bool _includeUsername = false;
  bool _includeEmail = false;
  bool _busy = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    _contact.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _sent) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.service.submit(
        _message.text,
        includeUsername: _includeUsername,
        includeEmail: _includeEmail,
        contact: _contact.text,
      );
      if (mounted) setState(() => _sent = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error is TimeoutException
              ? '未能确认送达，内容已保留，请稍后再试'
              : error is Exception && error.toString().startsWith('Exception: ')
                  ? error.toString().substring(11)
                  : '反馈未发送成功，内容已保留';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final useIosChrome = isIos();
    final topInset = useIosChrome || usesLegacyIosChrome()
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !usesLegacyIosChrome(),
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: '问题反馈 / 功能建议',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Settings',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Settings',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
            )
          : const BlurredAppBar(title: Text('问题反馈 / 功能建议')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset + 20,
          20,
          AppShellMetrics.bottomContentPaddingOf(context) + 20,
        ),
        children: _sent
            ? const [
                SizedBox(height: 40),
                Icon(Icons.check_circle_outline, size: 64),
                SizedBox(height: 20),
                Text('反馈已发送', textAlign: TextAlign.center),
              ]
            : [
                TextField(
                  controller: _message,
                  enabled: !_busy,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText: '描述问题或建议',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  title: const Text('发送用户名'),
                  value: _includeUsername,
                  onChanged: _busy ? null : (value) => setState(() => _includeUsername = value!),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                CheckboxListTile(
                  title: const Text('发送邮箱'),
                  value: _includeEmail,
                  onChanged: _busy ? null : (value) => setState(() => _includeEmail = value!),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(
                  controller: _contact,
                  enabled: !_busy,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: '补充联系方式（选填）',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('自动附带 App 版本和平台。'),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                AdaptiveButton(
                  label: '提交反馈',
                  icon: Icons.send_outlined,
                  sfSymbol: 'paperplane',
                  role: AdaptiveButtonRole.prominent,
                  loading: _busy,
                  onPressed: _busy ? null : () => unawaited(_submit()),
                ),
              ],
      ),
    );
  }
}
