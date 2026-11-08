import 'dart:async';

import 'package:flutter/material.dart';

import '../models/account_deletion_request.dart';
import '../services/auth_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class AccountDeletionPage extends StatefulWidget {
  const AccountDeletionPage({super.key, required this.auth});
  final AuthService auth;

  @override
  State<AccountDeletionPage> createState() => _AccountDeletionPageState();
}

class _AccountDeletionPageState extends State<AccountDeletionPage> {
  late final String _userId;
  bool _submitted = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userId = widget.auth.session?.userId ?? '';
  }

  Future<void> _submit() async {
    if (_busy || _submitted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.submitAccountDeletionRequest(expectedUserId: _userId);
      if (!mounted) return;
      setState(() => _submitted = true);
    } on AccountDeletionRequestException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
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
              title: '申请注销账号',
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
          : const BlurredAppBar(title: Text('申请注销账号')),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          20,
          topInset + 20,
          20,
          AppShellMetrics.bottomContentPaddingOf(context) + 20,
        ),
        children: [
          const SizedBox(height: 40),
          Icon(
            _submitted ? Icons.check_circle_outline : Icons.person_remove_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 24),
          Text(
            _submitted
                ? '注销申请已提交。将在 7 个工作日内处理，结果通过登记邮箱通知。'
                : '注销将永久删除 GeekPieAuth 账号及 TechPie 云备份，影响其他 GeekPie 服务。校园账号不受影响。\n\n7 个工作日内人工处理，结果通过登记邮箱通知。',
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          if (!_submitted)
            AdaptiveButton(
              label: '确认提交注销申请',
              icon: Icons.person_remove_outlined,
              sfSymbol: 'person.crop.circle.badge.minus',
              role: AdaptiveButtonRole.destructive,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_submit()),
            ),
        ],
      ),
    );
  }
}
