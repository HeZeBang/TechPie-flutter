import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _phoneController = TextEditingController();
  final _codeController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _sendingSms = false;
  bool _obscurePassword = true;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  Future<void> _sendSms() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty) return;

    setState(() => _sendingSms = true);
    try {
      await ServiceProvider.of(context).authService.sendSmsCode(phone);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('验证码已发送')),
        );
      }
      _startCooldown();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发送失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingSms = false);
    }
  }

  void _startCooldown() {
    setState(() => _cooldown = 60);
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _cooldown--;
        if (_cooldown <= 0) timer.cancel();
      });
    });
  }

  Future<void> _smsLogin() async {
    final phone = _phoneController.text.trim();
    final code = _codeController.text.trim();
    if (phone.isEmpty || code.isEmpty) return;

    try {
      await ServiceProvider.of(context).authService.smsLogin(phone, code);
      if (mounted) {
        ServiceProvider.of(context).scheduleService.fetchAll();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: $e')),
        );
      }
    }
  }

  Future<void> _egateLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();
    if (username.isEmpty || password.isEmpty) return;

    try {
      await ServiceProvider.of(context).authService.egateLogin(username, password);
      if (mounted) {
        ServiceProvider.of(context).scheduleService.fetchAll();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneController.dispose();
    _codeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              // Hero area with tonal surface
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
                      'TechPie',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '登录以访问校园服务',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Login form
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      // Segmented-style tab bar
                      TabBar(
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: colorScheme.secondaryContainer,
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        dividerHeight: 0,
                        labelColor: colorScheme.onSecondaryContainer,
                        unselectedLabelColor: colorScheme.onSurfaceVariant,
                        labelStyle: theme.textTheme.labelLarge,
                        tabs: const [
                          Tab(text: '短信登录'),
                          Tab(text: '统一身份认证'),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: 280,
                        child: TabBarView(
                          children: [
                            _SmsLoginForm(
                              phoneController: _phoneController,
                              codeController: _codeController,
                              cooldown: _cooldown,
                              sendingSms: _sendingSms,
                              onSendSms: _sendSms,
                              onLogin: _smsLogin,
                            ),
                            _EgateLoginForm(
                              usernameController: _usernameController,
                              passwordController: _passwordController,
                              obscurePassword: _obscurePassword,
                              onToggleObscure: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                              onLogin: _egateLogin,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SmsLoginForm extends StatelessWidget {
  final TextEditingController phoneController;
  final TextEditingController codeController;
  final int cooldown;
  final bool sendingSms;
  final VoidCallback onSendSms;
  final VoidCallback onLogin;

  const _SmsLoginForm({
    required this.phoneController,
    required this.codeController,
    required this.cooldown,
    required this.sendingSms,
    required this.onSendSms,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final auth = ServiceProvider.of(context).authService;

    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: phoneController,
            decoration: const InputDecoration(
              labelText: '手机号码',
              prefixIcon: Icon(Icons.phone_outlined),
              filled: true,
              border: UnderlineInputBorder(),
            ),
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: '验证码',
                    prefixIcon: Icon(Icons.pin_outlined),
                    filled: true,
              border: UnderlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.tonal(
                onPressed:
                    (cooldown > 0 || sendingSms) ? null : onSendSms,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(100, 56),
                ),
                child: sendingSms
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(cooldown > 0 ? '${cooldown}s' : '发送验证码'),
              ),
            ],
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: auth.loading ? null : onLogin,
            icon: auth.loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ],
      ),
    );
  }
}

class _EgateLoginForm extends StatelessWidget {
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final VoidCallback onToggleObscure;
  final VoidCallback onLogin;

  const _EgateLoginForm({
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.onToggleObscure,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    final auth = ServiceProvider.of(context).authService;

    return ListenableBuilder(
      listenable: auth,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: usernameController,
            decoration: const InputDecoration(
              labelText: '学号',
              prefixIcon: Icon(Icons.badge_outlined),
              filled: true,
              border: UnderlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passwordController,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock_outline),
              filled: true,
              border: const UnderlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: onToggleObscure,
              ),
            ),
            obscureText: obscurePassword,
          ),
          const SizedBox(height: 32),
          FilledButton.icon(
            onPressed: auth.loading ? null : onLogin,
            icon: auth.loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.login),
            label: const Text('登录'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
        ],
      ),
    );
  }
}
