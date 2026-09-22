import 'dart:async';

import 'package:flutter/material.dart';

import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../services/campus_card_service.dart';
import '../services/ecard_bind_hijack.dart';
import '../services/ecard_bind_service.dart';
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

class _CampusCardAccountPageState extends State<CampusCardAccountPage>
    with WidgetsBindingObserver {
  final _openIdController = TextEditingController();
  final _bindCodeController = TextEditingController();
  bool _loaded = false;
  EcardOpenIdChannel _channel = EcardOpenIdChannel.wechat;
  bool _checking = false;
  bool _saving = false;
  bool _hijackBusy = false;
  bool _bindBusy = false;
  String? _inlineMessage;
  bool _inlineError = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _loaded) {
      // The VPN may have been disconnected in Settings while WeChat was open.
      unawaited(ServiceProvider.of(context).ecardBindService.refreshStatus());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_loadOpenId());
    // The tunnel outlives the page, so its state has to be re-read rather than
    // remembered.
    unawaited(ServiceProvider.of(context).ecardBindService.refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _openIdController.dispose();
    _bindCodeController.dispose();
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
    final bindService = ServiceProvider.of(context).ecardBindService;
    final theme = Theme.of(context);
    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final useIosChrome = isIos();
    final useLegacyIosChrome = usesLegacyIosChrome();
    final topInset = useIosChrome || useLegacyIosChrome
        ? 0.0
        : adaptiveTopBarHeight() + MediaQuery.viewPaddingOf(context).top;
    final busy = service.busy || _checking || _saving;

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
            ListenableBuilder(
              listenable: bindService,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('自动获取 OPENID', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (bindService.status == EcardBindHijackStatus.unsupported)
                    Text('当前平台暂不支持自动获取，请在下方手动填写 OPENID。', style: hintStyle)
                  else ...[
                    Text(
                      '1. 点「开启自动获取」并在系统弹窗里点「允许」。\n'
                      '2. 打开微信里的一卡通小程序，点首页顶部的「绑定码」入口，页面上会显示 6 位绑定码。\n'
                      '3. 把绑定码填到下面并点「获取 OPENID」，随后自动连接 eCard。',
                      style: hintStyle,
                    ),
                    if (isIos()) ...[
                      const SizedBox(height: 8),
                      Text(
                        '此功能会添加临时 VPN 配置，可能与现有 VPN 冲突。仅修改校园卡域名解析；获取后请停止自动获取。需要在 iPhone 真机上使用。',
                        style: hintStyle,
                      ),
                    ],
                    const SizedBox(height: 12),
                    AdaptiveButton(
                      key: const Key('ecard-bind-hijack-button'),
                      onPressed: busy || _hijackBusy
                          ? null
                          : () => unawaited(_toggleHijack(bindService)),
                      icon: Icons.vpn_lock_outlined,
                      sfSymbol: 'link',
                      label: bindService.hijackActive ? '停止自动获取' : '开启自动获取',
                      role: AdaptiveButtonRole.standard,
                      loading: _hijackBusy,
                      width: double.infinity,
                      accessibilityLabel:
                          bindService.hijackActive ? '停止自动获取' : '开启自动获取',
                    ),
                    const SizedBox(height: 8),
                    AdaptiveTextFieldGroup(
                      key: const Key('ecard-bind-code-field'),
                      items: [
                        AdaptiveTextFieldGroupItem(
                          controller: _bindCodeController,
                          placeholder: '绑定码（小程序内 6 位）',
                          textInputAction: TextInputAction.done,
                          enabled: !busy && !_bindBusy,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AdaptiveButton(
                      key: const Key('ecard-bind-redeem-button'),
                      onPressed: busy || _bindBusy
                          ? null
                          : () => unawaited(_redeem(service, bindService)),
                      icon: Icons.download_outlined,
                      sfSymbol: 'arrow.down.circle',
                      label: '获取 OPENID',
                      role: AdaptiveButtonRole.prominent,
                      loading: _bindBusy,
                      width: double.infinity,
                      accessibilityLabel: '用绑定码获取 OPENID',
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Expanded(child: Text('OPENID 渠道')),
                SizedBox(
                  width: 200,
                  child: IgnorePointer(
                    ignoring: busy,
                    child: AdaptiveSelect(
                      value: _channel.method,
                      width: 200,
                      options: [
                        for (final channel in EcardOpenIdChannel.values)
                          AdaptiveSelectOption(
                              value: channel.method, label: channel.label,),
                      ],
                      onChanged: (value) {
                        if (busy) return;
                        setState(() {
                          _channel = EcardOpenIdChannel.parse(value);
                          _inlineMessage = null;
                        });
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            AdaptiveTextFieldGroup(
              key: const Key('openid-field'),
              items: [
                AdaptiveTextFieldGroupItem(
                  controller: _openIdController,
                  placeholder: '${_channel.label} OPENID',
                  textInputAction: TextInputAction.done,
                  enabled: !busy,
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
              onPressed: busy ? null : () => unawaited(_save(service)),
              icon: Icons.save_outlined,
              sfSymbol: 'checkmark',
              label: service.configured ? '更新 eCard' : '连接 eCard',
              role: AdaptiveButtonRole.prominent,
              loading: _saving,
              width: double.infinity,
              accessibilityLabel: service.configured ? '更新 eCard' : '连接 eCard',
            ),
            const SizedBox(height: 8),
            AdaptiveButton(
              key: const Key('openid-check-button'),
              onPressed: busy ? null : () => unawaited(_check(service)),
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
              AdaptiveConfirmationButton(
                label: '移除 eCard',
                icon: Icons.link_off,
                sfSymbol: 'link.badge.minus',
                confirmTitle: '移除 eCard？',
                confirmLabel: '移除',
                destructive: true,
                width: double.infinity,
                onConfirmed: () => unawaited(_disconnect(service)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHijack(EcardBindService bindService) async {
    setState(() => _hijackBusy = true);
    try {
      final wasActive = bindService.hijackActive;
      final EcardBindHijackStatus status;
      if (wasActive) {
        await bindService.stopHijack();
        status = bindService.status;
      } else {
        status = await bindService.startHijack();
      }
      if (!mounted) return;
      if (status == EcardBindHijackStatus.denied) {
        setState(() {
          _inlineError = true;
          _inlineMessage = '未获得系统授权，无法开启自动获取';
        });
      } else if (status !=
          (wasActive
              ? EcardBindHijackStatus.inactive
              : EcardBindHijackStatus.active)) {
        // Starting can fail quietly (no tunnel, refused interface); say so
        // instead of leaving the button looking untouched.
        setState(() {
          _inlineError = true;
          _inlineMessage = wasActive ? '未能停止自动获取，请检查系统 VPN 设置' : '未能开启自动获取，请重试';
        });
      } else {
        setState(() {
          _inlineError = false;
          _inlineMessage = null;
        });
        // The tunnel being up is not proof it carries this app's lookups; verify
        // quietly and only report when it did not work.
        if (!wasActive) unawaited(_silentSelfCheck(bindService));
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      if (mounted) setState(() => _hijackBusy = false);
    }
  }

  /// Runs the diagnosis without a button and stays quiet on success. A failure
  /// is the only thing worth telling the user.
  Future<void> _silentSelfCheck(EcardBindService bindService) async {
    final diagnosis = await bindService.diagnose();
    if (!mounted) return;
    if (diagnosis.routesToBindService && diagnosis.reachable) return;
    setState(() {
      _inlineError = true;
      _inlineMessage = '自动获取尚未就绪，请稍后重试';
    });
  }

  /// Turns the code into an OPENID and connects with it. The code is one-shot,
  /// so the tunnel is dropped either way: a retry would need a fresh code from
  /// the mini program anyway.
  Future<void> _redeem(
    CampusCardService service,
    EcardBindService bindService,
  ) async {
    setState(() {
      _bindBusy = true;
      _inlineMessage = null;
    });
    try {
      final redeemed = await bindService.redeem(_bindCodeController.text);
      if (!mounted) return;
      setState(() {
        _openIdController.text = redeemed.openId;
        _channel = redeemed.channel;
      });
      await _save(service);
      await bindService.stopHijack();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      if (mounted) setState(() => _bindBusy = false);
    }
  }

  Future<void> _check(CampusCardService service) async {
    final openId = _openIdController.text.trim();
    setState(() {
      _checking = true;
      _inlineMessage = null;
    });
    try {
      await service.verifyOpenId(openId, channel: _channel);
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
    final openId = _openIdController.text.trim();
    setState(() {
      _saving = true;
      _inlineMessage = null;
    });
    try {
      await service.connect(openId, channel: _channel);
      if (!mounted) return;
      setState(() {
        _inlineError = false;
        _inlineMessage = 'eCard 已连接';
      });
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

  Future<void> _disconnect(CampusCardService service) async {
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
    }
  }

  String _safeMessage(Object error) {
    if (error is AppFailure) return error.safeMessage;
    if (error is FormatException) return 'OPENID 格式无效';
    return '无法验证 OPENID，请检查网络后重试';
  }
}
