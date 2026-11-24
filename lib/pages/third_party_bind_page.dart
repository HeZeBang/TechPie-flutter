import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/third_party_account.dart';
import '../services/service_provider.dart';
import '../services/third_party_auth_service.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/adaptive_text_area.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'ids_bind_page.dart';

class ThirdPartyBindPage extends StatefulWidget {
  final ThirdPartyPlatform platform;

  const ThirdPartyBindPage({super.key, required this.platform});

  @override
  State<ThirdPartyBindPage> createState() => _ThirdPartyBindPageState();
}

class _ThirdPartyBindPageState extends State<ThirdPartyBindPage> {
  final _accountCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _hydroOriginCtrl = TextEditingController(
    text: 'https://acm.shanghaitech.edu.cn',
  );
  final _hydroDomainsCtrl = TextEditingController();
  bool _busy = false;
  bool _autoRenew = false;
  String? _inlineError;

  bool get _isIds => widget.platform == ThirdPartyPlatform.ids;
  bool get _isHydro => widget.platform == ThirdPartyPlatform.hydro;
  bool get _isGradescope => widget.platform == ThirdPartyPlatform.gradescope;

  Future<void> _dismissKeyboard() async {
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
    } catch (_) {}
  }

  @override
  void dispose() {
    _accountCtrl.dispose();
    _passwordCtrl.dispose();
    _hydroOriginCtrl.dispose();
    _hydroDomainsCtrl.dispose();
    super.dispose();
  }

  Future<void> _onAutoRenewChanged(bool value) async {
    if (!value) {
      setState(() => _autoRenew = false);
      return;
    }

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
    setState(() => _autoRenew = ok == true);
  }

  bool _validateForSubmit() {
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
      await tpAuth.bind(
        platform: widget.platform,
        account: _accountCtrl.text.trim(),
        password: _passwordCtrl.text,
        hydroOrigin: _isHydro ? _hydroOriginCtrl.text.trim() : null,
        hydroDomains: domains,
        autoRenew: _autoRenew,
      );
      if (!mounted) return;
      setState(() => _inlineError = null);
      await _dismissKeyboard();
      if (!mounted) return;
      showAdaptiveFeedback(
        context: context,
        message: '${widget.platform.label} 绑定成功',
        style: AdaptiveFeedbackStyle.success,
      );
      await maybePopAdaptivePage<void>(context);
    } on ThirdPartyBindException catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _inlineError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isIds) {
      return IdsBindPage(
        legacyAccount:
            ServiceProvider.of(context).thirdPartyAuthService.idsAccount,
      );
    }

    final colors = context.tpColors;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space4,
    );
    final title = '绑定 ${widget.platform.label}';

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: title,
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
            if (id == 'back') unawaited(maybePopAdaptivePage<void>(context));
          },
        ),
        material: () => BlurredAppBar(title: Text(title)),
      ),
      body: ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          TpTokens.pageHorizontalPadding,
          topInset,
          TpTokens.pageHorizontalPadding,
          AppShellMetrics.bottomContentPaddingOf(context) + TpTokens.space4,
        ),
        children: [
          TpPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_inlineError != null) ...[
                  _InlineBindFeedback(message: _inlineError!),
                  const SizedBox(height: TpTokens.sectionGap),
                ],
                TpCard(
                  leadingIcon:
                      _isGradescope ? TpIcons.graduation : TpIcons.code,
                  title: '${widget.platform.label} 账号凭据',
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space1,
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AdaptiveTextFieldGroup(
                        items: [
                          AdaptiveTextFieldGroupItem(
                            placeholder: _isGradescope ? '邮箱' : '用户名',
                            controller: _accountCtrl,
                            keyboardType: _isGradescope
                                ? TextInputType.emailAddress
                                : TextInputType.text,
                            textInputAction: TextInputAction.next,
                            enabled: !_busy,
                          ),
                          AdaptiveTextFieldGroupItem(
                            placeholder: '密码',
                            controller: _passwordCtrl,
                            obscureText: true,
                            textInputAction: _isHydro
                                ? TextInputAction.next
                                : TextInputAction.done,
                            enabled: !_busy,
                            onSubmitted: (_) {
                              if (!_isHydro) unawaited(_submit());
                            },
                          ),
                        ],
                      ),
                      if (_isHydro) ...[
                        const SizedBox(height: TpTokens.space3),
                        AdaptiveTextFieldGroup(
                          items: [
                            AdaptiveTextFieldGroupItem(
                              placeholder: 'Hydro 站点 Origin',
                              controller: _hydroOriginCtrl,
                              keyboardType: TextInputType.url,
                              textInputAction: TextInputAction.next,
                              enabled: !_busy,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '默认 https://acm.shanghaitech.edu.cn',
                          style: TpTypography.itemMeta(colors),
                        ),
                        const SizedBox(height: TpTokens.space3),
                        AdaptiveTextArea(
                          placeholder: '课程 Domain（每行一个，或用逗号分隔）',
                          controller: _hydroDomainsCtrl,
                          minLines: 2,
                          maxLines: 6,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '例：SI100B_2025_Autumn',
                          style: TpTypography.itemMeta(colors),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: TpTokens.sectionGap),
                TpCard(
                  child: TpListRow(
                    icon: TpIcons.refresh,
                    iconColor: colors.infoBlue,
                    title: '自动更新 Token',
                    subtitle: '过期前 48 小时内自动重登，免去手动重绑',
                    trailing: AdaptiveSwitch(
                      value: _autoRenew,
                      enabled: !_busy,
                      onChanged: (value) =>
                          unawaited(_onAutoRenewChanged(value)),
                    ),
                    onTap: _busy
                        ? null
                        : () => unawaited(_onAutoRenewChanged(!_autoRenew)),
                  ),
                ),
                const SizedBox(height: TpTokens.space4),
                AdaptiveButton(
                  label: '绑定',
                  icon: TpIcons.check,
                  sfSymbol: 'checkmark',
                  role: AdaptiveButtonRole.prominent,
                  loading: _busy,
                  height: 46,
                  onPressed: _busy ? null : () => unawaited(_submit()),
                ),
                const SizedBox(height: TpTokens.space3),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: TpTokens.space2,
                  ),
                  child: Text(
                    '凭据将通过 HTTPS 发送到 TechPie 后端，由后端代为登录上游平台并返回 Token。'
                    'Token 与原始信息在本设备安全存储；开启云同步后会以端到端加密形式备份至 Casdoor。',
                    style: TpTypography.itemMeta(colors).copyWith(height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineBindFeedback extends StatelessWidget {
  const _InlineBindFeedback({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return TpCard(
      color: colors.opaqueDangerContainer,
      borderColor: colors.dangerRed.withValues(alpha: 0.30),
      borderRadius: TpTokens.radiusS,
      padding: const EdgeInsets.symmetric(
        horizontal: TpTokens.space3,
        vertical: TpTokens.space3,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(TpIcons.info, size: TpTokens.iconS, color: colors.dangerRed),
          const SizedBox(width: TpTokens.space2),
          Expanded(
            child: Text(
              message,
              style: TpTypography.itemMeta(colors).copyWith(
                color: colors.dangerRed,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
