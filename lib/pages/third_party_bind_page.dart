import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios_liquid/ios_glass_switch.dart';
import '../widgets/ios_liquid/ios_native_navigation_bar.dart';
import '../widgets/ios_liquid/ios_native_segmented_control.dart';
import '../widgets/ios_liquid/ios_native_text_field_group.dart';
import '../widgets/ios_liquid/ios_native_text_view.dart';
import '../widgets/ios_liquid/ios_platform_view_page_transitions.dart';

class ThirdPartyBindPage extends StatefulWidget {
  final ThirdPartyPlatform platform;

  const ThirdPartyBindPage({super.key, required this.platform});

  @override
  State<ThirdPartyBindPage> createState() => _ThirdPartyBindPageState();
}

class _ThirdPartyBindPageState extends State<ThirdPartyBindPage> {
  final _formKey = GlobalKey<FormState>();
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hydroOriginCtrl = TextEditingController(
    text: 'https://acm.shanghaitech.edu.cn',
  );
  final _hydroDomainsCtrl = TextEditingController();
  bool _busy = false;
  bool _obscure = true;
  bool _autoRenew = false;
  String? _inlineError;

  // cpdaily SMS state
  int _cpdailyLoginMethod = 0; // 0 = password, 1 = SMS
  final _cpdailyPhoneCtrl = TextEditingController();
  final _cpdailyCodeCtrl = TextEditingController();
  bool _sendingSms = false;
  int _smsCooldown = 0;
  Timer? _smsCooldownTimer;

  bool get _isHydro => widget.platform == ThirdPartyPlatform.hydro;
  bool get _isGradescope => widget.platform == ThirdPartyPlatform.gradescope;
  bool get _isCpdaily => widget.platform == ThirdPartyPlatform.cpdaily;

  Future<void> _dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    if (isIos()) {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    }
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _hydroOriginCtrl.dispose();
    _hydroDomainsCtrl.dispose();
    _cpdailyPhoneCtrl.dispose();
    _cpdailyCodeCtrl.dispose();
    _smsCooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _onAutoRenewChanged(bool value) async {
    if (!value) {
      setState(() => _autoRenew = false);
      return;
    }

    // Optimistically set to true so the native switch and Flutter state stay
    // in sync. If the user cancels the native presenter, we'll revert to false.
    setState(() => _autoRenew = true);

    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '开启自动更新 Token',
      message: '打开后，APP 将于本地加密存储你的账号和密码信息,'
          '用于在过期前 48 小时内自动触发 Token 更新。\n\n'
          '凭据存放在本设备的 Keychain / EncryptedSharedPreferences 中。'
          '若开启云同步，密码也会被端到端加密后备份至 Casdoor(仅你能用主密码解密)。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '我知道了,开启',
          value: true,
          isDefault: true,
        ),
      ],
    );

    if (!mounted) return;

    // If user didn't accept, revert to false so native presenter and switch
    // UI are consistent.
    setState(() => _autoRenew = ok == true);
  }

  // -- cpdaily SMS methods --

  Future<void> _sendCpdailySms() async {
    final phone = _cpdailyPhoneCtrl.text.trim();
    if (phone.isEmpty) return;

    setState(() => _sendingSms = true);
    try {
      await ServiceProvider.of(context)
          .thirdPartyAuthService
          .sendCpdailySmsCode(phone);
      if (mounted) {
        setState(() => _inlineError = null);
        _smsCooldown = 60;
        _smsCooldownTimer?.cancel();
        _smsCooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) {
            t.cancel();
            return;
          }
          if (_smsCooldown <= 1) {
            t.cancel();
            setState(() => _smsCooldown = 0);
          } else {
            setState(() => _smsCooldown--);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _inlineError = '发送失败：$e');
      }
    } finally {
      if (mounted) setState(() => _sendingSms = false);
    }
  }

  Future<void> _submit() async {
    if (!_validateForSubmit()) return;
    await _dismissKeyboard();
    if (!mounted) return;
    setState(() => _busy = true);

    final tpAuth = ServiceProvider.of(context).thirdPartyAuthService;

    List<String>? domains;
    if (_isHydro) {
      domains = _hydroDomainsCtrl.text
          .split(RegExp(r'[\s,]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
    }

    try {
      if (_isCpdaily && _cpdailyLoginMethod == 1) {
        // SMS mode
        await tpAuth.bindCpdailySms(
          phone: _cpdailyPhoneCtrl.text.trim(),
          code: _cpdailyCodeCtrl.text.trim(),
        );
      } else {
        await tpAuth.bind(
          platform: widget.platform,
          account: _accountCtrl.text.trim(),
          password: _passwordCtrl.text,
          hydroOrigin: _isHydro ? _hydroOriginCtrl.text.trim() : null,
          hydroDomains: domains,
          autoRenew: _autoRenew,
        );
      }
      if (!mounted) return;
      setState(() => _inlineError = null);
      await _dismissKeyboard();
      if (!mounted) return;
      if (!isIos()) {
        showAdaptiveFeedback(
          context: context,
          message: '${widget.platform.label} 绑定成功',
          style: AdaptiveFeedbackStyle.success,
        );
      }
      await maybePopPlatformViewPage<void>(context);
    } on ThirdPartyBindException catch (e) {
      if (!mounted) return;
      if (isIos()) {
        setState(() => _inlineError = e.message);
      } else {
        showAdaptiveFeedback(
          context: context,
          message: e.message,
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (isIos()) {
        setState(() => _inlineError = e.toString());
      } else {
        showAdaptiveFeedback(
          context: context,
          message: e.toString(),
          style: AdaptiveFeedbackStyle.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _validateForSubmit() {
    if (_isCpdaily && _cpdailyLoginMethod == 1) {
      // SMS mode validation
      String? message;
      if (_cpdailyPhoneCtrl.text.trim().isEmpty) {
        message = '请填写手机号码';
      } else if (_cpdailyCodeCtrl.text.trim().isEmpty) {
        message = '请填写验证码';
      }
      setState(() => _inlineError = message);
      return message == null;
    }

    if (!isIos()) {
      return _formKey.currentState?.validate() ?? true;
    }

    String? message;
    if (_accountCtrl.text.trim().isEmpty) {
      message = '请填写${_isGradescope ? '邮箱' : '用户名'}';
    } else if (_passwordCtrl.text.isEmpty) {
      message = '请填写密码';
    } else if (_isHydro && _hydroOriginCtrl.text.trim().isEmpty) {
      message = '请填写 Hydro 站点 origin';
    } else if (_isHydro) {
      final domains = _hydroDomainsCtrl.text
          .split(RegExp(r'[\s,]+'))
          .where((value) => value.trim().isNotEmpty);
      if (domains.isEmpty) message = '至少填写一个课程 domain';
    }

    setState(() => _inlineError = message);
    return message == null;
  }

  @override
  Widget build(BuildContext context) {
    if (isIos()) {
      return _buildIosBindPage(context);
    }

    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useLegacyIosChrome
        ? 16.0
        : 16 + adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useLegacyIosChrome,
      appBar: BlurredAppBar(title: Text('Bind ${widget.platform.label}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            topInset,
            16,
            16,
          ),
          children: [
            if (_inlineError != null) ...[
              _InlineBindFeedback(message: _inlineError!),
              const SizedBox(height: 12),
            ],
            if (_isCpdaily) ...[
              // cpdaily: tabbed password / SMS interface
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('密码登录')),
                  ButtonSegment(value: 1, label: Text('短信登录')),
                ],
                selected: {_cpdailyLoginMethod},
                onSelectionChanged: (v) =>
                    setState(() => _cpdailyLoginMethod = v.first),
              ),
              const SizedBox(height: 16),
              if (_cpdailyLoginMethod == 0) ...[
                TextFormField(
                  controller: _accountCtrl,
                  decoration: const InputDecoration(
                    labelText: '学号',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '必填' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordCtrl,
                  obscureText: _obscure,
                  decoration: InputDecoration(
                    labelText: '密码',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                      ),
                      onPressed: () => setState(() => _obscure = !_obscure),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
                ),
              ] else ...[
                TextFormField(
                  controller: _cpdailyPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: '手机号码',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '必填' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _cpdailyCodeCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '验证码',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '必填' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonal(
                      onPressed: (_smsCooldown > 0 || _sendingSms)
                          ? null
                          : () => unawaited(_sendCpdailySms()),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(100, 56),
                      ),
                      child: _sendingSms
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _smsCooldown > 0 ? '${_smsCooldown}s' : '发送验证码',
                            ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
            ] else ...[
              TextFormField(
                controller: _accountCtrl,
                autofillHints: const [AutofillHints.username],
                keyboardType: _isGradescope
                    ? TextInputType.emailAddress
                    : TextInputType.text,
                decoration: InputDecoration(
                  labelText: _isGradescope ? '邮箱' : '用户名',
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty) ? '必填' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _passwordCtrl,
                autofillHints: const [AutofillHints.password],
                obscureText: _obscure,
                decoration: InputDecoration(
                  labelText: '密码',
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) => (v == null || v.isEmpty) ? '必填' : null,
              ),
              if (_isHydro) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hydroOriginCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hydro 站点 origin',
                    helperText: '默认 https://acm.shanghaitech.edu.cn',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '必填' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _hydroDomainsCtrl,
                  minLines: 2,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '课程 domain (每行一个,或用逗号分隔)',
                    helperText: '例: SI100B_2025_Autumn',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) {
                    final list = (v ?? '')
                        .split(RegExp(r'[\s,]+'))
                        .where((e) => e.trim().isNotEmpty);
                    return list.isEmpty ? '至少填一个 domain' : null;
                  },
                ),
              ],
              const SizedBox(height: 8),
            ],
            if (isIos())
              MergeSemantics(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动更新 Token'),
                  subtitle: const Text('过期前 48 小时内自动重登,免去手动重绑'),
                  trailing: IosGlassSwitch(
                    value: _autoRenew,
                    onChanged: (v) => unawaited(_onAutoRenewChanged(v)),
                  ),
                  onTap: () => unawaited(_onAutoRenewChanged(!_autoRenew)),
                ),
              )
            else
              CheckboxListTile(
                value: _autoRenew,
                onChanged: (v) => unawaited(_onAutoRenewChanged(v ?? false)),
                title: const Text('自动更新 Token'),
                subtitle: const Text('过期前 48 小时内自动重登,免去手动重绑'),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('绑定'),
            ),
            const SizedBox(height: 12),
            Text(
              '凭据将通过 HTTPS 发送到 techpie 后端,后端代为登录上游平台并返回 token。'
              'token 与原始 payload 在本设备加密保存;开启云同步后会以端到端加密形式备份至 Casdoor。',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIosBindPage(BuildContext context) {
    final theme = Theme.of(context);
    final secondaryLabel = theme.colorScheme.onSurfaceVariant;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: IosNativeNavigationBar(
        title: 'Bind ${widget.platform.label}',
        leadingItems: [
          if (Navigator.canPop(context))
            const IosNativeNavigationBarItem(
              id: 'back',
              title: '返回',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回',
            ),
        ],
        onItemPressed: (id) {
          if (id == 'back') {
            unawaited(maybePopPlatformViewPage<void>(context));
          }
        },
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (_inlineError != null) ...[
              _InlineBindFeedback(message: _inlineError!),
              const SizedBox(height: 16),
            ],
            if (_isCpdaily) ...[
              IosNativeSegmentedControl(
                value: _cpdailyLoginMethod,
                segments: const ['密码登录', '短信登录'],
                onChanged: (value) {
                  setState(() {
                    _cpdailyLoginMethod = value;
                    _inlineError = null;
                  });
                },
              ),
              const SizedBox(height: 18),
              if (_cpdailyLoginMethod == 0)
                IosNativeTextFieldGroup(
                  items: [
                    IosNativeTextFieldGroupItem(
                      placeholder: '学号',
                      controller: _accountCtrl,
                      textInputAction: TextInputAction.next,
                    ),
                    IosNativeTextFieldGroupItem(
                      placeholder: '密码',
                      controller: _passwordCtrl,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => unawaited(_submit()),
                    ),
                  ],
                )
              else ...[
                IosNativeTextFieldGroup(
                  items: [
                    IosNativeTextFieldGroupItem(
                      placeholder: '手机号码',
                      controller: _cpdailyPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: IosNativeTextFieldGroup(
                        items: [
                          IosNativeTextFieldGroupItem(
                            placeholder: '验证码',
                            controller: _cpdailyCodeCtrl,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => unawaited(_submit()),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonal(
                      onPressed: (_smsCooldown > 0 || _sendingSms)
                          ? null
                          : () => unawaited(_sendCpdailySms()),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(100, 56),
                      ),
                      child: _sendingSms
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _smsCooldown > 0 ? '${_smsCooldown}s' : '发送验证码',
                            ),
                    ),
                  ],
                ),
              ],
            ] else
              IosNativeTextFieldGroup(
                items: [
                  IosNativeTextFieldGroupItem(
                    placeholder: _isGradescope ? '邮箱' : '用户名',
                    controller: _accountCtrl,
                    keyboardType: _isGradescope
                        ? TextInputType.emailAddress
                        : TextInputType.text,
                    textInputAction: TextInputAction.next,
                  ),
                  IosNativeTextFieldGroupItem(
                    placeholder: '密码',
                    controller: _passwordCtrl,
                    obscureText: _obscure,
                    textInputAction:
                        _isHydro ? TextInputAction.next : TextInputAction.done,
                    onSubmitted: (_) {
                      if (!_isHydro) unawaited(_submit());
                    },
                  ),
                ],
              ),
            if (_isHydro) ...[
              const SizedBox(height: 16),
              IosNativeTextFieldGroup(
                items: [
                  IosNativeTextFieldGroupItem(
                    placeholder: 'Origin',
                    controller: _hydroOriginCtrl,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '默认 https://acm.shanghaitech.edu.cn',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryLabel,
                ),
              ),
              const SizedBox(height: 10),
              IosNativeTextView(
                placeholder: 'Domain',
                controller: _hydroDomainsCtrl,
                minLines: 2,
                maxLines: 6,
                textInputAction: TextInputAction.done,
              ),
              const SizedBox(height: 4),
              Text(
                '每行一个,或用逗号分隔\n例: SI100B_2025_Autumn',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: secondaryLabel,
                ),
              ),
            ],
            if (!_isCpdaily || _cpdailyLoginMethod == 0) ...[
              const SizedBox(height: 16),
              MergeSemantics(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('自动更新 Token'),
                  subtitle: Text(
                    '过期前 48 小时内自动重登,免去手动重绑',
                    style: TextStyle(color: secondaryLabel),
                  ),
                  trailing: IosGlassSwitch(
                    value: _autoRenew,
                    onChanged: (value) => unawaited(_onAutoRenewChanged(value)),
                  ),
                  onTap: () => unawaited(_onAutoRenewChanged(!_autoRenew)),
                ),
              ),
            ],
            const SizedBox(height: 18),
            FilledButton(
              onPressed: _busy ? null : () => unawaited(_submit()),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('绑定'),
            ),
            const SizedBox(height: 12),
            Text(
              '凭据将通过 HTTPS 发送到 techpie 后端,后端代为登录上游平台并返回 token。'
              'token 与原始 payload 仅在本设备加密保存。',
              style: theme.textTheme.bodySmall?.copyWith(color: secondaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineBindFeedback extends StatelessWidget {
  const _InlineBindFeedback({required this.message});

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
