import 'dart:async';

import 'package:flutter/material.dart';

import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../services/campus_card_service.dart';
import '../services/service_provider.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class CampusCardAccountPage extends StatefulWidget {
  const CampusCardAccountPage({super.key});

  @override
  State<CampusCardAccountPage> createState() => _CampusCardAccountPageState();
}

class _CampusCardAccountPageState extends State<CampusCardAccountPage> {
  final _openIdController = TextEditingController();
  bool _loaded = false;
  EcardOpenIdChannel _channel = EcardOpenIdChannel.wechat;
  bool _checking = false;
  bool _saving = false;
  bool _disconnecting = false;
  String? _inlineMessage;
  bool _inlineError = false;

  bool get _operationBusy =>
      _checking || _saving || _disconnecting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_loadOpenId());

  }

  @override
  void dispose() {
    _openIdController.dispose();
    super.dispose();
  }

  Future<void> _loadOpenId() async {
    final service = ServiceProvider.of(context).campusCardService;
    await service.refreshAccount();
    final openId = await service.readOpenId();
    final channel = await service.readOpenIdChannel();
    if (!mounted) return;
    setState(() {
      _openIdController.text = openId ?? '';
      _channel = channel;
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = ServiceProvider.of(context).campusCardService;
    bool isBusy() => service.busy || _operationBusy;
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: !useIosChrome && !useLegacyIosChrome,
      appBar: useIosChrome
          ? IosNativeNavigationBar(
              title: 'eCard',
              leadingItems: const [
                IosNativeNavigationBarItem(
                  id: 'back',
                  title: 'Settings',
                  sfSymbol: 'chevron.left',
                  accessibilityLabel: '返回 Settings',
                  placementGroup: 'leading-main',
                ),
              ],
              onItemPressed: (id) {
                if (id == 'back') {
                  unawaited(maybePopAdaptivePage<void>(context));
                }
              },
            )
          : const BlurredAppBar(title: Text('eCard')),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            topInset + 16,
            16,
            AppShellMetrics.bottomContentPaddingOf(context),
          ),
          children: [
            Text('eCard', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              '使用 OPENID 通过 GeekPie 会话服务连接 eCard。OPENID 保存在本机安全存储中；开启 Cloud sync 后会端到端加密同步。会话 Cookie 和离线密钥仍由各设备单独保存。',
              style: hintStyle,
            ),
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(child: Text('OPENID 渠道')),
              SizedBox(width: 200, child: IgnorePointer(ignoring: isBusy(), child: AdaptiveSelect(
                value: _channel.method,
                width: 200,
                accessibilityLabel: 'OPENID 渠道',
                options: [for (final channel in EcardOpenIdChannel.values)
                  AdaptiveSelectOption(value: channel.method, label: channel.label),],
                onChanged: (value) {
                  if (isBusy()) return;
                  setState(() {
                    _channel = EcardOpenIdChannel.parse(value);
                    _inlineMessage = null;
                  });
                },
              ),),),
            ],),
            const SizedBox(height: 12),
            AdaptiveTextFieldGroup(
              key: const Key('openid-field'),
              items: [
                AdaptiveTextFieldGroupItem(
                  controller: _openIdController,
                  placeholder: '${_channel.label} OPENID',
                  textInputAction: TextInputAction.done,
                  enabled: !isBusy(),
                  onSubmitted: (_) => unawaited(_save(service)),
                ),
              ],
            ),
            if (_inlineMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('openid-inline-status'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_inlineError
                          ? theme.colorScheme.error
                          : theme.colorScheme.primary)
                      .withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _inlineMessage!,
                  style: TextStyle(
                    color: _inlineError
                        ? theme.colorScheme.error
                        : theme.colorScheme.primary,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            AdaptiveButton(
              key: const Key('openid-save-button'),
              onPressed: isBusy() ? null : () => unawaited(_save(service)),
              icon: Icons.save_outlined,
              sfSymbol: 'checkmark',
              label: service.configured ? '更新 eCard' : '连接 eCard',
              role: AdaptiveButtonRole.prominent,
              loading: _saving,
              width: double.infinity,
              accessibilityLabel:
                  service.configured ? '更新 eCard' : '连接 eCard',
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              key: const Key('openid-check-button'),
              onPressed: isBusy() ? null : () => unawaited(_check(service)),
              icon: Icons.verified_user_outlined,
              sfSymbol: 'checkmark.shield',
              label: '检查登录',
              role: AdaptiveButtonRole.standard,
              loading: _checking,
              width: double.infinity,
              accessibilityLabel: '检查 eCard 连接',
            ),
            if (service.configured) ...[
              const SizedBox(height: 8),
              IgnorePointer(
                ignoring: isBusy(),
                child: AdaptiveConfirmationButton(
                  label: '移除 eCard',
                  icon: Icons.link_off,
                  sfSymbol: 'link.badge.minus',
                  confirmTitle: '移除 eCard？',
                  confirmLabel: '移除',
                  destructive: true,
                  width: double.infinity,
                  onConfirmed: () => unawaited(_disconnect(service)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _check(CampusCardService service) async {
    if (_operationBusy || service.busy) return;
    final openId = _openIdController.text.trim();
    final channel = _channel;
    setState(() {
      _checking = true;
      _inlineMessage = null;
    });
    try {
      await service.verifyOpenId(openId, channel: channel);
      if (!mounted) return;
      setState(() {
        _inlineError = false;
        _inlineMessage = 'OPENID 可以正常登录 eCard';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _save(CampusCardService service) async {
    if (_operationBusy || service.busy) return;
    setState(() {
      _saving = true;
      _inlineMessage = null;
    });
    try {
      await _connect(service);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _connect(CampusCardService service) async {
    final openId = _openIdController.text.trim();
    final channel = _channel;
    await service.connect(openId, channel: channel);
    if (!mounted) return;
    setState(() {
      _inlineError = false;
      _inlineMessage = 'eCard 已连接';
    });
  }

  Future<void> _disconnect(CampusCardService service) async {
    if (_operationBusy || service.busy) return;
    setState(() => _disconnecting = true);
    try {
      await service.disconnect();
      if (!mounted) return;
      setState(() {
        _openIdController.clear();
        _inlineError = false;
        _inlineMessage = 'eCard 已移除';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      if (mounted) setState(() => _disconnecting = false);
    }
  }

  String _safeMessage(Object error) {
    if (error is AppFailure) return error.safeMessage;
    if (error is FormatException) return 'OPENID 格式无效';
    return '无法验证 OPENID，请检查网络后重试';
  }
}
