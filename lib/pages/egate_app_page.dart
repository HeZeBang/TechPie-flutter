import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/egate_app_service.dart';
import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_feedback.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/page_refresh.dart';
import '../widgets/scanner/scan_page.dart';
import '../widgets/uni_auth_login.dart';
import 'third_party_accounts_page.dart';

/// "校园签到" — queries the egate-app (xshdapp) sign-in announcement +
/// history and lets the user submit a check-in for a scanned WID. Session
/// cookies are derived from the ids binding (see EgateAppService), so
/// this page mirrors OaGymPage's ready/unready gating.
class EgateAppPage extends StatefulWidget {
  const EgateAppPage({super.key});

  @override
  State<EgateAppPage> createState() => _EgateAppPageState();
}

class _EgateAppPageState extends State<EgateAppPage> {
  bool _loading = false;
  bool _submitting = false;
  String? _error;
  String? _message;
  List<EgateAppSignRecord> _history = const [];
  bool _loadedOnce = false;
  String? _loadedIdentity;

  String _friendlyError(Object e, {String fallback = '操作失败，请重试'}) {
    final text = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '').trim();
    return text.isEmpty ? fallback : text;
  }

  Future<void> _handlePrerequisite() async {
    final sp = ServiceProvider.of(context);
    if (sp.authService.isLoggedIn) {
      await _openThirdPartyAccounts();
      return;
    }
    await startUniAuthLogin(context);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _openThirdPartyAccounts() async {
    await pushAdaptivePage<void>(
      context,
      builder: (_) => const ThirdPartyAccountsPage(),
    );
  }

  Future<void> _refresh(EgateAppService service) async {
    final requestIdentity = _loadedIdentity;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        service.fetchSignMessage(),
        service.fetchSignHistory(),
      ]);
      if (!mounted || requestIdentity != _loadedIdentity) return;
      setState(() {
        _message = results[0] as String;
        _history = results[1] as List<EgateAppSignRecord>;
      });
    } catch (e) {
      if (!mounted || requestIdentity != _loadedIdentity) return;
      setState(() => _error = _friendlyError(e, fallback: '加载校园签到失败，请重试'));
    } finally {
      if (mounted && requestIdentity == _loadedIdentity) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _submitCheckin(EgateAppService service, String wid) async {
    if (_submitting) return;
    final requestIdentity = _loadedIdentity;
    setState(() => _submitting = true);
    try {
      final result = await service.submitCheckin(wid);
      if (!mounted || requestIdentity != _loadedIdentity) return;
      showAdaptiveFeedback(
        context: context,
        message: result.message,
        style: AdaptiveFeedbackStyle.success,
      );
      unawaited(_refresh(service));
    } catch (e) {
      if (!mounted || requestIdentity != _loadedIdentity) return;
      showAdaptiveFeedback(
        context: context,
        message: _friendlyError(e, fallback: '签到提交失败，请重试'),
        style: AdaptiveFeedbackStyle.error,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _scanQrCode(EgateAppService service) async {
    if (_submitting) return;
    final runtime = ServiceProvider.of(context).campusCardService.runtime;
    final wid = await showTechPieScanner(
      context,
      scanner: runtime.scanner,
      lifecycle: runtime.lifecycle,
      feedback: runtime.feedback,
      title: '扫描签到二维码',
      hint: '将二维码放入框内，即可自动扫描',
    );
    if (wid == null || wid.isEmpty || !mounted) return;
    unawaited(_submitCheckin(service, wid));
  }

  Future<void> _enterWidManually(EgateAppService service) async {
    if (_submitting) return;
    final controller = TextEditingController();
    final wid = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        final colors = dialogContext.tpColors;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final canSubmit = controller.text.trim().isNotEmpty;
            return AlertDialog(
              title: const Text('手动输入签到内容'),
              content: TextField(
                controller: controller,
                autofocus: true,
                maxLines: 4,
                minLines: 1,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setDialogState(() {}),
                onSubmitted: (value) {
                  if (value.trim().isNotEmpty) {
                    Navigator.of(dialogContext).pop(value.trim());
                  }
                },
                decoration: const InputDecoration(
                  hintText: '粘贴或输入二维码内容 (WID)',
                ),
              ),
              actions: [
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textSecondary,
                  ),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: canSubmit
                      ? () =>
                          Navigator.of(dialogContext).pop(controller.text.trim())
                      : null,
                  child: const Text('提交'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    if (wid == null || wid.isEmpty || !mounted) return;
    unawaited(_submitCheckin(service, wid));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final tpAuth = sp.thirdPartyAuthService;
    final service = sp.egateAppService;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space4,
    );
    // Mobile camera scanning runs on Android / iOS / OHOS; desktop keeps manual.
    final canScanWithCamera = !kIsWeb && !isDesktop();

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '校园签到',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '首页',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回首页',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => BlurredAppBar(
          title: const Text('校园签到'),
          actions: [
            if (isDesktop())
              ListenableBuilder(
                listenable: Listenable.merge([auth, tpAuth]),
                builder: (context, _) => PageRefreshButton(
                  onRefresh: () => _refresh(service),
                  enabled: auth.isLoggedIn && tpAuth.hasIdsBinding,
                  refreshing: _loading,
                ),
              ),
          ],
        ),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, tpAuth]),
        builder: (context, _) {
          final ready = auth.isLoggedIn && tpAuth.hasIdsBinding;
          final identity = ready
              ? '${auth.session?.userId ?? ''}|${tpAuth.idsStudentId}'
              : null;
          if (identity != _loadedIdentity) {
            _loadedIdentity = identity;
            _loadedOnce = false;
            _message = null;
            _history = const [];
            _error = null;
            _loading = false;
          }
          if (!ready) {
            return ListView(
              padding: EdgeInsets.fromLTRB(
                TpTokens.pageHorizontalPadding,
                topInset,
                TpTokens.pageHorizontalPadding,
                AppShellMetrics.bottomContentPaddingOf(context),
              ),
              children: [
                TpPageBody(
                  child: TpCard(
                    padding: const EdgeInsets.all(TpTokens.space5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: colors.opaqueBrandContainer,
                            borderRadius:
                                BorderRadius.circular(TpTokens.radiusM),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            TpIcons.calendarCheck,
                            size: TpTokens.iconL,
                            color: colors.brandInk,
                          ),
                        ),
                        const SizedBox(height: TpTokens.space4),
                        Text(
                          auth.isLoggedIn ? '需要绑定 IDS 账号' : '需要先登录 TechPie',
                          style: TpTypography.cardTitle(colors)
                              .copyWith(fontSize: 18),
                        ),
                        const SizedBox(height: TpTokens.space2),
                        Text(
                          auth.isLoggedIn
                              ? '校园签到复用 IDS 绑定的校园网登录态，请在「第三方账号」中绑定 IDS 后再使用。'
                              : '校园签到复用 IDS 绑定的校园网登录态，不需要单独保存密码。',
                          style: TpTypography.itemMeta(colors).copyWith(
                            fontSize: 13.5,
                            height: 1.45,
                          ),
                        ),
                        const SizedBox(height: TpTokens.space4),
                        AdaptiveButton(
                          onPressed: _handlePrerequisite,
                          icon: auth.isLoggedIn
                              ? TpIcons.linkedAccounts
                              : TpIcons.login,
                          sfSymbol: auth.isLoggedIn
                              ? 'key.horizontal'
                              : 'person.crop.circle.badge.plus',
                          label: auth.isLoggedIn ? '去绑定 IDS' : '去登录',
                          role: AdaptiveButtonRole.prominent,
                          height: 46,
                          accessibilityLabel:
                              auth.isLoggedIn ? '前往绑定 IDS' : '登录 TechPie',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          if (!_loadedOnce) {
            _loadedOnce = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) unawaited(_refresh(service));
            });
          }

          return PageRefreshIndicator(
            onRefresh: () async => _refresh(service),
            child: ListView(
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
                      if (_error != null) ...[
                        TpCard(
                          color: colors.opaqueDangerContainer,
                          borderColor:
                              colors.dangerRed.withValues(alpha: 0.35),
                          padding: const EdgeInsets.all(TpTokens.space4),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                TpIcons.info,
                                size: TpTokens.iconM,
                                color: colors.dangerRed,
                              ),
                              const SizedBox(width: TpTokens.space3),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TpTypography.itemMeta(colors)
                                      .copyWith(color: colors.textPrimary),
                                ),
                              ),
                              TextButton(
                                onPressed: _loading
                                    ? null
                                    : () => unawaited(_refresh(service)),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: TpTokens.sectionGap),
                      ],
                      TpCard(
                        leadingIcon: TpIcons.bell,
                        title: '当前公告',
                        padding: const EdgeInsets.fromLTRB(
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space1,
                          TpTokens.cardPaddingHorizontal,
                          TpTokens.space4,
                        ),
                        child: Text(
                          _loading
                              ? '加载中…'
                              : (_message?.isNotEmpty == true
                                  ? _message!
                                  : '暂无签到公告'),
                          style: TpTypography.itemMeta(colors).copyWith(
                            fontSize: 13.5,
                            color: colors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                      const SizedBox(height: TpTokens.sectionGap),
                      Row(
                        children: [
                          if (canScanWithCamera) ...[
                            Expanded(
                              child: AdaptiveButton(
                                onPressed: _submitting
                                    ? null
                                    : () => unawaited(_scanQrCode(service)),
                                icon: TpIcons.qrCode,
                                sfSymbol: 'qrcode.viewfinder',
                                label: '扫码签到',
                                role: AdaptiveButtonRole.prominent,
                                loading: _submitting,
                                height: 46,
                              ),
                            ),
                            const SizedBox(width: TpTokens.space3),
                          ],
                          Expanded(
                            child: AdaptiveButton(
                              onPressed: _submitting
                                  ? null
                                  : () => unawaited(_enterWidManually(service)),
                              icon: TpIcons.edit,
                              sfSymbol: 'keyboard',
                              label: '手动输入',
                              role: canScanWithCamera
                                  ? AdaptiveButtonRole.standard
                                  : AdaptiveButtonRole.prominent,
                              loading: _submitting && !canScanWithCamera,
                              height: 46,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: TpTokens.sectionGap),
                      TpCard(
                        leadingIcon: TpIcons.calendarCheck,
                        title: '签到历史',
                        trailing: _history.isEmpty
                            ? null
                            : TpBadge(
                                label: '${_history.length} 条',
                                tone: TpBadgeTone.muted,
                              ),
                        child: _history.isEmpty && !_loading
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  TpTokens.cardPaddingHorizontal,
                                  TpTokens.space2,
                                  TpTokens.cardPaddingHorizontal,
                                  TpTokens.space5,
                                ),
                                child: Text(
                                  '暂无签到记录',
                                  style: TpTypography.itemMeta(colors),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : Column(
                                children: [
                                  for (var i = 0; i < _history.length; i++)
                                    TpListRow(
                                      icon: TpIcons.checkCircle,
                                      title: _history[i].activityName,
                                      subtitle: [
                                        _history[i].typeDisplay,
                                        if (_history[i].date != null)
                                          _history[i].date!,
                                      ].where((s) => s.isNotEmpty).join(' · '),
                                      trailing: _history[i]
                                              .statusDisplay
                                              .isEmpty
                                          ? null
                                          : TpBadge(
                                              label: _history[i].statusDisplay,
                                              tone: TpBadgeTone.success,
                                            ),
                                      showDivider: i < _history.length - 1,
                                    ),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
