import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/third_party_account.dart';
import '../services/ids/ids_client.dart' show IdsCaptchaRefresh, IdsVerificationAnswer;
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/secure_password_field.dart';

final idsAccountSecurityUrl = Uri.parse(
  'https://ids.shanghaitech.edu.cn/personalInfo/personCenter/index.html#/accountsecurity',
);
const idsPasskeyNotice =
    '您可以在 IDS 账号安全页面查看已创建的 Passkey，并随时解绑。解绑后，需要在 TechPie 重新绑定，才能继续使用 IDS 相关功能。';

String _text(BuildContext context, String en, String zh) =>
    View.of(context).platformDispatcher.locale.languageCode == 'zh' ? zh : en;

String _bindingError(BuildContext context, Object error) {
  final message = error.toString();
  if (error is String && !RegExp(r'[\u3400-\u9fff]').hasMatch(message)) return message;
  const translations = {
    'IDS 账号或密码错误，请重新输入': 'Incorrect account or password. Try again.',
    'IDS 账号已锁定，请在学校 IDS 处理后重试': 'Your IDS account is locked. Resolve this in IDS, then try again.',
    'IDS 登录失败，请检查学校账号状态后重试': 'Sign-in failed. Check your IDS account and try again.',
    '请填写 IDS 账号和密码': 'Enter your IDS account and password.',
    '请输入验证码': 'Enter the verification code.',
    '获取验证码失败，请重试': 'Could not load the image. Try again.',
    '验证码错误，请重试': 'That code didn’t match. Try again.',
    'IDS 要求额外身份验证，请先在学校账号安全页面处理':
        'Complete the extra identity check in IDS Account Security, then try again.',
    'IDS 登录页面已变化或要求修改密码，请先到学校网站处理':
        'Visit IDS to check your account or update your password, then try again.',
    'IDS 密码错误，请重新输入': 'Incorrect password. Try again.',
    'IDS 二次验证会话已失效，请重试': 'Verification expired. Please sign in again.',
    'IDS 二次验证失败，请检查密码后重试': 'Verification failed. Check your password and try again.',
    '无法确认 IDS 账号身份': 'IDS could not confirm your account. Try again.',
    'IDS 无法开始 Passkey 注册': 'IDS could not start passkey registration. Try again.',
    'IDS 未接受 Passkey 注册': 'IDS could not register your passkey. Try again.',
    '无法读取 IDS 已绑定的 Passkey 名称，请重试': 'Could not read your IDS passkeys. Try again.',
  };
  return _text(
    context,
    translations[message] ?? 'Could not connect to IDS. Please try again.',
    message,
  );
}

class IdsBindPage extends StatelessWidget {
  const IdsBindPage({super.key, this.legacyAccount});
  final ThirdPartyAccount? legacyAccount;

  @override
  Widget build(BuildContext context) => IdsBindForm(legacyAccount: legacyAccount);
}

class IdsBindForm extends StatefulWidget {
  const IdsBindForm({super.key, this.legacyAccount});
  final ThirdPartyAccount? legacyAccount;
  @override
  State<IdsBindForm> createState() => _IdsBindFormState();
}

class _IdsBindFormState extends State<IdsBindForm> with WidgetsBindingObserver {
  final _account = TextEditingController();
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  bool _busy = false;
  bool _refreshing = false;
  bool _manual = false;
  bool _retry = false;
  Object? _error;
  Uint8List? _image;
  IdsCaptchaRefresh? _refresh;
  Completer<String?>? _answer;
  ThirdPartyAccount? _connected;

  String text(String en, String zh) => _text(context, en, zh);
  bool get _canUpgrade {
    final account = widget.legacyAccount;
    return !_manual &&
        account?.platform == ThirdPartyPlatform.ids &&
        account!.raw['authMethod'] != 'passkey' &&
        account.account.trim().isNotEmpty &&
        (account.password?.isNotEmpty ?? false);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _answer?.complete(null);
    _account.dispose();
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<String?> _prompt(Uint8List image, String? error, {required IdsCaptchaRefresh refresh}) {
    if (!mounted) return Future.value(null);
    final pending = Completer<String?>();
    setState(() {
      _image = image;
      _error = error;
      _refresh = refresh;
      _answer = pending;
      _captcha.clear();
    });
    return pending.future;
  }

  Future<void> _reload() async {
    if (_refreshing || _answer == null) return;
    setState(() => _refreshing = true);
    try {
      final image = await _refresh!();
      if (!mounted) return;
      setState(() {
        _image = image;
        _captcha.clear();
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _error = text('Could not load the image. Try again.', '获取验证码失败，请重试'));
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  void _submitCaptcha() {
    if (_answer == null || _refreshing) return;
    if (_captcha.text.trim().isEmpty) {
      setState(() => _error = text('Enter the verification code.', '请输入验证码'));
      return;
    }
    FocusScope.of(context).unfocus();
    final answer = _answer!;
    setState(() {
      _answer = null;
      _error = null;
    });
    answer.complete(_captcha.text.trim());
  }

  Future<void> _bind() async {
    if (_busy) return;
    final upgrading = _canUpgrade;
    final account = upgrading ? widget.legacyAccount!.account : _account.text.trim();
    final password = upgrading ? widget.legacyAccount!.password! : _password.text;
    if (account.isEmpty || password.isEmpty) {
      setState(() => _error = text('Enter your IDS account and password.', '请填写 IDS 账号和密码'));
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final connected = await ServiceProvider.of(context).thirdPartyAuthService.bindIds(
            account: account,
            password: password,
            isCancelled: () => !mounted,
            promptCaptcha: _prompt,
          );
      if (!mounted) return;
      setState(() {
        _connected = connected;
        _password.clear();
        _captcha.clear();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _manual = true;
        _retry = true;
        _account.text = account;
        _password.clear();
        _error = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _image = null;
          _refresh = null;
        });
      }
    }
  }

  Widget _field(
    String label,
    TextEditingController controller,
    String hint, {
    bool password = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: TpTypography.itemMeta(context.tpColors)),
          const SizedBox(height: TpTokens.space2),
          AdaptiveTextFieldGroup(
            items: [
              AdaptiveTextFieldGroupItem(
                controller: controller,
                placeholder: hint,
                obscureText: password,
                enabled: !_busy,
                textInputAction: password ? TextInputAction.done : TextInputAction.next,
                onSubmitted: password ? (_) => unawaited(_bind()) : null,
              ),
            ],
          ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final verifying = _image != null;
    final connected = _connected;
    final upgrade = _canUpgrade;
    final colors = context.tpColors;
    String title;
    String description;
    if (connected != null) {
      title = text('Campus account connected', '校园账号已连接');
      description =
          text('You can now view your timetable and use campus services.', '现在可以用这个账号查看课表、使用校园服务。');
    } else if (verifying) {
      title = _error == null
          ? text('Enter the verification code', '输入验证码')
          : text('Try the new code', '再次输入验证码');
      description = text(
        'Enter the code from the image so IDS can verify your sign-in.',
        '学校 IDS 需要确认是你本人在登录。',
      );
    } else if (upgrade) {
      title = text('Upgrade your campus account', '升级校园账号');
      description = text(
        'Use your saved IDS account to create a passkey for TechPie.',
        '使用已保存的账号登录学校 IDS，并为 TechPie 创建 Passkey。',
      );
    } else {
      title = _retry
          ? text('Sign in again', '重新登录校园账号')
          : text('Connect your campus account', '连接校园账号');
      description = text(
        'Sign in with IDS to create a passkey for campus services in TechPie.',
        '使用学校 IDS 登录。TechPie 会创建 Passkey，方便你以后使用校园服务。',
      );
    }
    final details = <Widget>[];
    if (connected != null || (upgrade && !verifying)) {
      details.add(
        TpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(text('ShanghaiTech University', '上海科技大学'), style: TpTypography.itemMeta(colors)),
              const SizedBox(height: TpTokens.space2),
              Text(
                connected?.account ?? widget.legacyAccount!.account,
                style: TpTypography.pageTitle(colors).copyWith(fontSize: 23),
              ),
              if (connected != null) ...[
                const SizedBox(height: TpTokens.space2),
                Text(
                  text('Connected through IDS', '已通过 IDS 连接'),
                  style: TpTypography.itemMeta(colors).copyWith(color: colors.successGreen),
                ),
              ],
            ],
          ),
        ),
      );
    } else if (verifying) {
      details.add(
        Wrap(
          spacing: TpTokens.space3,
          runSpacing: TpTokens.space2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(TpTokens.radiusS),
              child: Image.memory(
                _image!,
                width: 160,
                height: 64,
                fit: BoxFit.contain,
                semanticLabel: text('IDS verification image', 'IDS 验证码图片'),
              ),
            ),
            TextButton(
              onPressed: _answer == null || _refreshing ? null : () => unawaited(_reload()),
              child: Text(text('New image', '换一张')),
            ),
          ],
        ),
      );
      details.add(
        AdaptiveTextFieldGroup(
          items: [
            AdaptiveTextFieldGroupItem(
              controller: _captcha,
              placeholder: text('Enter the characters shown', '输入图中的字符'),
              enabled: _answer != null && !_refreshing,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitCaptcha(),
            ),
          ],
        ),
      );
    } else {
      details.add(
        _field(
          text('IDS account', 'IDS 账号'),
          _account,
          text('Student ID or phone number', '学号或手机号'),
        ),
      );
      details.add(
        _field(
          text('IDS password', 'IDS 密码'),
          _password,
          text('Enter your password', '输入密码'),
          password: true,
        ),
      );
      details.add(
        Text(
          text('Your password is only used for this sign-in.', '密码仅用于本次学校验证。'),
          style: TpTypography.itemMeta(colors),
        ),
      );
    }
    if (_error != null) {
      details.add(
        Text(
          _bindingError(context, _error!),
          style: TpTypography.itemMeta(colors).copyWith(color: colors.dangerRed),
          semanticsLabel: _bindingError(context, _error!),
        ),
      );
    }
    return _IdsWizardLayout(
      title: title,
      description: description,
      icon: connected != null
          ? TpIcons.checkCircle
          : verifying
              ? TpIcons.code
              : TpIcons.lock,
      onCancel: connected != null ? null : () => unawaited(maybePopAdaptivePage<void>(context)),
      action: connected != null
          ? text('Done', '完成')
          : verifying
              ? text('Verify', '验证')
              : upgrade
                  ? text('Upgrade to a passkey', '升级为 Passkey')
                  : _retry
                      ? text('Reconnect', '重新连接')
                      : text('Connect account', '连接校园账号'),
      loading: _busy && (!verifying || _answer == null) || _refreshing,
      onAction: connected != null
          ? () => unawaited(maybePopAdaptivePage<void>(context))
          : verifying
              ? _submitCaptcha
              : () => unawaited(_bind()),
      secondary: upgrade && !verifying
          ? TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _manual = true;
                        _account.text = widget.legacyAccount!.account;
                      }),
              child: Text(text('Sign in manually', '手动登录')),
            )
          : null,
      children: details,
    );
  }
}

class _IdsWizardLayout extends StatelessWidget {
  const _IdsWizardLayout({
    required this.title,
    required this.description,
    required this.icon,
    required this.action,
    required this.onAction,
    required this.children,
    this.onCancel,
    this.secondary,
    this.loading = false,
  });
  final String title;
  final String description;
  final IconData icon;
  final String action;
  final VoidCallback onAction;
  final VoidCallback? onCancel;
  final Widget? secondary;
  final bool loading;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: TpTokens.singleColumnMaxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: onCancel == null
                        ? null
                        : TextButton(
                            onPressed: onCancel,
                            child: Text(_text(context, 'Cancel', '取消')),
                          ),
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.all(TpTokens.space5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: colors.brandSoft,
                              borderRadius: BorderRadius.circular(TpTokens.radiusM),
                            ),
                            child: Icon(icon, color: colors.brand, size: 26),
                          ),
                        ),
                        const SizedBox(height: TpTokens.space5),
                        Text(
                          title,
                          style:
                              TpTypography.pageTitle(colors).copyWith(fontSize: 30, height: 1.45),
                        ),
                        const SizedBox(height: TpTokens.space2),
                        Text(
                          description,
                          style: TpTypography.itemMeta(colors).copyWith(fontSize: 17, height: 1.45),
                        ),
                        const SizedBox(height: TpTokens.space5),
                        for (final child in children) ...[
                          child,
                          const SizedBox(height: TpTokens.space4),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.space5,
                    TpTokens.space3,
                    TpTokens.space5,
                    TpTokens.space4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (secondary != null) ...[
                        Align(alignment: AlignmentDirectional.centerStart, child: secondary),
                        const SizedBox(height: TpTokens.space2),
                      ],
                      FilledButton(
                        onPressed: loading ? null : onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: colors.brand,
                          foregroundColor: colors.onBrand,
                          minimumSize: const Size.fromHeight(52),
                          shape: const StadiumBorder(),
                        ),
                        child: loading
                            ? SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colors.onBrand,
                                ),
                              )
                            : Text(
                                action,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One modal stays mounted while IDS validates answers and returns retries.
class IdsDialogSession extends ChangeNotifier {
  IdsDialogSession(BuildContext context, {this.withPassword = false})
      : _context = Navigator.of(context, rootNavigator: true).context;
  final BuildContext _context;
  final bool withPassword;
  Completer<IdsVerificationAnswer?>? _pending;
  Future<void>? _dialog;
  BuildContext? _dialogContext;
  Uint8List? _image;
  String? _error;
  IdsCaptchaRefresh? _refresh;
  bool _busy = false;
  bool _closed = false;

  Future<String?> captcha(
    Uint8List image,
    String? error, {
    required IdsCaptchaRefresh refresh,
  }) async =>
      (await verification(image, error, refresh: refresh))?.captcha;

  Future<IdsVerificationAnswer?> verification(
    Uint8List image,
    String? error, {
    required IdsCaptchaRefresh refresh,
  }) {
    if (_closed || !_context.mounted) return Future.value(null);
    final answer = Completer<IdsVerificationAnswer?>();
    _pending = answer;
    _image = image;
    _error = error;
    _refresh = refresh;
    _busy = false;
    notifyListeners();
    _dialog ??= showDialog<void>(
      context: _context,
      barrierDismissible: false,
      builder: (context) {
        _dialogContext = context;
        return ListenableBuilder(
          listenable: this,
          builder: (context, _) => PopScope(
            canPop: !_busy,
            child: _IdsVerificationDialog(
              withPassword: withPassword,
              image: _image!,
              error: _error,
              busy: _busy,
              onAnswer: _submit,
              onRefresh: _reloadCaptcha,
            ),
          ),
        );
      },
    ).whenComplete(() {
      _closed = true;
      _pending?.complete(null);
      _pending = null;
    });
    return answer.future;
  }

  Future<void> _reloadCaptcha() async {
    if (_busy || _closed || _refresh == null) return;
    _busy = true;
    notifyListeners();
    try {
      final image = await _refresh!();
      if (_closed) return;
      _image = image;
      _error = null;
    } catch (error) {
      if (_closed) return;
      _error = '获取验证码失败，请点击图片重试';
    }
    if (_closed) return;
    _busy = false;
    notifyListeners();
  }

  void _submit(IdsVerificationAnswer answer) {
    final pending = _pending;
    if (pending == null || _busy || _closed) return;
    _pending = null;
    _busy = true;
    _error = null;
    notifyListeners();
    pending.complete(answer);
  }

  Future<void> close() async {
    _closed = true;
    _pending?.complete(null);
    _pending = null;
    final context = _dialogContext;
    if (context != null && context.mounted && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
    await _dialog;
  }
}

class _IdsVerificationDialog extends StatefulWidget {
  const _IdsVerificationDialog({
    required this.withPassword,
    required this.image,
    this.error,
    required this.busy,
    required this.onAnswer,
    required this.onRefresh,
  });
  final bool withPassword;
  final Uint8List image;
  final String? error;
  final bool busy;
  final ValueChanged<IdsVerificationAnswer> onAnswer;
  final VoidCallback onRefresh;
  @override
  State<_IdsVerificationDialog> createState() => _IdsVerificationDialogState();
}

class _IdsVerificationDialogState extends State<_IdsVerificationDialog> {
  final _password = TextEditingController();
  final _captcha = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _captcha.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _IdsVerificationDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _captcha.clear();
  }

  void _submit() {
    if (widget.busy ||
        _captcha.text.trim().isEmpty ||
        (widget.withPassword && _password.text.isEmpty)) {
      return;
    }
    widget.onAnswer((password: _password.text, captcha: _captcha.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return AlertDialog(
      title: Text(widget.withPassword ? 'IDS 解绑验证' : '输入验证码'),
      scrollable: true,
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.withPassword) ...[
              const Text(
                '本地绑定已删除。完成验证可同时在 IDS 解绑此 Passkey；取消或验证失败不影响本地删除。',
              ),
              const SizedBox(height: TpTokens.space3),
            ],
            if (widget.error != null) ...[
              Text(
                widget.error!,
                style: TpTypography.itemMeta(colors).copyWith(
                  color: colors.dangerRed,
                ),
              ),
              const SizedBox(height: TpTokens.space3),
            ],
            if (widget.withPassword) ...[
              SecurePasswordField(
                controller: _password,
                placeholder: 'IDS 密码',
                enabled: !widget.busy,
                decoration: const InputDecoration(labelText: 'IDS 密码'),
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: TpTokens.space3),
            ],
            _IdsCaptchaInput(
              image: widget.image,
              controller: _captcha,
              autofocus: !widget.withPassword,
              onSubmitted: _submit,
              enabled: !widget.busy,
              onRefresh: widget.onRefresh,
            ),
            if (widget.busy)
              const Padding(
                padding: EdgeInsets.only(top: TpTokens.space3),
                child: LinearProgressIndicator(),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.busy ? null : () => Navigator.pop(context),
          child: Text(widget.withPassword ? '仅删除本地' : '取消'),
        ),
        FilledButton(
          onPressed: widget.busy ? null : _submit,
          child: Text(
            widget.busy
                ? '正在验证…'
                : widget.withPassword
                    ? '验证并解绑 IDS'
                    : '继续',
          ),
        ),
      ],
    );
  }
}

class IdsPasskeyHelp extends StatelessWidget {
  const IdsPasskeyHelp({super.key});
  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          idsPasskeyNotice,
          style: TpTypography.itemMeta(colors).copyWith(height: 1.45),
        ),
        const SizedBox(height: TpTokens.space3),
        ClipRRect(
          borderRadius: BorderRadius.circular(TpTokens.radiusS),
          child: AspectRatio(
            aspectRatio: 2414 / 856,
            child: Image.asset(
              'assets/help/ids_passkey.png',
              semanticLabel: 'IDS 账号安全页面中 Techpie Passkey 的查看和解绑位置',
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: TpTokens.space2),
        TextButton.icon(
          onPressed: () => unawaited(
            launchUrl(
              idsAccountSecurityUrl,
              mode: LaunchMode.externalApplication,
            ),
          ),
          icon: const Icon(TpIcons.externalLink, size: TpTokens.iconS),
          label: const Text('打开 IDS 账号安全页面'),
        ),
      ],
    );
  }
}

class _IdsCaptchaInput extends StatelessWidget {
  const _IdsCaptchaInput({
    required this.image,
    required this.controller,
    required this.onSubmitted,
    this.autofocus = false,
    this.enabled = true,
    this.onRefresh,
  });
  final Uint8List image;
  final TextEditingController controller;
  final VoidCallback onSubmitted;
  final bool autofocus;
  final bool enabled;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              enabled: enabled,
              autocorrect: false,
              enableSuggestions: false,
              autofillHints: null,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(labelText: '验证码'),
              onSubmitted: (_) => onSubmitted(),
            ),
          ),
          const SizedBox(width: TpTokens.space3),
          Tooltip(
            message: '更换验证码',
            child: InkWell(
              onTap: enabled ? onRefresh : null,
              borderRadius: BorderRadius.circular(TpTokens.radiusXs),
              child: Image.memory(
                image,
                width: 112,
                height: 56,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ],
      );
}
