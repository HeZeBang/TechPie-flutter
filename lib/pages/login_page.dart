import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageCopy {
  const _LoginPageCopy({
    required this.pageTitle,
    required this.brandName,
    required this.subtitle,
  });

  final String pageTitle;
  final String brandName;
  final String subtitle;
}

const _loginPageCopy = _LoginPageCopy(
  pageTitle: '登录',
  brandName: 'TechPie',
  subtitle: '登录以访问校园服务',
);

Future<void> presentLoginPage(BuildContext context) async {
  if (context.mounted) {
    await pushAdaptivePage<void>(context, builder: (_) => const LoginPage());
  }
}

class _LoginPageState extends State<LoginPage> {
  bool _loading = false;
  String? _inlineMessage;

  Future<void> _geekpieLogin() async {
    setState(() {
      _loading = true;
      _inlineMessage = null;
    });

    try {
      final sp = ServiceProvider.of(context);
      final login = isIos() && usesIosLiquidGlass()
          ? sp.uniAuthService.loginSdkOnly()
          : sp.uniAuthService.login(context);
      final tokens = await login;
      await sp.authService.geekpieLogin(tokens);
      sp.scheduleService.requestFetch(force: true);
      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _inlineMessage = '登录失败：$e');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const copy = _loginPageCopy;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: isIos()
          ? IosNativeNavigationBar(
              title: copy.pageTitle,
              leadingItems: [
                if (Navigator.canPop(context))
                  const IosNativeNavigationBarItem(
                    id: 'back',
                    sfSymbol: 'chevron.left',
                    accessibilityLabel: '返回',
                  ),
              ],
              onItemPressed: (_) => maybePopAdaptivePage<void>(context),
            )
          : AppBar(
              title: Text(copy.pageTitle),
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              elevation: 0,
            ),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Hero area
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
                decoration: BoxDecoration(
                  color: isIos() ? theme.scaffoldBackgroundColor : colorScheme.primaryContainer,
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(28),
                    bottomRight: Radius.circular(28),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.school_rounded,
                      size: 64,
                      color: isIos() ? colorScheme.primary : colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      copy.brandName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: isIos() ? colorScheme.onSurface : colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            isIos() ? colorScheme.onSurfaceVariant : colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Single login button
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (_inlineMessage != null) ...[
                      _InlineFormFeedback(message: _inlineMessage!),
                      const SizedBox(height: 16),
                    ],
                    if (isIos())
                      CNButton(
                        label: _loading ? '正在登录…' : '通过 GeekPie Uni-Auth 登录',
                        onPressed: _loading ? null : _geekpieLogin,
                        enabled: !_loading,
                        semanticLabel: _loading ? '正在登录，请稍候' : '通过 GeekPie Uni-Auth 登录',
                        tint: colorScheme.primary,
                        config: const CNButtonConfig(
                          style: CNButtonStyle.prominentGlass,
                          minHeight: 56,
                        ),
                      )
                    else
                      FilledButton.icon(
                        onPressed: _loading ? null : _geekpieLogin,
                        icon: _loading
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.login),
                        label: const Text('通过 GeekPie Uni-Auth 登录'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(56),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineFormFeedback extends StatelessWidget {
  const _InlineFormFeedback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.info_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onErrorContainer,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
