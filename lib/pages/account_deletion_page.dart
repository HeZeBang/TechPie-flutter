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
          if (!_submitted) ...[
            Text('注销整个 GeekPieAuth 账号', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
                '注销将永久删除 GeekPieAuth 统一账号及 TechPie 云备份，并影响使用该账号登录的其他 GeekPie 服务。学校及其他第三方平台的账号不会因此注销。',
            ),
            const SizedBox(height: 12),
            const Text('确认后直接提交申请，由管理员在 7 个工作日内完成删除，并通过账号登记的邮箱通知结果。无需另行发送邮件。'),
            const SizedBox(height: 12),
            const Text('提交申请不会立即退出登录。提交成功后无需重复申请，处理结果将通过邮箱通知。'),
          ] else ...[
            Text('注销申请已提交', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text('管理员将在 7 个工作日内完成账号与数据删除，并通过账号登记的邮箱通知结果。无需再次提交或发送邮件。'),
          ],
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
