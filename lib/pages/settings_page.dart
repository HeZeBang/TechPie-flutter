import 'dart:async';

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
import '../utils/user_display_name.dart';
import '../widgets/adaptive_alert_dialog.dart';
import '../widgets/adaptive_button.dart';
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
import 'developer_options_page.dart';
import 'feedback_page.dart';
import 'huawei_watch_page.dart';
import 'sync_settings_page.dart';
import 'third_party_accounts_page.dart';
import 'third_party_bind_page.dart';
import 'watch_settings_page.dart';
import 'wearables_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// The stack a settings subpage is pushed onto in the tablet (600–959dp)
  /// band. On desktop (>= 960dp), DesktopShell already wraps this tab in a
  /// content Navigator, so mounting a second one would be redundant.
  final _nestedNavigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    if (usesSidebarLayout(context) && !usesDesktopSidebarShell(context)) {
      return NavigatorPopHandler(
        onPopWithResult: (_) => _nestedNavigatorKey.currentState?.pop(),
        child: Navigator(
          key: _nestedNavigatorKey,
          onGenerateRoute: (settings) => adaptivePageRoute<void>(
            settings: settings,
            builder: (_) => const _SettingsBody(),
          ),
        ),
      );
    }

    return const _SettingsBody();
  }
}

class _SettingsBody extends StatefulWidget {
  const _SettingsBody();

  @override
  State<_SettingsBody> createState() => _SettingsBodyState();
}

class _SettingsBodyState extends State<_SettingsBody> {
  String _appVersion = '';
  bool _checkingUpdate = false;
  bool _wasVisible = false;
  IslandCapability? _islandCapability;

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
      debugPrint('PackageInfo.fromPlatform failed: ${error.runtimeType}');
    }
  }

  Future<void> _checkForUpdate() async {
    final updateService = ServiceProvider.of(context).updateService;
    final source = updateService.source;
    final current = ProductVersion.tryParse(_appVersion);
    if (current == null) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: '无法检查更新',
        message: '无法识别当前版本号（$_appVersion）。',
        actions: const [AdaptiveAlertAction<void>(label: '好')],
      );
      return;
    }

    setState(() => _checkingUpdate = true);
    try {
      final release = await updateService.checkForUpdate(
        current,
        source: source,
      );
      if (!mounted) return;

      if (release == null) {
        await showUpToDateDialog(context, _appVersion, source: source);
        return;
      }
      await showUpdateAvailableDialog(context, release);
    } on UpdateCheckException catch (error) {
      if (!mounted) return;
      await showUpdateFailureDialog(
        context,
        message: error.message,
        source: source,
      );
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  @override
  Widget build(BuildContext context) => _buildSettingsScaffold(context);

  Widget _buildSettingsScaffold(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final logger = sp.debugLogger;
    final storage = sp.storageService;
    final themeService = sp.themeService;
    final tpAuth = sp.thirdPartyAuthService;
    final campusCard = sp.campusCardService;
    final updateSourceLabel = sp.updateService.source.label;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(
      context,
      extra: TpTokens.space3,
    );

    return AdaptiveNavigationScaffold(
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      clipBodyBelowAppBar: true,
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
            if (sp.telemetry != null) sp.telemetry!,
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

            final deviceEntries = <Widget Function(bool showDivider)>[
              if (WearablesPage.isSupported)
                (showDivider) => TpListRow(
                      icon: TpIcons.watch,
                      iconColor: colors.textSecondary,
                      title: '穿戴设备',
                      subtitle: '小米手环、华为手表与 Apple Watch',
                      showChevron: true,
                      showDivider: showDivider,
                      onTap: () => unawaited(
                        pushAdaptivePage<void>(
                          context,
                          builder: (_) => const WearablesPage(),
                        ),
                      ),
                    ),
              if (_showsHuaweiWatch)
                (showDivider) => TpListRow(
                      icon: TpIcons.watch,
                      iconColor: colors.textSecondary,
                      title: 'Huawei Watch',
                      showChevron: true,
                      showDivider: showDivider,
                      onTap: () => unawaited(
                        pushAdaptivePage<void>(
                          context,
                          builder: (_) => const HuaweiWatchPage(),
                        ),
                      ),
                    ),
              if (supportsAppleWatch())
                (showDivider) => TpListRow(
                      icon: TpIcons.watch,
                      iconColor: colors.textSecondary,
                      title: 'Apple Watch',
                      showChevron: true,
                      showDivider: showDivider,
                      onTap: () => unawaited(
                        pushAdaptivePage<void>(
                          context,
                          builder: (_) => const WatchSettingsPage(),
                        ),
                      ),
                    ),
              if (hasDeadlineWidgets)
                (showDivider) => TpListRow(
                      key: const ValueKey('settings.deadline-widgets'),
                      icon: TpIcons.activities,
                      iconColor: colors.textSecondary,
                      title: '桌面小组件',
                      subtitle: '与桌面共享截止日期标题与时间；TechPie 关闭时展示本地缓存',
                      showDivider: showDivider,
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
                (showDivider) => TpListRow(
                      key: const ValueKey('settings.island'),
                      icon: TpIcons.bellRing,
                      iconColor: colors.textSecondary,
                      title: '课程与截止日期通知',
                      subtitle: _islandSubtitle,
                      showDivider: showDivider,
                      trailing: AdaptiveSwitch(
                        value: storage.islandEnabled,
                        onChanged: (value) =>
                            unawaited(_setIslandEnabled(island, value)),
                      ),
                      onTap: () => unawaited(
                        _setIslandEnabled(island, !storage.islandEnabled),
                      ),
                    ),
              if (hasSpending)
                (showDivider) => TpListRow(
                      key: const ValueKey('settings.spending-alerts'),
                      icon: TpIcons.bell,
                      iconColor: colors.textSecondary,
                      title: '校园卡消费提醒',
                      subtitle: '刷新发现新消费时通知；后台检查受系统调度限制',
                      showDivider: showDivider,
                      trailing: AdaptiveSwitch(
                        value: spending.enabled,
                        onChanged: (value) =>
                            unawaited(spending.setEnabled(value)),
                      ),
                      onTap: () =>
                          unawaited(spending.setEnabled(!spending.enabled)),
                    ),
            ];

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

                      // 1. 账号与绑定
                      _buildAccountSection(
                        context: context,
                        colors: colors,
                        auth: auth,
                        session: session,
                        displayName: resolveUserDisplayName(
                          session: session,
                          idsRealName: tpAuth.idsAccount?.name,
                          campusCardOwnerName: campusCard.cachedOwnerName,
                        ),
                        syncService: sp.syncService,
                        boundCount: boundCount,
                      ),
                      const SizedBox(height: TpTokens.sectionGap),

                      // 2. 外观
                      TpSectionCard(
                        title: '外观',
                        children: [
                          _buildThemeModeRow(colors, themeService),
                          if (themeService.supportsColorSchemeSelection)
                            _buildThemeColorRow(context, colors, themeService),
                        ],
                      ),

                      // 3. 设备与提醒
                      if (deviceEntries.isNotEmpty) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        TpSectionCard(
                          title: '设备与提醒',
                          children: [
                            for (var i = 0; i < deviceEntries.length; i++)
                              deviceEntries[i](i < deviceEntries.length - 1),
                          ],
                        ),
                      ],

                      // 4. 网络（仅桌面端）
                      if (supportsInAppProxy()) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        TpSectionCard(
                          title: '网络',
                          children: [
                            TpListRow(
                              key: const ValueKey('settings.app-proxy-address'),
                              icon: TpIcons.globe,
                              iconColor: colors.textSecondary,
                              title: '应用代理',
                              subtitle: '通过 HTTP 代理转发应用与登录请求',
                              value: _proxyValueLabel(storage),
                              showChevron: true,
                              onTap: () => unawaited(
                                _showProxySettings(storage, sp.uniAuthService),
                              ),
                            ),
                          ],
                        ),
                      ],

                      const SizedBox(height: TpTokens.sectionGap),

                      // 5. 支持与关于
                      TpSectionCard(
                        title: '支持与关于',
                        children: [
                          TpListRow(
                            icon: TpIcons.feedback,
                            iconColor: colors.textSecondary,
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
                                  telemetry: sp.telemetry,
                                  service: FeedbackService(
                                    auth,
                                    apiBaseUrl(sp.storageService),
                                  ),
                                ),
                              );
                            }()),
                          ),
                          if (sp.telemetry case final metrics?)
                            TpListRow(
                              key: const ValueKey('settings.usage-statistics'),
                              icon: TpIcons.privacy,
                              iconColor: colors.textSecondary,
                              title: '发送匿名使用统计',
                              subtitle: '统计活跃安装、登录、功能使用、反馈送达和录播加载耗时。仅使用随机安装标识，不含账号及校园内容。',
                              showDivider: true,
                              trailing: AdaptiveSwitch(
                                value: metrics.enabled,
                                onChanged: (value) => unawaited(metrics.setEnabled(value)),
                              ),
                              onTap: () => unawaited(metrics.setEnabled(!metrics.enabled)),
                            ),
                          TpListRow(
                            icon: TpIcons.privacy,
                            iconColor: colors.textSecondary,
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
                            key: const ValueKey('settings.check-update'),
                            icon: TpIcons.refresh,
                            iconColor: colors.textSecondary,
                            title: '检查更新',
                            subtitle: _checkingUpdate
                                ? '正在检查最新版本…'
                                : (_appVersion.isEmpty
                                    ? '当前版本未知'
                                    : '点击检查 $updateSourceLabel 最新版本'),
                            value: _appVersion.isEmpty ? null : 'v$_appVersion',
                            trailing: _checkingUpdate
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            showChevron: !_checkingUpdate,
                            onTap: _appVersion.isEmpty || _checkingUpdate
                                ? null
                                : () => unawaited(_checkForUpdate()),
                          ),
                        ],
                      ),

                      // 6. 账号操作（退出登录在前，注销账号在后）
                      if (auth.isLoggedIn) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        TpSectionCard(
                          title: '账号操作',
                          children: [
                            TpListRow(
                              key: const ValueKey('settings.logout'),
                              icon: TpIcons.logout,
                              iconColor: colors.textSecondary,
                              title: '退出登录',
                              showDivider: true,
                              onTap: () => unawaited(_confirmLogout(auth)),
                            ),
                            TpListRow(
                              key: const ValueKey('settings.delete-account'),
                              icon: TpIcons.delete,
                              title: '注销账号',
                              destructive: true,
                              showChevron: true,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) =>
                                      AccountDeletionPage(auth: auth),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],

                      // 7. 开发者选项（非 Release 折叠为单行入口）
                      if (!kReleaseMode) ...[
                        const SizedBox(height: TpTokens.sectionGap),
                        TpSectionCard(
                          title: '开发者',
                          children: [
                            TpListRow(
                              key: const ValueKey('settings.developer-options'),
                              icon: TpIcons.code,
                              iconColor: colors.textSecondary,
                              title: '开发者选项',
                              subtitle: logger.enabled
                                  ? '调试日志已开启 · ${logger.entries.length} 条记录'
                                  : '调试开关、本地服务与诊断工具',
                              showChevron: true,
                              onTap: () => unawaited(
                                pushAdaptivePage<void>(
                                  context,
                                  builder: (_) => const DeveloperOptionsPage(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: TpTokens.space6),
                      const _SettingsBrandFooter(),
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
    required String displayName,
    required SyncService syncService,
    required int boundCount,
  }) {
    return TpCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (session != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                TpTokens.cardPaddingHorizontal,
                TpTokens.space4,
                TpTokens.cardPaddingHorizontal,
                TpTokens.space3,
              ),
              child: Row(
                children: [
                  TpAvatarBadge(
                    text: userAvatarLabel(displayName),
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
                              child: Text(
                                displayName.isNotEmpty
                                    ? displayName
                                    : session.userId,
                                style: TpTypography.cardTitle(colors)
                                    .copyWith(fontSize: 17),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
                        Text(
                          'GeekPie Uni-Auth',
                          style: TpTypography.itemMeta(colors),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
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
            iconColor: colors.textSecondary,
            title: '第三方账号',
            subtitle: '已绑定 $boundCount / 4 项 · IDS / eCard / Gradescope / Hydro',
            showChevron: true,
            showDivider: auth.isLoggedIn,
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
              iconColor: colors.textSecondary,
              title: '云同步',
              subtitle: _cloudSyncSubtitle(syncService),
              showChevron: true,
              onTap: () => unawaited(
                pushAdaptivePage<void>(
                  context,
                  builder: (_) => const SyncSettingsPage(),
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool get _showsHuaweiWatch => isAndroid();

  Widget _buildThemeModeRow(
    TpColors colors,
    ThemeService themeService,
  ) {
    final hasNext = themeService.supportsColorSchemeSelection;
    return AdaptiveNavigationScaffold.adaptiveChrome(
      ios: () => TpListRow(
        icon: _themeModeIcon(themeService.mode),
        iconColor: colors.textSecondary,
        title: '主题模式',
        showDivider: hasNext,
        trailing: AdaptiveSelect(
          value: themeService.mode.name,
          placeholder: '选择主题',
          accessibilityLabel: '主题模式',
          shrinkWrap: true,
          iosButtonStyle: CNButtonStyle.plain,
          iosTint: colors.brandInk,
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
          iconColor: colors.textSecondary,
          title: '主题模式',
          value: themeService.mode.label,
          showChevron: true,
          showDivider: hasNext,
          onTap: () => _showThemePicker(tileContext, themeService),
        ),
      ),
    );
  }

  Widget _buildThemeColorRow(
    BuildContext context,
    TpColors colors,
    ThemeService themeService,
  ) {
    final brightness = Theme.of(context).brightness;
    return AdaptiveNavigationScaffold.adaptiveChrome(
      ios: () => TpListRow(
        icon: TpIcons.sparkles,
        iconColor: colors.textSecondary,
        title: '主题色',
        trailing: AdaptiveSelect(
          value: themeService.colorScheme.name,
          placeholder: '选择主题色',
          accessibilityLabel: '主题色',
          shrinkWrap: true,
          iosButtonStyle: CNButtonStyle.plain,
          iosTint: colors.brandInk,
          options: [
            for (final scheme in AppColorScheme.values)
              AdaptiveSelectOption(
                value: scheme.name,
                label: themeService.colorSchemeLabel(scheme),
                sfSymbol: 'circle.fill',
                sfSymbolColor:
                    themeService.previewColorForScheme(scheme, brightness),
              ),
          ],
          onChanged: (value) => unawaited(
            themeService.setColorScheme(AppColorScheme.values.byName(value)),
          ),
        ),
      ),
      material: () => Builder(
        builder: (tileContext) => TpListRow(
          icon: TpIcons.sparkles,
          iconColor: colors.textSecondary,
          title: '主题色',
          value: _colorSubtitle(themeService),
          showChevron: true,
          onTap: () => _showColorPicker(tileContext, themeService),
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

  String _proxyValueLabel(StorageService storage) {
    if (storage.appProxyEnabled && storage.appProxyUrl.isNotEmpty) {
      return storage.appProxyUrl;
    }
    if (storage.appProxyUrl.isNotEmpty) {
      return '已停用';
    }
    return '跟随系统';
  }

  Future<void> _showProxySettings(
    StorageService storage,
    UniAuthService uniAuth,
  ) async {
    final result = await showDialog<({bool enabled, String url})>(
      context: context,
      builder: (_) => _ProxySettingsDialog(
        initialEnabled: storage.appProxyEnabled,
        initialUrl: storage.appProxyUrl,
      ),
    );
    if (result == null || !mounted) return;
    final proxy = normalizeAppProxy(result.url);
    if (result.enabled && !isValidAppProxy(proxy)) {
      await showAdaptiveAlertDialog<void>(
        context: context,
        title: '代理地址无效',
        message: '请使用 host:port 格式，例如 127.0.0.1:7890。',
        actions: const [AdaptiveAlertAction<void>(label: '好')],
      );
      return;
    }
    if (proxy.isEmpty || isValidAppProxy(proxy)) {
      await storage.setAppProxyUrl(proxy);
    }
    final active = result.enabled && isValidAppProxy(proxy);
    await storage.setAppProxyEnabled(active);
    final applied = active ? proxy : '';
    configureAppProxy(applied);
    uniAuth.setProxyUrl(applied);
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
    final label = themeService.colorSchemeLabel(themeService.colorScheme);
    if (themeService.colorScheme == AppColorScheme.system &&
        !themeService.systemDynamicColorAvailable) {
      return '$label（不可用，已回退科技红）';
    }
    return label;
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
                    selected: themeService.colorScheme == scheme,
                    leading: _ColorSwatchDot(
                      color: themeService.previewColorForScheme(
                        scheme,
                        theme.brightness,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            themeService.colorSchemeLabel(scheme),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: themeService.colorScheme == scheme
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                        if (themeService.colorScheme == scheme)
                          Icon(
                            TpIcons.check,
                            size: TpTokens.iconS,
                            color: colors.brandInk,
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
          final brightness = Theme.of(context).brightness;
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
                    leading: _ColorSwatchDot(
                      color: themeService.previewColorForScheme(
                        scheme,
                        brightness,
                      ),
                    ),
                    title: themeService.colorSchemeLabel(scheme),
                    trailing: themeService.colorScheme == scheme
                        ? Icon(
                            TpIcons.check,
                            size: TpTokens.iconS,
                            color: colors.brandInk,
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

class _ColorSwatchDot extends StatelessWidget {
  const _ColorSwatchDot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: colors.divider),
      ),
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

  static IconData _iconForMode(AppThemeMode mode) => switch (mode) {
        AppThemeMode.system => TpIcons.smartphone,
        AppThemeMode.light => TpIcons.sun,
        AppThemeMode.dark => TpIcons.moon,
        AppThemeMode.amoled => TpIcons.amoled,
      };

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
              selected: themeService.mode == mode,
              leading: Icon(_iconForMode(mode), size: 18),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      mode.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: themeService.mode == mode
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (themeService.mode == mode)
                    Icon(
                      TpIcons.check,
                      size: TpTokens.iconS,
                      color: colors.brandInk,
                    ),
                ],
              ),
              onTap: () => onSelected(mode),
            )
          else
            TpListRow(
              icon: _iconForMode(mode),
              iconColor: themeService.mode == mode
                  ? colors.brandInk
                  : colors.textMuted,
              title: mode.label,
              trailing: themeService.mode == mode
                  ? Icon(
                      TpIcons.check,
                      size: TpTokens.iconS,
                      color: colors.brandInk,
                    )
                  : null,
              onTap: () => onSelected(mode),
            ),
      ],
    );
  }
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog({
    required this.initialEnabled,
    required this.initialUrl,
  });

  final bool initialEnabled;
  final String initialUrl;

  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late final TextEditingController _controller;
  late bool _enabled;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
    _enabled = widget.initialEnabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      (enabled: _enabled, url: _controller.text.trim()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return AlertDialog(
      title: const Text('应用代理'),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('启用应用代理', style: TpTypography.itemTitle(colors)),
                      const SizedBox(height: 2),
                      Text(
                        '使用自定义 HTTP 代理转发请求',
                        style: TpTypography.itemMeta(colors),
                      ),
                    ],
                  ),
                ),
                AdaptiveSwitch(
                  key: const ValueKey('settings.app-proxy-enabled'),
                  value: _enabled,
                  onChanged: (value) => setState(() => _enabled = value),
                ),
              ],
            ),
            const SizedBox(height: TpTokens.space3),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '代理地址 (host:port)',
                hintText: '127.0.0.1:7890',
              ),
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('保存'),
        ),
      ],
    );
  }
}

class _SettingsBrandFooter extends StatelessWidget {
  const _SettingsBrandFooter();

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Padding(
      key: const ValueKey('settings.brand-footer'),
      padding: const EdgeInsets.only(bottom: TpTokens.space4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const TpBrandMark(size: 20),
          const SizedBox(height: TpTokens.space2),
          Text(
            'TechPie · Built with Flutter by GeekPie_',
            style: TpTypography.cardMeta(colors).copyWith(
              color: colors.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
