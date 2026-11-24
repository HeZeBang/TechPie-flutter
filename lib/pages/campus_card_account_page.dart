import 'dart:async';

import 'package:flutter/material.dart';

import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../services/campus_card_service.dart';
import '../services/ecard_bind_hijack.dart';
import '../services/ecard_bind_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_text_field_group.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';

class CampusCardAccountPage extends StatefulWidget {
  const CampusCardAccountPage({super.key});

  @override
  State<CampusCardAccountPage> createState() => _CampusCardAccountPageState();
}

class _CampusCardAccountPageState extends State<CampusCardAccountPage> {
  final _openIdController = TextEditingController();
  final _bindCodeController = TextEditingController();
  bool _loaded = false;
  EcardOpenIdChannel _channel = EcardOpenIdChannel.wechat;
  bool _checking = false;
  bool _saving = false;
  bool _hijackBusy = false;
  bool _bindBusy = false;
  bool _disconnecting = false;
  String? _inlineMessage;
  bool _inlineError = false;

  bool get _operationBusy =>
      _checking || _saving || _hijackBusy || _bindBusy || _disconnecting;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loaded) return;
    _loaded = true;
    unawaited(_loadOpenId());
    unawaited(ServiceProvider.of(context).ecardBindService.refreshStatus());
  }

  @override
  void dispose() {
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
    final colors = context.tpColors;
    final service = ServiceProvider.of(context).campusCardService;
    final bindService = ServiceProvider.of(context).ecardBindService;
    bool isBusy() => service.busy || _operationBusy;
    final hintStyle = TpTypography.itemMeta(colors).copyWith(height: 1.45);
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: 'eCard',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '第三方账号',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回第三方账号',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => const BlurredAppBar(title: Text('eCard')),
      ),
      body: ListenableBuilder(
        listenable: service,
        builder: (context, _) => ListView(
          padding: EdgeInsets.fromLTRB(
            TpTokens.pageHorizontalPadding,
            topInset,
            TpTokens.pageHorizontalPadding,
            AppShellMetrics.bottomContentPaddingOf(context),
          ),
          children: [
            TpPageBody(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Overview Card
                  TpCard(
                    padding: const EdgeInsets.all(TpTokens.space4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colors.brandSoft,
                                borderRadius:
                                    BorderRadius.circular(TpTokens.radiusS),
                              ),
                              alignment: Alignment.center,
                              child: Icon(
                                TpIcons.wallet,
                                size: TpTokens.iconM,
                                color: colors.brand,
                              ),
                            ),
                            const SizedBox(width: TpTokens.space3),
                            Expanded(
                              child: Text(
                                'eCard',
                                style: TpTypography.cardTitle(colors)
                                    .copyWith(fontSize: 17),
                              ),
                            ),
                            TpBadge(
                              label: service.configured ? '已连接' : '未连接',
                              tone: service.configured
                                  ? TpBadgeTone.success
                                  : TpBadgeTone.muted,
                            ),
                          ],
                        ),
                        const SizedBox(height: TpTokens.space2),
                        Text(
                          '使用 OPENID 通过 GeekPie 会话服务连接 eCard。OPENID 保存在本机安全存储中；开启 Cloud sync 后会端到端加密同步。会话 Cookie 和离线密钥仍由各设备单独保存。',
                          style: hintStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: TpTokens.sectionGap),

                  // Auto-acquire Card
                  TpCard(
                    leadingIcon: TpIcons.scan,
                    title: '自动获取 OPENID',
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.cardPaddingHorizontal,
                      TpTokens.space1,
                      TpTokens.cardPaddingHorizontal,
                      TpTokens.space4,
                    ),
                    child: ListenableBuilder(
                      listenable: bindService,
                      builder: (context, _) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (bindService.status ==
                              EcardBindHijackStatus.unsupported)
                            Text(
                              '当前平台暂不支持自动获取，请在下方手动填写 OPENID。',
                              style: hintStyle,
                            )
                          else ...[
                            Text(
                              '1. 点「开启自动获取」并在系统弹窗里点「允许」。\n'
                              '2. 打开微信里的一卡通小程序，点首页顶部的「绑定码」入口，页面上会显示 6 位绑定码。\n'
                              '3. 把绑定码填到下面并点「获取 OPENID」，随后自动连接 eCard。',
                              style: hintStyle,
                            ),
                            if (showsIosVpnTunnelNotice()) ...[
                              const SizedBox(height: TpTokens.space2),
                              Text(
                                'iOS 会临时占用系统 VPN，可能暂停现有 VPN。绑定结束后自动关闭；若取消，请点「停止自动获取」。',
                                style: hintStyle,
                              ),
                            ],
                            const SizedBox(height: TpTokens.space3),
                            AdaptiveButton(
                              key: const Key('ecard-bind-hijack-button'),
                              onPressed: isBusy()
                                  ? null
                                  : () => unawaited(_toggleHijack(bindService)),
                              icon: TpIcons.lock,
                              sfSymbol: 'link',
                              label: bindService.hijackNeedsStop
                                  ? '停止自动获取'
                                  : '开启自动获取',
                              role: AdaptiveButtonRole.standard,
                              loading: _hijackBusy,
                              height: 44,
                              width: double.infinity,
                              accessibilityLabel: bindService.hijackNeedsStop
                                  ? '停止自动获取'
                                  : '开启自动获取',
                            ),
                            const SizedBox(height: TpTokens.space2),
                            AdaptiveTextFieldGroup(
                              key: const Key('ecard-bind-code-field'),
                              items: [
                                AdaptiveTextFieldGroupItem(
                                  controller: _bindCodeController,
                                  placeholder: '绑定码（小程序内 6 位）',
                                  textInputAction: TextInputAction.done,
                                  enabled: !isBusy(),
                                ),
                              ],
                            ),
                            const SizedBox(height: TpTokens.space2),
                            AdaptiveButton(
                              key: const Key('ecard-bind-redeem-button'),
                              onPressed: isBusy()
                                  ? null
                                  : () => unawaited(
                                        _redeem(service, bindService),
                                      ),
                              icon: TpIcons.download,
                              sfSymbol: 'arrow.down.circle',
                              label: '获取 OPENID',
                              role: AdaptiveButtonRole.prominent,
                              loading: _bindBusy,
                              height: 44,
                              width: double.infinity,
                              accessibilityLabel: '用绑定码获取 OPENID',
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: TpTokens.sectionGap),

                  // Manual Configuration Card
                  TpCard(
                    leadingIcon: TpIcons.sliders,
                    title: '手动配置 OPENID',
                    padding: const EdgeInsets.fromLTRB(
                      TpTokens.cardPaddingHorizontal,
                      TpTokens.space1,
                      TpTokens.cardPaddingHorizontal,
                      TpTokens.space4,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'OPENID 渠道',
                                style: TpTypography.itemTitle(colors)
                                    .copyWith(fontSize: 14.5),
                              ),
                            ),
                            const SizedBox(width: TpTokens.space3),
                            Flexible(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 180),
                                child: IgnorePointer(
                                  ignoring: isBusy(),
                                  child: AdaptiveSelect(
                                    value: _channel.method,
                                    width: 180,
                                    accessibilityLabel: 'OPENID 渠道',
                                    options: [
                                      for (final channel
                                          in EcardOpenIdChannel.values)
                                        AdaptiveSelectOption(
                                          value: channel.method,
                                          label: channel.label,
                                        ),
                                    ],
                                    onChanged: (value) {
                                      if (isBusy()) return;
                                      setState(() {
                                        _channel =
                                            EcardOpenIdChannel.parse(value);
                                        _inlineMessage = null;
                                      });
                                    },
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: TpTokens.space3),
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
                          const SizedBox(height: TpTokens.space3),
                          Container(
                            key: const Key('openid-inline-status'),
                            padding: const EdgeInsets.all(TpTokens.space3),
                            decoration: BoxDecoration(
                              color: (_inlineError
                                      ? colors.dangerRed
                                      : colors.successGreen)
                                  .withValues(
                                alpha: colors.isDark ? 0.16 : 0.10,
                              ),
                              borderRadius:
                                  BorderRadius.circular(TpTokens.radiusS),
                            ),
                            child: Text(
                              _inlineMessage!,
                              style: TpTypography.itemMeta(colors).copyWith(
                                color: _inlineError
                                    ? colors.dangerRed
                                    : colors.successGreen,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: TpTokens.space4),
                        AdaptiveButton(
                          key: const Key('openid-save-button'),
                          onPressed:
                              isBusy() ? null : () => unawaited(_save(service)),
                          icon: TpIcons.check,
                          sfSymbol: 'checkmark',
                          label: service.configured ? '更新 eCard' : '连接 eCard',
                          role: AdaptiveButtonRole.prominent,
                          loading: _saving,
                          height: 44,
                          width: double.infinity,
                          accessibilityLabel:
                              service.configured ? '更新 eCard' : '连接 eCard',
                        ),
                        const SizedBox(height: TpTokens.space2),
                        AdaptiveButton(
                          key: const Key('openid-check-button'),
                          onPressed: isBusy()
                              ? null
                              : () => unawaited(_check(service)),
                          icon: TpIcons.privacy,
                          sfSymbol: 'checkmark.shield',
                          label: '检查登录',
                          role: AdaptiveButtonRole.standard,
                          loading: _checking,
                          height: 44,
                          width: double.infinity,
                          accessibilityLabel: '检查 eCard 连接',
                        ),
                        if (service.configured) ...[
                          const SizedBox(height: TpTokens.space2),
                          IgnorePointer(
                            ignoring: isBusy(),
                            child: AdaptiveConfirmationButton(
                              label: '移除 eCard',
                              icon: TpIcons.delete,
                              sfSymbol: 'link.badge.minus',
                              confirmTitle: '移除 eCard？',
                              confirmLabel: '移除',
                              destructive: true,
                              width: double.infinity,
                              onConfirmed: () =>
                                  unawaited(_disconnect(service)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleHijack(EcardBindService bindService) async {
    if (_operationBusy || ServiceProvider.of(context).campusCardService.busy) {
      return;
    }
    setState(() => _hijackBusy = true);
    try {
      final wasActive = bindService.hijackNeedsStop;
      final EcardBindHijackStatus status;
      if (wasActive) {
        await bindService.stopHijack();
        status = EcardBindHijackStatus.inactive;
      } else {
        status = await bindService.startHijack();
      }
      if (!mounted) return;
      if (status == EcardBindHijackStatus.denied) {
        setState(() {
          _inlineError = true;
          _inlineMessage = '未获得系统授权，无法开启自动获取';
        });
      } else if (!wasActive && status != EcardBindHijackStatus.active) {
        setState(() {
          _inlineError = true;
          _inlineMessage = '未能开启自动获取，请重试';
        });
      } else {
        setState(() {
          _inlineError = false;
          _inlineMessage = null;
        });
        unawaited(_silentSelfCheck(bindService));
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

  Future<void> _silentSelfCheck(EcardBindService bindService) async {
    final diagnosis = await bindService.diagnose();
    if (!mounted || !bindService.hijackActive) return;
    if (diagnosis.routesToBindService && diagnosis.reachable) return;
    setState(() {
      _inlineError = true;
      _inlineMessage = '自动获取尚未就绪，请稍后重试';
    });
  }

  Future<void> _redeem(
    CampusCardService service,
    EcardBindService bindService,
  ) async {
    if (_operationBusy || service.busy) return;
    setState(() {
      _bindBusy = true;
      _inlineMessage = null;
    });
    var tunnelStopped = false;
    try {
      final redeemed = await bindService.redeem(_bindCodeController.text);
      if (!mounted) return;
      setState(() {
        _openIdController.text = redeemed.openId;
        _channel = redeemed.channel;
      });
      await bindService.stopHijack();
      tunnelStopped = true;
      if (!mounted) return;
      await _connect(service);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _inlineError = true;
        _inlineMessage = _safeMessage(error);
      });
    } finally {
      try {
        if (!tunnelStopped) await bindService.stopHijack();
      } catch (error) {
        if (mounted) {
          setState(() {
            _inlineError = true;
            _inlineMessage = _safeMessage(error);
          });
        }
      } finally {
        if (mounted) setState(() => _bindBusy = false);
      }
    }
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
      await ServiceProvider.of(context)
          .ecardBindService
          .prepareCampusConnection();
      if (!mounted) return;
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
    await ServiceProvider.of(context)
        .ecardBindService
        .prepareCampusConnection();
    if (!mounted) return;
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
