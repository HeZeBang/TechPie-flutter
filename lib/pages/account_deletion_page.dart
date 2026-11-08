import 'dart:async';

import 'package:flutter/material.dart';

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
  bool _deleted = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _userId = widget.auth.session?.userId ?? '';
  }

  Future<void> _delete() async {
    if (_busy || _deleted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.auth.deleteAccount(expectedUserId: _userId);
      if (!mounted) return;
      setState(() => _deleted = true);
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
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
              title: '注销账号',
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
          : const BlurredAppBar(title: Text('注销账号')),
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
            _deleted ? Icons.check_circle_outline : Icons.person_remove_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 24),
          Text(
            _deleted
                ? '账号已注销。'
                : '将立即永久删除整个 GeekPieAuth 账号及 TechPie 云备份，无法恢复。其他 GeekPie 服务也将无法使用该账号登录。校园账号不受影响。',
            textAlign: TextAlign.center,
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          if (!_deleted)
            AdaptiveButton(
              label: '永久注销',
              icon: Icons.person_remove_outlined,
              sfSymbol: 'person.crop.circle.badge.minus',
              role: AdaptiveButtonRole.destructive,
              loading: _busy,
              onPressed: _busy ? null : () => unawaited(_delete()),
            ),
        ],
      ),
    );
  }
}
