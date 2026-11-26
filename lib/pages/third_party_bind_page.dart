import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_account_setup.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_area.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/design_system/design_system.dart';
import 'ids_bind_page.dart';

enum _SetupStep { courses, site, credentials, renewal, connected }

enum _SignInFailure { service, connection }

class ThirdPartyBindPage extends StatefulWidget {
  final ThirdPartyPlatform platform;

  const ThirdPartyBindPage({super.key, required this.platform});

  @override
  State<ThirdPartyBindPage> createState() => _ThirdPartyBindPageState();
}

class _ThirdPartyBindPageState extends State<ThirdPartyBindPage> with WidgetsBindingObserver {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hydroOriginCtrl = TextEditingController(
    text: 'https://acm.shanghaitech.edu.cn',
  );
  final _hydroDomainsCtrl = TextEditingController();
  late _SetupStep _step;
  bool _busy = false;
  bool _autoRenew = false;
  String? _inlineError;
  _SignInFailure? _signInFailure;

  bool get _isHydro => widget.platform == ThirdPartyPlatform.hydro;
  bool get _isGradescope => widget.platform == ThirdPartyPlatform.gradescope;
  String get _name => widget.platform.label;
  String _text(String en, String zh) =>
      View.of(context).platformDispatcher.locale.languageCode == 'zh' ? zh : en;
  String get _identityLabel => _isGradescope ? _text('Email', '邮箱') : _text('Username', '用户名');
  List<String> get _domains => _hydroDomainsCtrl.text
      .split(RegExp(r'[\s,，]+'))
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();

  String? get _signInMessage => switch (_signInFailure) {
        _SignInFailure.service => _text(
            'Could not sign in to $_name. Please try again.',
            '无法登录 $_name，请重试。',
          ),
        _SignInFailure.connection => _text(
            'Could not connect. Check your connection and try again.',
            '无法连接。请检查网络后重试。',
          ),
        null => null,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _step = _isHydro ? _SetupStep.courses : _SetupStep.credentials;
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _hydroOriginCtrl.dispose();
    _hydroDomainsCtrl.dispose();
    super.dispose();
  }

  Future<void> _dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
  }

  void _go(_SetupStep step) {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _step = step;
      _inlineError = null;
    });
  }

  void _back() {
    if (_busy) return;
    switch (_step) {
      case _SetupStep.site:
        _go(_SetupStep.courses);
      case _SetupStep.renewal:
        _go(_SetupStep.credentials);
      case _SetupStep.credentials when _isHydro:
        _go(_SetupStep.courses);
      default:
        unawaited(maybePopAdaptivePage<void>(context));
    }
  }

  bool get _canLeave =>
      !_busy &&
      (_step == _SetupStep.connected ||
          _step == _SetupStep.courses ||
          (!_isHydro && _step == _SetupStep.credentials));

  bool _validateSite() {
    final uri = Uri.tryParse(_hydroOriginCtrl.text.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        !['https', 'http'].contains(uri.scheme) ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      setState(
        () => _inlineError = _text(
          'Enter a site address such as https://acm.shanghaitech.edu.cn.',
          '请输入站点地址，例如 https://acm.shanghaitech.edu.cn。',
        ),
      );
      return false;
    }
    _hydroOriginCtrl.text = uri.origin;
    return true;
  }

  void _continueCourses() {
    if (_domains.isEmpty) {
      setState(() => _inlineError = _text('Enter at least one course domain.', '请至少输入一个课程域。'));
      return;
    }
    if (!_validateSite()) {
      setState(() => _step = _SetupStep.site);
      return;
    }
    _go(_SetupStep.credentials);
  }

  void _setRenewal(bool enabled) {
    setState(() => _autoRenew = enabled);
    _go(_SetupStep.credentials);
  }

  Future<void> _submit() async {
    if (_busy || _step != _SetupStep.credentials) return;
    String? error;
    if (_accountCtrl.text.trim().isEmpty) {
      error = _text('Enter your ${_isGradescope ? 'email' : 'username'}.', '请填写$_identityLabel。');
    } else if (_passwordCtrl.text.isEmpty) {
      error = _text('Enter your password.', '请填写密码。');
    }
    setState(() {
      _inlineError = error;
      _signInFailure = null;
    });
    if (error != null) return;
    // Lock navigation and submission before waiting for the keyboard channel.
    setState(() => _busy = true);
    try {
      await _dismissKeyboard();
      if (!mounted) return;
      await ServiceProvider.of(context).thirdPartyAuthService.bind(
            platform: widget.platform,
            account: _accountCtrl.text.trim(),
            password: _passwordCtrl.text,
            hydroOrigin: _isHydro ? _hydroOriginCtrl.text.trim() : null,
            hydroDomains: _isHydro ? _domains : null,
            autoRenew: _autoRenew,
          );
      if (!mounted) return;
      _passwordCtrl.clear();
      _go(_SetupStep.connected);
    } on ThirdPartyBindException {
      if (!mounted) return;
      setState(() => _signInFailure = _SignInFailure.service);
    } catch (_) {
      if (!mounted) return;
      setState(() => _signInFailure = _SignInFailure.connection);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(
    String label,
    TextEditingController controller, {
    bool password = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: TpTypography.itemMeta(context.tpColors)),
        const SizedBox(height: TpTokens.space2),
        AdaptiveTextFieldGroup(
          items: [
            AdaptiveTextFieldGroupItem(
              controller: controller,
              placeholder: label,
              obscureText: password,
              keyboardType: keyboard,
              enabled: !_busy,
              textInputAction: password ? TextInputAction.done : TextInputAction.next,
              onSubmitted: password ? (_) => unawaited(_submit()) : null,
            ),
          ],
        ),
      ],
    );
  }

  Widget _choice(String label, String value, VoidCallback onTap) {
    final colors = context.tpColors;
    return Semantics(
      button: true,
      enabled: !_busy,
      child: TpCard(
        onTap: _busy ? null : onTap,
        padding: const EdgeInsets.all(TpTokens.space4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(label, style: TpTypography.itemMeta(colors)),
            const SizedBox(height: TpTokens.space1),
            Text(value, style: TpTypography.itemTitle(colors).copyWith(color: colors.brand)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.platform == ThirdPartyPlatform.ids) {
      return IdsBindPage(
        legacyAccount: ServiceProvider.of(context).thirdPartyAuthService.idsAccount,
      );
    }
    late String title;
    String? description;
    late IconData icon;
    late String action;
    late VoidCallback onAction;
    String? disclosure;
    Widget? secondary;
    final children = <Widget>[];
    switch (_step) {
      case _SetupStep.courses:
        title = _text('Choose your courses', '选择课程');
        description = _text(
          'Enter the domain IDs from your Hydro course pages. Separate multiple IDs with commas.',
          '输入 Hydro 课程页面中的域 ID。多个 ID 请用逗号分隔。',
        );
        icon = TpIcons.course;
        children.addAll([
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_text('Course domains', '课程域'), style: TpTypography.itemMeta(context.tpColors)),
              const SizedBox(height: TpTokens.space2),
              AdaptiveTextArea(
                controller: _hydroDomainsCtrl,
                placeholder: 'SI100B_2025_Autumn',
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.done,
              ),
            ],
          ),
          _choice(
            _text('Campus site · Change', '校园站点 · 更改'),
            Uri.tryParse(_hydroOriginCtrl.text)?.host ?? _hydroOriginCtrl.text,
            () => _go(_SetupStep.site),
          ),
        ]);
        action = _text('Continue', '继续');
        onAction = _continueCourses;
      case _SetupStep.site:
        title = _text('Change Hydro site', '更改 Hydro 站点');
        description =
            _text('Use the address where you sign in to Hydro.', '输入你平时登录 Hydro 使用的站点地址。');
        icon = TpIcons.globe;
        children.add(
          _field(_text('Site address', '站点地址'), _hydroOriginCtrl, keyboard: TextInputType.url),
        );
        action = _text('Use this site', '使用此站点');
        onAction = () {
          if (_validateSite()) _go(_SetupStep.courses);
        };
      case _SetupStep.credentials:
        title = _text('Connect $_name', '连接 $_name');
        icon = TpIcons.lock;
        children.addAll([
          _field(
            _identityLabel,
            _accountCtrl,
            keyboard: _isGradescope ? TextInputType.emailAddress : TextInputType.text,
          ),
          _field(_text('Password', '密码'), _passwordCtrl, password: true),
          _choice(
            _text('Automatic sign-in', '自动登录'),
            _autoRenew ? _text('On · Change', '已开启 · 更改') : _text('Off · Change', '已关闭 · 更改'),
            () => _go(_SetupStep.renewal),
          ),
        ]);
        disclosure = _text(
          'TechPie sends your credentials to its server to sign in to $_name.',
          'TechPie 会将你的凭据发送到其服务器，用于登录 $_name。',
        );
        action = _signInFailure == null
            ? _text('Connect $_name', '连接 $_name')
            : _text('Try again', '重试');
        onAction = () => unawaited(_submit());
      case _SetupStep.renewal:
        title = _text('Keep your account connected?', '保持账号连接？');
        description = _text(
          'TechPie can sign in again before your session expires.',
          'TechPie 可在会话过期前自动重新登录。',
        );
        icon = TpIcons.refresh;
        children.add(
          TpCard(
            padding: const EdgeInsets.all(TpTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_text('On this device', '在此设备上'),
                    style: TpTypography.cardTitle(context.tpColors),),
                const SizedBox(height: TpTokens.space2),
                Text(
                  _text(
                    'Your username and password are stored in encrypted device storage.',
                    '你的账号和密码会加密保存在此设备上。',
                  ),
                ),
                const SizedBox(height: TpTokens.space4),
                Text(
                  _text('With Cloud sync', '开启云同步时'),
                  style: TpTypography.cardTitle(context.tpColors),
                ),
                const SizedBox(height: TpTokens.space2),
                Text(
                  _text(
                    'An end-to-end encrypted backup includes your password. Your master password unlocks it.',
                    '端到端加密备份将包含你的密码。你可以使用主密码解密。',
                  ),
                ),
              ],
            ),
          ),
        );
        secondary = TextButton(
          onPressed: () => _setRenewal(false),
          child: Text(_text('Keep automatic sign-in off', '关闭自动登录')),
        );
        action = _text('Allow automatic sign-in', '允许自动登录');
        onAction = () => _setRenewal(true);
      case _SetupStep.connected:
        title = _text('$_name connected', '$_name 已连接');
        description =
            _text('You can manage this connection in Linked accounts.', '你可以在“第三方账号”中管理此连接。');
        icon = TpIcons.check;
        children.add(
          TpCard(
            padding: const EdgeInsets.all(TpTokens.space4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(_identityLabel, style: TpTypography.itemMeta(context.tpColors)),
                Text(_accountCtrl.text.trim()),
                if (_isHydro) ...[
                  const SizedBox(height: TpTokens.space4),
                  Text(_text('Course domains', '课程域'),
                      style: TpTypography.itemMeta(context.tpColors),),
                  Text(_domains.join(', ')),
                ],
              ],
            ),
          ),
        );
        action = _text('Done', '完成');
        onAction = () => unawaited(maybePopAdaptivePage<void>(context));
    }
    return PopScope(
      canPop: _canLeave,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AdaptiveAccountSetup(
        title: title,
        description: description,
        icon: icon,
        action: action,
        onAction: onAction,
        onBack: _back,
        backLabel: _text('Back', '返回'),
        loading: _busy,
        error: _inlineError ?? (_step == _SetupStep.credentials ? _signInMessage : null),
        disclosure: disclosure,
        secondary: secondary,
        children: children,
      ),
    );
  }
}
