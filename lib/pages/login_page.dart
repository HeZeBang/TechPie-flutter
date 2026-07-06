import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/schedule_service.dart';
import '../services/service_provider.dart';
import '../services/uni_auth_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';

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

const MethodChannel _nativeGlassPresenterChannel = MethodChannel(
  'techpie/native_glass_presenter',
);

Future<void> presentLoginPage(BuildContext context) async {
  if (isIos() && usesIosLiquidGlass()) {
    final sp = ServiceProvider.of(context);
    await _presentNativeLoginSheet(
      authService: sp.authService,
      uniAuthService: sp.uniAuthService,
      scheduleService: sp.scheduleService,
    );
    return;
  }

  if (context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const LoginPage()),
    );
  }
}

Future<void> _presentNativeLoginSheet({
  required AuthService authService,
  required UniAuthService uniAuthService,
  required ScheduleService scheduleService,
}) async {
  _nativeGlassPresenterChannel.setMethodCallHandler((call) async {
    Future<Map<String, Object?>> runAction(
      Future<void> Function() action,
    ) async {
      try {
        await action();
        return const <String, Object?>{'ok': true};
      } catch (error) {
        return <String, Object?>{'ok': false, 'message': '$error'};
      }
    }

    switch (call.method) {
      case 'nativeLoginSheet.geekpieLogin':
        return runAction(() async {
          // The SDK manages its own WebView — no BuildContext needed.
          final jwt = await uniAuthService.loginSdkOnly();
          await authService.geekpieLogin(jwt);
          unawaited(scheduleService.fetchAll());
        });
      default:
        throw MissingPluginException(
          'Unknown login sheet action ${call.method}',
        );
    }
  });

  try {
    await _nativeGlassPresenterChannel.invokeMethod<void>(
      'presentLoginSheet',
      <String, Object?>{
        'pageTitle': _loginPageCopy.pageTitle,
        'brandName': _loginPageCopy.brandName,
        'subtitle': _loginPageCopy.subtitle,
      },
    );
  } finally {
    _nativeGlassPresenterChannel.setMethodCallHandler(null);
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
      final jwt = await sp.uniAuthService.login(context);
      await sp.authService.geekpieLogin(jwt);
      if (mounted) {
        unawaited(sp.scheduleService.fetchAll());
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        if (isIos()) {
          setState(() => _inlineMessage = '登录失败：$e');
        } else {
          showAdaptiveFeedback(
            context: context,
            message: '登录失败: $e',
            style: AdaptiveFeedbackStyle.error,
          );
        }
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
            unawaited(Navigator.maybePop(context));
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
            FilledButton(
              onPressed: _loading ? null : _geekpieLogin,
              child: SizedBox(
                height: liquidGlass ? 56 : 52,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_loading) ...[
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    const Text('通过 GeekPie Uni-Auth 登录'),
                  ],
                ),
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
