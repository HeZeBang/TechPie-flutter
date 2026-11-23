import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
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
    final confirmed = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '永久注销账号？',
      message: '将永久删除整个 GeekPieAuth 账号，无法恢复',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false, isDefault: true),
        AdaptiveAlertAction<bool>(
          label: '永久注销',
          value: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted || _busy || _deleted) return;
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
    final colors = context.tpColors;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space4,
    );
    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '注销账号',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '我的',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回我的',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
        ),
        material: () => const BlurredAppBar(title: Text('注销账号')),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          TpTokens.pageHorizontalPadding,
          topInset,
          TpTokens.pageHorizontalPadding,
          AppShellMetrics.bottomContentPaddingOf(context) + TpTokens.space4,
        ),
        children: [
          TpPageBody(
            child: TpCard(
              padding: const EdgeInsets.symmetric(
                horizontal: TpTokens.space5,
                vertical: TpTokens.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: (_deleted
                                ? colors.successGreen
                                : colors.dangerRed)
                            .withValues(alpha: colors.isDark ? 0.18 : 0.10),
                        borderRadius: BorderRadius.circular(TpTokens.radiusM),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        _deleted ? TpIcons.checkCircle : TpIcons.delete,
                        size: 30,
                        color: _deleted ? colors.successGreen : colors.dangerRed,
                      ),
                    ),
                  ),
                  const SizedBox(height: TpTokens.space4),
                  Text(
                    _deleted ? '账号已注销' : '永久注销 GeekPieAuth 账号',
                    style:
                        TpTypography.cardTitle(colors).copyWith(fontSize: 17),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Text(
                    _deleted
                        ? '账号与云备份均已清除，校园账号不受影响。'
                        : '将立即永久删除整个 GeekPieAuth 账号及 TechPie 云备份，无法恢复。其他 GeekPie 服务也将无法使用该账号登录。校园账号不受影响。',
                    style: TpTypography.itemMeta(colors).copyWith(
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: TpTokens.space4),
                    Text(
                      _error!,
                      style: TpTypography.itemMeta(colors).copyWith(
                        color: colors.dangerRed,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (!_deleted) ...[
                    const SizedBox(height: TpTokens.space5),
                    AdaptiveButton(
                      label: '永久注销',
                      icon: TpIcons.delete,
                      sfSymbol: 'person.crop.circle.badge.minus',
                      role: AdaptiveButtonRole.destructive,
                      loading: _busy,
                      height: 46,
                      onPressed: _busy ? null : () => unawaited(_delete()),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
