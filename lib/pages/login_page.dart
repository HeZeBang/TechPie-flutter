import 'dart:async';

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
  if (isIos() && usesIosLiquidGlass()) {
    await CNBottomSheet.showCupertino<void>(
      context: context,
      pageBuilder: (_) => const LoginPage(),
    );
  } else if (context.mounted) {
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
    if (isIos()) {
      return _buildIosLoginPage(context, copy);
    }
    return _buildMaterialLoginPage(context, copy);
  }

  Widget _buildMaterialLoginPage(BuildContext context, _LoginPageCopy copy) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
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
                  color: colorScheme.primaryContainer,
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
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      copy.brandName,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      copy.subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
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

  Widget _buildIosLoginPage(BuildContext context, _LoginPageCopy copy) {
    final theme = Theme.of(context);
    final canPop = Navigator.canPop(context);
    final liquidGlass = usesIosLiquidGlass();

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: IosNativeNavigationBar(
        title: copy.pageTitle,
        leadingItems: [
          if (canPop)
            const IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
            ),
        ],
        onItemPressed: (id) {
          if (id == 'back') {
            unawaited(maybePopAdaptivePage<void>(context));
          }
        },
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(20, liquidGlass ? 4 : 12, 20, 28),
          children: [
            _IosLoginHeader(copy: copy, liquidGlass: liquidGlass),
            SizedBox(height: liquidGlass ? 40 : 36),
            if (_inlineMessage != null) ...[
              _IosInlineFeedback(message: _inlineMessage!),
              const SizedBox(height: 16),
            ],
            CNButton(
              label: _loading ? '正在登录…' : '通过 GeekPie Uni-Auth 登录',
              onPressed: _loading ? null : _geekpieLogin,
              enabled: !_loading,
              semanticLabel: _loading ? '正在登录，请稍候' : '通过 GeekPie Uni-Auth 登录',
              tint: theme.colorScheme.primary,
              config: CNButtonConfig(
                style: CNButtonStyle.prominentGlass,
                minHeight: liquidGlass ? 56 : 52,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IosLoginHeader extends StatelessWidget {
  const _IosLoginHeader({
    required this.copy,
    required this.liquidGlass,
  });

  final _LoginPageCopy copy;
  final bool liquidGlass;

  @override
  Widget build(BuildContext context) {
    final labelColor = Theme.of(context).colorScheme.onSurfaceVariant;

    return Padding(
      padding: EdgeInsets.only(
        left: 2,
        right: 2,
        top: liquidGlass ? 0 : 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            copy.brandName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            copy.subtitle,
            style: TextStyle(
              color: labelColor,
              fontSize: liquidGlass ? 17 : 15,
              height: 1.25,
              letterSpacing: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _IosInlineFeedback extends StatelessWidget {
  const _IosInlineFeedback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final red = scheme.error;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline, size: 18, color: red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: red,
                  fontSize: 14,
                  height: 1.25,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
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
