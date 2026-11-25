import 'dart:async';
import 'dart:ui';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/third_party_account.dart';
import '../models/user_session.dart';
import '../services/api_base_url.dart';
import '../services/auth_service.dart';
import '../services/deadline_widget_service.dart';
import '../services/feedback_service.dart';
import '../services/http_client.dart';
import '../services/island_service.dart';
import '../services/service_provider.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/theme_service.dart';
import '../services/uni_auth_service.dart';
import '../services/update_service.dart';
import '../theme/theme.dart';
import '../utils/adaptive_layout.dart';
import '../utils/platform.dart';
import '../utils/product_version.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_confirmation_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_select.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/desktop_popup.dart';
import '../widgets/ids_rebind_banner.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/uni_auth_login.dart';
import '../widgets/update_dialogs.dart';
import 'account_deletion_page.dart';
import 'debug_log_page.dart';
import 'debug_webview_page.dart';
import 'developer_lab_page.dart';
import 'feedback_page.dart';
import 'sync_settings_page.dart';
import 'third_party_accounts_page.dart';
import 'third_party_bind_page.dart';
import 'watch_settings_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String _appVersion = '';
  bool _checkingUpdate = false;
  bool? _isPersonalInfoBlurred;
  bool _wasVisible = false;
  IslandCapability? _islandCapability;

  /// The stack a settings subpage is pushed onto in a wide window. A field, not
  /// a local: a GlobalKey rebuilt every frame would drop the stack with it.
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadAppVersion());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ignore: deprecated_member_use
    final isVisible = TickerMode.of(context);
    if (isVisible && !_wasVisible) {
      _isPersonalInfoBlurred =
          ServiceProvider.of(context).storageService.maskPersonalInfo;
    }
    if (isVisible && !_wasVisible) unawaited(_loadIslandCapability());
    _wasVisible = isVisible;
  }

  Future<void> _loadIslandCapability() async {
    final island = ServiceProvider.of(context).islandService;
    if (island == null || !island.supported) return;
    final capability = await island.capability();
    if (mounted) setState(() => _islandCapability = capability);
  }

  Future<void> _setIslandEnabled(IslandService island, bool value) async {
    await island.setEnabled(value);
    if (!mounted) return;
    setState(() {});
    await _loadIslandCapability();
  }

  Future<void> _setDeadlineWidgetsEnabled(
    StorageService storage,
    DeadlineWidgetService widgetService,
    bool value,
  ) async {
    await storage.setDeadlineWidgetsEnabled(value);
    await widgetService.setEnabled(value);
    if (mounted) setState(() {});
  }

  String get _islandSubtitle {
    final capability = _islandCapability;
    if (capability == null) return '显示当前课程、下一节课和即将到期的截止日期';
    if (!capability.notificationsEnabled) return '请允许 TechPie 发送通知';
    return switch (capability.backend) {
      'hyper_island' => '通过 HyperOS 超级岛显示',
      'live_update' => '通过 Android 实时通知显示',
      _ => '通过普通常驻通知显示',
    };
  }

  void _togglePersonalInfoBlur() {
    setState(() {
      _isPersonalInfoBlurred = !(_isPersonalInfoBlurred ?? true);
    });
  }

  Future<void> _loadAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      if (info.version.isEmpty) {
        debugPrint(
          'PackageInfo returned an empty version '
          '(appName="${info.appName}", packageName="${info.packageName}", '
          'buildNumber="${info.buildNumber}")',
        );
      }
      setState(() {
        _appVersion = info.buildNumber.isNotEmpty
            ? '${info.version}+${info.buildNumber}'
            : info.version;
      });
    } catch (error) {
      debugPrint('PackageInfo.fromPlatform failed: $error');
    }
  }

  Future<void> _checkForUpdate() async {
    final updateService = ServiceProvider.of(context).updateService;
    final current = ProductVersion.tryParse(_appVersion);
    if (current == null) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: '无法检查更新',
        message: '当前版本号（$_appVersion）无法识别，没法与 GitHub 上的版本比较。',
        actions: const [AdaptiveAlertAction<void>(label: '好')],
      );
      return;
    }

    setState(() => _checkingUpdate = true);
    try {
      final release = await updateService.checkForUpdate(current);
      if (!mounted) return;

      if (release == null) {
        await showUpToDateDialog(context, _appVersion);
        return;
      }
      await showUpdateAvailableDialog(context, release);
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      await showUpdateFailureDialog(context, message: error.message);
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (usesSidebarLayout(context)) {
      return NavigatorPopHandler(
        onPopWithResult: (_) => _nestedNavigatorKey.currentState?.pop(),
        child: Navigator(
          key: _nestedNavigatorKey,
          onGenerateRoute: (settings) => adaptivePageRoute<void>(
            settings: settings,
            builder: (context) => _buildSettingsScaffold(context),
          ),
        ),
      );
    }

    return _buildSettingsScaffold(context);
  }

  Widget _buildSettingsScaffold(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final logger = sp.debugLogger;
    final storage = sp.storageService;
    final themeService = sp.themeService;
    final tpAuth = sp.thirdPartyAuthService;
    final campusCard = sp.campusCardService;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    return AdaptiveNavigationScaffold(
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => const IosNativeNavigationBar(
          title: '我的',
          largeTitleMode: true,
        ),
        material: () => const BlurredAppBar(title: Text('我的')),
      ),
      body: ColoredBox(
        color: colors.canvas,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            auth,
            logger,
            themeService,
            tpAuth,
            campusCard,
            sp.syncService,
            if (sp.spendingAlertService != null) sp.spendingAlertService!,
          ]),
          builder: (context, _) {
            final session = auth.session;
            final boundCount =
                tpAuth.boundPlatforms.length + (campusCard.configured ? 1 : 0);
            final island = sp.islandService;
            final spending = sp.spendingAlertService;
            final hasDeadlineWidgets = !kIsWeb &&
                defaultTargetPlatform == TargetPlatform.linux &&
                sp.deadlineWidgetService != null;
            final hasIsland = island != null && island.supported;
            final hasSpending = spending != null && spending.supported;
            final hasNotificationsGroup =
                hasDeadlineWidgets || hasIsland || hasSpending;

            return ListView(
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
                      if (tpAuth.needsIdsRebind ||
                          storage.debugForceIdsRebindBanner) ...[
                        IdsRebindBanner(
                          onRebind: () => unawaited(
                            pushAdaptivePage<void>(
                              context,
                              rootNavigator: true,
                              builder: (_) => const ThirdPartyBindPage(
                                platform: ThirdPartyPlatform.ids,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: TpTokens.sectionGap),
                      ],

                      // 1. 账号与隐私 hero card
                      _buildAccountSection(
                        context: context,
                        colors: colors,
                        auth: auth,
                        session: session,
                        syncService: sp.syncService,
                        storage: storage,
                        boundCount: boundCount,
                      ),
                      const SizedBox(height: TpTokens.sectionGap),

                      // 2. 外观与体验
                      _SettingsSectionCard(
                        title: '外观与体验',
                        children: [
                          _buildThemeModeRow(context, colors, themeService),
                          if (themeService.supportsColorSchemeSelection)
                            Builder(
                              builder: (tileContext) => TpListRow(
                                icon: TpIcons.sparkles,
                                iconColor: colors.brand,
                                title: '主题色',
                                value: _colorSubtitle(themeService),
                                showChevron: true,
                                showDivider: supportsAppleWatch(),
                                onTap: () =>
                                    _showColorPicker(tileContext, themeService),
                              ),
                            ),
                          if (supportsAppleWatch())
                            TpListRow(
                              icon: TpIcons.watch,
                              iconColor: colors.infoBlue,
                              title: 'Apple Watch',
                              showChevron: true,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => const WatchSettingsPage(),
                                ),
                              ),
                            ),
                        ],
                      ),

                      // 3. 通知与组件
                      if (hasNotificationsGroup) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        _SettingsSectionCard(
                          title: '通知与组件',
                          children: [
                            if (hasDeadlineWidgets)
                              TpListRow(
                                key: const ValueKey(
                                  'settings.deadline-widgets',
                                ),
                                icon: TpIcons.activities,
                                iconColor: colors.infoBlue,
                                title: '桌面小组件',
                                subtitle:
                                    '与桌面共享截止日期标题与时间；TechPie 关闭时展示本地缓存',
                                showDivider: hasIsland || hasSpending,
                                trailing: AdaptiveSwitch(
                                  value: storage.deadlineWidgetsEnabled,
                                  onChanged: (value) => unawaited(
                                    _setDeadlineWidgetsEnabled(
                                      storage,
                                      sp.deadlineWidgetService!,
                                      value,
                                    ),
                                  ),
                                ),
                                onTap: () => unawaited(
                                  _setDeadlineWidgetsEnabled(
                                    storage,
                                    sp.deadlineWidgetService!,
                                    !storage.deadlineWidgetsEnabled,
                                  ),
                                ),
                              ),
                            if (hasIsland)
                              TpListRow(
                                key: const ValueKey('settings.island'),
                                icon: TpIcons.bellRing,
                                iconColor: colors.brand,
                                title: '课程与截止日期通知',
                                subtitle: _islandSubtitle,
                                showDivider: hasSpending,
                                trailing: AdaptiveSwitch(
                                  value: storage.islandEnabled,
                                  onChanged: (value) =>
                                      unawaited(_setIslandEnabled(island, value)),
                                ),
                                onTap: () => unawaited(
                                  _setIslandEnabled(
                                    island,
                                    !storage.islandEnabled,
                                  ),
                                ),
                              ),
                            if (hasSpending)
                              TpListRow(
                                key: const ValueKey('settings.spending-alerts'),
                                icon: TpIcons.bell,
                                iconColor: colors.successGreen,
                                title: '校园卡消费提醒',
                                subtitle: '刷新发现新消费时通知；后台检查受系统调度限制',
                                trailing: AdaptiveSwitch(
                                  value: spending.enabled,
                                  onChanged: (value) =>
                                      unawaited(spending.setEnabled(value)),
                                ),
                                onTap: () => unawaited(
                                  spending.setEnabled(!spending.enabled),
                                ),
                              ),
                          ],
                        ),
                      ],

                      const SizedBox(height: TpTokens.sectionGap),

                      // 4. 网络与支持
                      _SettingsSectionCard(
                        title: '网络与支持',
                        children: [
                          if (!kIsWeb) ...[
                            TpListRow(
                              key: const ValueKey('settings.app-proxy-address'),
                              icon: TpIcons.globe,
                              iconColor: colors.infoBlue,
                              title: '应用代理',
                              subtitle: storage.appProxyEnabled &&
                                      storage.appProxyUrl.isNotEmpty
                                  ? storage.appProxyUrl
                                  : (storage.appProxyUrl.isNotEmpty
                                      ? '${storage.appProxyUrl}（未启用）'
                                      : '跟随系统默认'),
                              showChevron: true,
                              showDivider: true,
                              onTap: () => unawaited(
                                _showProxySettings(storage, sp.uniAuthService),
                              ),
                            ),
                            TpListRow(
                              key: const ValueKey('settings.app-proxy-enabled'),
                              icon: TpIcons.sliders,
                              iconColor: colors.infoBlue,
                              title: '启用应用代理',
                              subtitle: '通过已配置的 HTTP 代理转发应用请求',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: storage.appProxyEnabled &&
                                    storage.appProxyUrl.isNotEmpty,
                                onChanged: (value) => unawaited(
                                  _setProxyEnabled(
                                    storage,
                                    sp.uniAuthService,
                                    value,
                                  ),
                                ),
                              ),
                              onTap: () => unawaited(
                                _setProxyEnabled(
                                  storage,
                                  sp.uniAuthService,
                                  !(storage.appProxyEnabled &&
                                      storage.appProxyUrl.isNotEmpty),
                                ),
                              ),
                            ),
                          ],
                          TpListRow(
                            icon: TpIcons.feedback,
                            iconColor: colors.brand,
                            title: '问题反馈 / 功能建议',
                            showChevron: true,
                            showDivider: true,
                            onTap: () => unawaited(() async {
                              if (!auth.isLoggedIn) {
                                await startUniAuthLogin(context);
                              }
                              if (!context.mounted || !auth.isLoggedIn) return;
                              await pushAdaptivePage<void>(
                                context,
                                builder: (_) => FeedbackPage(
                                  service: FeedbackService(
                                    auth,
                                    apiBaseUrl(sp.storageService),
                                  ),
                                ),
                              );
                            }()),
                          ),
                          TpListRow(
                            icon: TpIcons.privacy,
                            iconColor: colors.successGreen,
                            title: '隐私政策与使用支持',
                            showDivider: true,
                            trailing: Icon(
                              TpIcons.externalLink,
                              size: TpTokens.iconS,
                              color: colors.textMuted,
                            ),
                            onTap: () => unawaited(
                              launchUrl(
                                Uri.parse('https://techpie.geekpie.club/privacy'),
                                mode: LaunchMode.externalApplication,
                              ),
                            ),
                          ),
                          TpListRow(
                            icon: TpIcons.info,
                            iconColor: colors.textMuted,
                            title: '关于 TechPie',
                            subtitle: _appVersion.isEmpty
                                ? '版本未知'
                                : '版本 $_appVersion · 点击检查更新',
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Icon(
                                    TpIcons.refresh,
                                    size: TpTokens.iconS,
                                    color: colors.textMuted,
                                  ),
                            onTap: _appVersion.isEmpty || _checkingUpdate
                                ? null
                                : () => unawaited(_checkForUpdate()),
                          ),
                        ],
                      ),

                      // 5. 账号管理 (signed-in only)
                      if (auth.isLoggedIn) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        _SettingsSectionCard(
                          title: '账号管理',
                          children: [
                            TpListRow(
                              icon: TpIcons.delete,
                              title: '注销账号',
                              destructive: true,
                              showChevron: true,
                              showDivider: true,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) =>
                                      AccountDeletionPage(auth: auth),
                                ),
                              ),
                            ),
                            AdaptiveNavigationScaffold.adaptiveChrome(
                              ios: () => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: TpTokens.cardPaddingHorizontal,
                                  vertical: TpTokens.space2,
                                ),
                                child: AdaptiveConfirmationButton(
                                  label: '退出登录',
                                  icon: TpIcons.logout,
                                  sfSymbol: 'rectangle.portrait.and.arrow.right',
                                  confirmTitle: '退出登录？',
                                  confirmLabel: '退出登录',
                                  destructive: true,
                                  width: double.infinity,
                                  height: 44,
                                  onConfirmed: () => unawaited(auth.logout()),
                                ),
                              ),
                              material: () => TpListRow(
                                icon: TpIcons.logout,
                                title: '退出登录',
                                destructive: true,
                                onTap: () => unawaited(_confirmLogout(auth)),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 6. 开发者选项 (non-release only)
                      if (!kReleaseMode) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        _SettingsSectionCard(
                          title: '开发者选项',
                          children: [
                            TpListRow(
                              key: const ValueKey('settings.ids-rebind-preview'),
                              icon: TpIcons.lock,
                              iconColor: colors.warningAmber,
                              title: '强制显示 IDS 重绑横幅',
                              subtitle: '仅用于调试迁移提示',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: storage.debugForceIdsRebindBanner,
                                onChanged: (value) {
                                  unawaited(
                                    storage.setDebugForceIdsRebindBanner(value),
                                  );
                                  setState(() {});
                                },
                              ),
                              onTap: () {
                                final next = !storage.debugForceIdsRebindBanner;
                                unawaited(
                                  storage.setDebugForceIdsRebindBanner(next),
                                );
                                setState(() {});
                              },
                            ),
                            TpListRow(
                              key: const ValueKey('settings.debug-mode'),
                              icon: TpIcons.bug,
                              iconColor: colors.warningAmber,
                              title: '调试模式',
                              subtitle: '记录所有 API 请求日志',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: logger.enabled,
                                onChanged: (value) {
                                  logger.enabled = value;
                                  unawaited(storage.setDebugMode(value));
                                },
                              ),
                              onTap: () {
                                final next = !logger.enabled;
                                logger.enabled = next;
                                unawaited(storage.setDebugMode(next));
                              },
                            ),
                            TpListRow(
                              key: const ValueKey('settings.use-localhost'),
                              icon: TpIcons.classroom,
                              iconColor: colors.infoBlue,
                              title: '本地测试服务器',
                              subtitle: isAndroid()
                                  ? '通过 10.0.2.2:3000 连接本地服务'
                                  : '连接本地开发服务器',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: storage.useLocalhost,
                                onChanged: (value) {
                                  unawaited(storage.setUseLocalhost(value));
                                  setState(() {});
                                },
                              ),
                              onTap: () {
                                final next = !storage.useLocalhost;
                                unawaited(storage.setUseLocalhost(next));
                                setState(() {});
                              },
                            ),
                            TpListRow(
                              icon: TpIcons.code,
                              iconColor: colors.textSecondary,
                              title: 'WebView 调试',
                              subtitle: '桥接注入与自定义地址测试',
                              showChevron: true,
                              showDivider: true,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => const DebugWebViewPage(
                                    initialUrl:
                                        'http://127.0.0.1:8000/bridge_test.html',
                                  ),
                                ),
                              ),
                            ),
                            TpListRow(
                              icon: TpIcons.activity,
                              iconColor: colors.textSecondary,
                              title: '震动与音效实验室',
                              subtitle: '预览触觉波形与提示音效',
                              showChevron: true,
                              showDivider: logger.enabled,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => const DeveloperLabPage(),
                                ),
                              ),
                            ),
                            if (logger.enabled)
                              TpListRow(
                                icon: TpIcons.document,
                                iconColor: colors.brand,
                                title: '查看日志',
                                subtitle: '共 ${logger.entries.length} 条记录',
                                showChevron: true,
                                onTap: () => unawaited(
                                  pushAdaptivePage<void>(
                                    context,
                                    builder: (_) => const DebugLogPage(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildAccountSection({
    required BuildContext context,
    required TpColors colors,
    required AuthService auth,
    required UserSession? session,
    required SyncService syncService,
    required StorageService storage,
    required int boundCount,
  }) {
    final blurred = _isPersonalInfoBlurred ?? true;

    return TpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session != null)
            Semantics(
              button: true,
              label: blurred ? '个人信息已模糊，点击显示' : '个人信息已显示，点击隐藏',
              child: InkWell(
                onTap: _togglePersonalInfoBlur,
                splashColor: colors.brandSoft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space4,
                    TpTokens.cardPaddingHorizontal,
                    TpTokens.space3,
                  ),
                  child: Row(
                    children: [
                      TpAvatarBadge(
                        text: _avatarInitials(session, blurred),
                        size: 46,
                      ),
                      const SizedBox(width: TpTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(
                                      sigmaX: 8,
                                      sigmaY: 8,
                                    ),
                                    enabled: blurred,
                                    child: Text(
                                      session.userName.isNotEmpty
                                          ? session.userName
                                          : session.userId,
                                      style: TpTypography.cardTitle(colors)
                                          .copyWith(fontSize: 17),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: TpTokens.space2),
                                const TpBadge(
                                  label: '在线',
                                  tone: TpBadgeTone.success,
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              enabled: blurred,
                              child: Text(
                                [
                                  'GeekPie Uni-Auth',
                                  if (session.userId.isNotEmpty) session.userId,
                                ].join(' · '),
                                style: TpTypography.itemMeta(colors),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          blurred ? TpIcons.eyeOff : TpIcons.eye,
                          size: TpTokens.iconM,
                          color: colors.textMuted,
                        ),
                        tooltip: blurred ? '显示个人信息' : '隐藏个人信息',
                        onPressed: _togglePersonalInfoBlur,
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TpTokens.cardPaddingHorizontal,
                TpTokens.space4,
                TpTokens.cardPaddingHorizontal,
                TpTokens.space3,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const TpAvatarBadge(text: 'GP', size: 46),
                      const SizedBox(width: TpTokens.space3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '登录 TechPie',
                              style: TpTypography.cardTitle(colors)
                                  .copyWith(fontSize: 17),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '通过 GeekPie Uni-Auth 同步课表与校园服务',
                              style: TpTypography.itemMeta(colors),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: TpTokens.space3),
                  AdaptiveButton(
                    icon: TpIcons.login,
                    sfSymbol: 'person.crop.circle.badge.plus',
                    label: '通过 GeekPie Uni-Auth 登录',
                    role: AdaptiveButtonRole.prominent,
                    height: 44,
                    accessibilityLabel: '登录 TechPie',
                    onPressed: () => unawaited(startUniAuthLogin(context)),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: TpTokens.cardPaddingHorizontal,
            ),
            child: Divider(height: 1, thickness: 0.5, color: colors.divider),
          ),
          TpListRow(
            icon: TpIcons.linkedAccounts,
            iconColor: colors.brand,
            title: '第三方账号',
            subtitle:
                '已绑定 $boundCount 项 · 校园卡 / eGate / Gradescope / Hydro',
            showChevron: true,
            showDivider: true,
            onTap: () => unawaited(
              pushAdaptivePage<void>(
                context,
                builder: (_) => const ThirdPartyAccountsPage(),
              ),
            ),
          ),
          if (auth.isLoggedIn)
            TpListRow(
              icon: TpIcons.sync,
              iconColor: colors.infoBlue,
              title: '云同步',
              subtitle: _cloudSyncSubtitle(syncService),
              showChevron: true,
              showDivider: true,
              onTap: () => unawaited(
                pushAdaptivePage<void>(
                  context,
                  builder: (_) => const SyncSettingsPage(),
                ),
              ),
            ),
          TpListRow(
            key: const ValueKey('settings.mask-personal-info'),
            icon: TpIcons.eyeOff,
            iconColor: colors.textSecondary,
            title: '默认模糊个人信息',
            subtitle: '保护姓名与学号等隐私信息，点击可临时查看',
            trailing: AdaptiveSwitch(
              value: storage.maskPersonalInfo,
              onChanged: (value) {
                unawaited(storage.setMaskPersonalInfo(value));
                setState(() {
                  _isPersonalInfoBlurred = value;
                });
              },
            ),
            onTap: () {
              final next = !storage.maskPersonalInfo;
              unawaited(storage.setMaskPersonalInfo(next));
              setState(() {
                _isPersonalInfoBlurred = next;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildThemeModeRow(
    BuildContext context,
    TpColors colors,
    ThemeService themeService,
  ) {
    final hasNext =
        themeService.supportsColorSchemeSelection || supportsAppleWatch();
    return AdaptiveNavigationScaffold.adaptiveChrome(
      ios: () => TpListRow(
        icon: _themeModeIcon(themeService.mode),
        iconColor: colors.brand,
        title: '主题模式',
        showDivider: hasNext,
        trailing: AdaptiveSelect(
          value: themeService.mode.name,
          placeholder: '选择主题',
          accessibilityLabel: '主题模式',
          shrinkWrap: true,
          options: [
            for (final mode in AppThemeMode.values)
              AdaptiveSelectOption(
                value: mode.name,
                label: mode.label,
                sfSymbol: switch (mode) {
                  AppThemeMode.system => 'circle.lefthalf.filled',
                  AppThemeMode.light => 'sun.max',
                  AppThemeMode.dark => 'moon',
                  AppThemeMode.amoled => 'moon.fill',
                },
              ),
          ],
          onChanged: (value) {
            final mode = AppThemeMode.values.firstWhere(
              (item) => item.name == value,
              orElse: () => AppThemeMode.system,
            );
            unawaited(themeService.setMode(mode));
          },
        ),
      ),
      material: () => Builder(
        builder: (tileContext) => TpListRow(
          icon: _themeModeIcon(themeService.mode),
          iconColor: colors.brand,
          title: '主题模式',
          value: themeService.mode.label,
          showChevron: true,
          showDivider: hasNext,
          onTap: () => _showThemePicker(tileContext, themeService),
        ),
      ),
    );
  }

  IconData _themeModeIcon(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => TpIcons.smartphone,
        AppThemeMode.light => TpIcons.sun,
        AppThemeMode.dark => TpIcons.moon,
        AppThemeMode.amoled => TpIcons.amoled,
      };

  String _avatarInitials(UserSession session, bool blurred) {
    if (blurred) return 'GP';
    final name = session.userName.trim();
    if (name.isEmpty) return 'GP';
    final runes = name.runes.toList();
    if (runes.first > 127) {
      return String.fromCharCode(runes.first);
    }
    return name.substring(0, name.length >= 2 ? 2 : 1).toUpperCase();
  }

  Future<void> _confirmLogout(AuthService auth) async {
    final ok = await showAdaptiveAlertDialog<bool>(
      context: context,
      title: '退出登录',
      message: '将清除当前设备上的登录状态和相关缓存数据。',
      actions: const [
        AdaptiveAlertAction<bool>(label: '取消', value: false),
        AdaptiveAlertAction<bool>(
          label: '退出登录',
          value: true,
          isDestructive: true,
        ),
      ],
    );

    if (ok == true) {
      await auth.logout();
    }
  }

  Future<void> _setProxyEnabled(
    StorageService storage,
    UniAuthService uniAuth,
    bool value,
  ) async {
    if (value) {
      final normalized = normalizeAppProxy(storage.appProxyUrl);
      if (!isValidAppProxy(normalized)) {
        await _showProxySettings(storage, uniAuth);
        return;
      }
      await storage.setAppProxyUrl(normalized);
      await storage.setAppProxyEnabled(true);
      configureAppProxy(normalized);
      uniAuth.setProxyUrl(normalized);
    } else {
      await storage.setAppProxyEnabled(false);
      configureAppProxy('');
      uniAuth.setProxyUrl('');
    }
    if (mounted) setState(() {});
  }

  Future<void> _showProxySettings(
    StorageService storage,
    UniAuthService uniAuth,
  ) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) => _ProxySettingsDialog(initialValue: storage.appProxyUrl),
    );
    if (value == null || !mounted) return;
    final proxy = normalizeAppProxy(value);
    if (proxy.isNotEmpty && !isValidAppProxy(proxy)) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: '代理地址无效',
        message: '请使用 host:port 格式，例如 127.0.0.1:7890。',
        actions: const [AdaptiveAlertAction<void>(label: '好')],
      );
      return;
    }
    await storage.setAppProxyUrl(proxy);
    await storage.setAppProxyEnabled(proxy.isNotEmpty);
    configureAppProxy(proxy);
    uniAuth.setProxyUrl(proxy);
    if (mounted) setState(() {});
  }

  void _showThemePicker(BuildContext context, ThemeService themeService) {
    if (usesSidebarLayout(context)) {
      showDesktopPopover(
        anchorContext: context,
        width: 260,
        placement: DesktopPopoverPlacement.belowEnd,
        offset: const Offset(0, 8),
        scrollable: true,
        builder: (context, close) {
          final theme = Theme.of(context);
          return DesktopPopoverSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text('选择主题模式', style: theme.textTheme.titleSmall),
                ),
                const Divider(height: 1),
                _ThemeModeOptions(
                  themeService: themeService,
                  desktop: true,
                  onSelected: (mode) {
                    unawaited(themeService.setMode(mode));
                    close();
                  },
                ),
              ],
            ),
          );
        },
      );
      return;
    }

    unawaited(
      CNBottomSheet.show<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  '选择主题模式',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              _ThemeModeOptions(
                themeService: themeService,
                onSelected: (mode) {
                  unawaited(themeService.setMode(mode));
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: TpTokens.space2),
            ],
          ),
        ),
      ),
    );
  }

  String _colorSubtitle(ThemeService themeService) {
    if (themeService.colorScheme == AppColorScheme.system) {
      if (themeService.usesIosSystemAccent) {
        return '系统蓝';
      }
      if (!themeService.systemDynamicColorAvailable) {
        return '${themeService.colorScheme.label}（不可用，已回退 TechRed）';
      }
    }
    return themeService.colorScheme.label;
  }

  void _showColorPicker(BuildContext context, ThemeService themeService) {
    if (usesSidebarLayout(context)) {
      showDesktopPopover(
        anchorContext: context,
        width: 260,
        placement: DesktopPopoverPlacement.belowEnd,
        offset: const Offset(0, 8),
        builder: (context, close) {
          final theme = Theme.of(context);
          final colors = context.tpColors;
          return DesktopPopoverSurface(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                  child: Text('选择主题色', style: theme.textTheme.titleSmall),
                ),
                const Divider(height: 1),
                for (final scheme in AppColorScheme.values)
                  DesktopMenuRow(
                    leading: Icon(scheme.icon, size: 20),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            scheme.label,
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                        if (themeService.colorScheme == scheme)
                          Icon(
                            TpIcons.check,
                            size: TpTokens.iconS,
                            color: colors.brand,
                          ),
                      ],
                    ),
                    onTap: () {
                      unawaited(themeService.setColorScheme(scheme));
                      close();
                    },
                  ),
              ],
            ),
          );
        },
      );
      return;
    }

    unawaited(
      CNBottomSheet.show<void>(
        context: context,
        useRootNavigator: true,
        builder: (context) {
          final colors = context.tpColors;
          return SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    '选择主题色',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                for (final scheme in AppColorScheme.values)
                  TpListRow(
                    icon: scheme.icon,
                    iconColor: themeService.colorScheme == scheme
                        ? colors.brand
                        : colors.textMuted,
                    title: scheme.label,
                    trailing: themeService.colorScheme == scheme
                        ? Icon(
                            TpIcons.check,
                            size: TpTokens.iconS,
                            color: colors.brand,
                          )
                        : null,
                    onTap: () {
                      unawaited(themeService.setColorScheme(scheme));
                      Navigator.pop(context);
                    },
                  ),
                const SizedBox(height: TpTokens.space2),
              ],
            ),
          );
        },
      ),
    );
  }

  String _cloudSyncSubtitle(SyncService sync) {
    if (!sync.enabled) return '未开启';
    final at = sync.lastSyncAt;
    if (at == null) return '已开启 · 尚未同步';
    return '已开启 · 上次同步 ${_shortTime(at)}';
  }

  String _shortTime(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}';
  }
}

class _SettingsSectionCard extends StatelessWidget {
  const _SettingsSectionCard({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TpTokens.space2,
            0,
            TpTokens.space2,
            TpTokens.space2,
          ),
          child: Text(
            title,
            style: TpTypography.cardMeta(colors).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _ThemeModeOptions extends StatelessWidget {
  const _ThemeModeOptions({
    required this.themeService,
    required this.onSelected,
    this.desktop = false,
  });

  final ThemeService themeService;
  final ValueChanged<AppThemeMode> onSelected;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.tpColors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final mode in AppThemeMode.values)
          if (desktop)
            DesktopMenuRow(
              leading: Icon(mode.icon, size: 20),
              title: Row(
                children: [
                  Expanded(
                    child: Text(mode.label, style: theme.textTheme.bodyMedium),
                  ),
                  if (themeService.mode == mode)
                    Icon(
                      TpIcons.check,
                      size: TpTokens.iconS,
                      color: colors.brand,
                    ),
                ],
              ),
              onTap: () => onSelected(mode),
            )
          else
            TpListRow(
              icon: mode.icon,
              iconColor: themeService.mode == mode
                  ? colors.brand
                  : colors.textMuted,
              title: mode.label,
              trailing: themeService.mode == mode
                  ? Icon(
                      TpIcons.check,
                      size: TpTokens.iconS,
                      color: colors.brand,
                    )
                  : null,
              onTap: () => onSelected(mode),
            ),
      ],
    );
  }
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog({required this.initialValue});

  final String initialValue;

  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('应用代理'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: '127.0.0.1:7890'),
        keyboardType: TextInputType.url,
        onSubmitted: (value) => Navigator.pop(context, value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
