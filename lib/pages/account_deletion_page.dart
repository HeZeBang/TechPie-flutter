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
  AccountDeletionRequest? _request;
  bool _busy = true;
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userId = widget.auth.session?.userId ?? '';
    unawaited(_load());
  }

  Future<void> _load({bool submit = false}) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = submit
          ? await widget.auth.submitAccountDeletionRequest(expectedUserId: _userId)
          : await widget.auth.getAccountDeletionRequest(expectedUserId: _userId);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loaded = true;
      });
    } on AccountDeletionRequestException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loaded = false;
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
    final request = _request;
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
          if (request == null) ...[
            Text('注销整个 GeekPieAuth 账号', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            const Text(
                '注销将永久删除 GeekPieAuth 统一账号及 TechPie 云备份，并影响使用该账号登录的其他 GeekPie 服务。学校及其他第三方平台的账号不会因此注销。',
            ),
            const SizedBox(height: 12),
            const Text('确认后直接提交申请，由管理员在 7 个工作日内完成删除，并通过账号登记的邮箱通知结果。无需另行发送邮件。'),
            const SizedBox(height: 12),
            const Text('提交申请不会立即退出登录。删除完成前仍可在此查看受理记录。'),
          ] else ...[
            Text(
              request.completed ? '注销已处理完成' : '注销申请已受理',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            SelectableText('申请编号：${request.id}'),
            const SizedBox(height: 8),
            Text('申请时间：${request.requestedAt.toLocal().toString().split('.').first}'),
            const SizedBox(height: 12),
            Text(
              request.completed
                  ? '管理员已完成账号与数据删除，结果将通过账号登记的邮箱通知。'
                  : '管理员将在申请后 7 个工作日内完成账号与数据删除，并通过账号登记的邮箱通知结果。无需再次提交或发送邮件。',
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          if (_loaded && request == null)
            AdaptiveButton(
              label: '确认提交注销申请',
              icon: Icons.person_remove_outlined,
              sfSymbol: 'person.crop.circle.badge.minus',
              role: AdaptiveButtonRole.destructive,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_load(submit: true)),
            ),
          if (!_loaded || request != null)
            AdaptiveButton(
              label: '刷新申请状态',
              icon: Icons.refresh,
              sfSymbol: 'arrow.clockwise',
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_load()),
            ),
        ],
      ),
    );
  }
}
