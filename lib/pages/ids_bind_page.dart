import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/third_party_account.dart';
import '../services/ids/ids_client.dart' show IdsCaptchaRefresh, IdsVerificationAnswer;
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/secure_password_field.dart';

final idsAccountSecurityUrl = Uri.parse(
  'https://ids.shanghaitech.edu.cn/personalInfo/personCenter/index.html#/accountsecurity',
);
const idsPasskeyNotice =
    '您可以在 IDS 账号安全页面查看已创建的 Passkey，并随时解绑。解绑后，需要在 TechPie 重新绑定，才能继续使用 IDS 相关功能。';

class IdsBindPage extends StatelessWidget {
  const IdsBindPage({super.key, this.legacyAccount});
  final ThirdPartyAccount? legacyAccount;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: isIos()
            ? IosNativeNavigationBar(
                title: '绑定 IDS Passkey',
                leadingItems: [
                  if (Navigator.canPop(context))
                    const IosNativeNavigationBarItem(
                      id: 'back',
                      title: '返回',
                      sfSymbol: 'chevron.left',
                    ),
                ],
                onItemPressed: (_) => unawaited(maybePopAdaptivePage<void>(context)),
              )
            : const BlurredAppBar(title: Text('绑定 IDS Passkey')),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: IdsBindForm(legacyAccount: legacyAccount),
          ),
        ),
      );
}

class IdsBindForm extends StatefulWidget {
  const IdsBindForm({super.key, this.legacyAccount});
  final ThirdPartyAccount? legacyAccount;
  @override
  State<IdsBindForm> createState() => _IdsBindFormState();
}

class _IdsBindFormState extends State<IdsBindForm> {
  final _account = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _manual = false;

  bool get _canUpgrade {
    final account = widget.legacyAccount;
    return !_manual &&
        account?.platform == ThirdPartyPlatform.ids &&
        account!.raw['authMethod'] != 'passkey' &&
        account.account.trim().isNotEmpty &&
        (account.password?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    _account.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _bind({String? account, String? password, bool upgrading = false}) async {
    if (_busy) return;
    final loginAccount = (account ?? _account.text).trim();
    final loginPassword = password ?? _password.text;
    if (loginAccount.isEmpty || loginPassword.isEmpty) {
      setState(() => _error = '请填写 IDS 账号和密码');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final prompts = IdsDialogSession(context);
    try {
      await ServiceProvider.of(context).thirdPartyAuthService.bindIds(
            account: loginAccount,
            password: loginPassword,
            isCancelled: () => !mounted,
            promptCaptcha: (image, error, {required refresh}) async {
              if (!mounted) return null;
              return prompts.captcha(image, error, refresh: refresh);
            },
          );
      if (!mounted) return;
      _password.clear();
      await prompts.close();
      if (!mounted) return;
      await maybePopAdaptivePage<void>(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          if (upgrading) {
            _manual = true;
            _account.text = loginAccount;
            _password.clear();
          }
          _error = error.toString();
        });
      }
    } finally {
      await prompts.close();
      prompts.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            _canUpgrade
                ? '检测到已保存的旧版校园账号，是否升级为 Passkey？确认后将由本机使用已保存的账号和密码登录学校 IDS。'
                : '首次绑定需要登录学校 IDS，并为 TechPie 创建一个 Passkey。之后由 TechPie 自动使用它登录。',
          ),
          const SizedBox(height: 20),
          if (_canUpgrade) ...[
            FilledButton(
              onPressed: _busy
                  ? null
                  : () => unawaited(
                        _bind(
                          account: widget.legacyAccount!.account,
                          password: widget.legacyAccount!.password,
                          upgrading: true,
                        ),
                      ),
              child: Text(_busy ? '正在升级…' : '确认升级为 Passkey'),
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _manual = true;
                        _account.text = widget.legacyAccount!.account;
                      }),
              child: const Text('手动绑定'),
            ),
          ] else
            AdaptiveTextFieldGroup(
              items: [
                AdaptiveTextFieldGroupItem(
                  controller: _account,
                  placeholder: 'IDS 账号（学号或手机号）',
                  enabled: !_busy,
                ),
                AdaptiveTextFieldGroupItem(
                  controller: _password,
                  placeholder: 'IDS 密码',
                  obscureText: true,
                  enabled: !_busy,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => unawaited(_bind()),
                ),
              ],
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 20),
          if (!_canUpgrade)
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_bind()),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('创建并绑定 Passkey'),
            ),
          const SizedBox(height: 16),
          Text(
            '账号、密码和验证码由本机直接提交给学校。密码不会保存；Passkey 保存在本机安全存储中，开启 Cloud Sync 后会端到端加密同步。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 20),
          const IdsPasskeyHelp(),
        ],
      );
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
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.withPassword ? 'IDS 解绑验证' : '输入验证码'),
        scrollable: true,
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.withPassword) ...[
                const Text('本地绑定已删除。完成验证可同时在 IDS 解绑此 Passkey；取消或验证失败不影响本地删除。'),
                const SizedBox(height: 12),
              ],
              if (widget.error != null) ...[
                Text(widget.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                const SizedBox(height: 12),
              ],
              if (widget.withPassword) ...[
                SecurePasswordField(
                  controller: _password,
                  placeholder: 'IDS 密码',
                  enabled: !widget.busy,
                  decoration: const InputDecoration(labelText: 'IDS 密码'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
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
                const Padding(padding: EdgeInsets.only(top: 12), child: LinearProgressIndicator()),
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
            child: Text(widget.busy
                ? '正在验证…'
                : widget.withPassword
                    ? '验证并解绑 IDS'
                    : '继续',),
          ),
        ],
      );
}

class IdsPasskeyHelp extends StatelessWidget {
  const IdsPasskeyHelp({super.key});
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(idsPasskeyNotice),
          const SizedBox(height: 12),
          AspectRatio(
            aspectRatio: 2414 / 856,
            child: Image.asset(
              'assets/help/ids_passkey.png',
              semanticLabel: 'IDS 账号安全页面中 Techpie Passkey 的查看和解绑位置',
              fit: BoxFit.contain,
            ),
          ),
          TextButton.icon(
            onPressed: () =>
                unawaited(launchUrl(idsAccountSecurityUrl, mode: LaunchMode.externalApplication)),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('打开 IDS 账号安全页面'),
          ),
        ],
      );
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
          const SizedBox(width: 12),
          Tooltip(
            message: '更换验证码',
            child: InkWell(
              onTap: enabled ? onRefresh : null,
              child: Image.memory(image, width: 112, height: 56, fit: BoxFit.contain),
            ),
          ),
        ],
      );
}
