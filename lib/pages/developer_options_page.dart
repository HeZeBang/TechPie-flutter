import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../utils/platform.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_switch.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import 'debug_log_page.dart';
import 'debug_webview_page.dart';
import 'developer_lab_page.dart';

/// Non-release developer toggles, test endpoints, and diagnostic tools pushed
/// from Settings so debug controls never clutter the main settings screen.
class DeveloperOptionsPage extends StatefulWidget {
  const DeveloperOptionsPage({super.key});

  @override
  State<DeveloperOptionsPage> createState() => _DeveloperOptionsPageState();
}

class _DeveloperOptionsPageState extends State<DeveloperOptionsPage> {
  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final storage = sp.storageService;
    final logger = sp.debugLogger;
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
          title: '开发者选项',
          leadingItems: const [
            IosNativeNavigationBarItem(
              id: 'back',
              title: '我的',
              sfSymbol: 'chevron.left',
              accessibilityLabel: '返回我的',
              placementGroup: 'leading-main',
            ),
          ],
          onItemPressed: (id) {
            if (id == 'back') {
              unawaited(maybePopAdaptivePage<void>(context));
            }
          },
        ),
        material: () => const BlurredAppBar(title: Text('开发者选项')),
      ),
      body: ListenableBuilder(
        listenable: logger,
        builder: (context, _) {
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
                    TpSectionCard(
                      title: '调试与环境',
                      children: [
                        TpListRow(
                          key: const ValueKey('settings.ids-rebind-preview'),
                          icon: TpIcons.lock,
                          iconColor: colors.textSecondary,
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
                          iconColor: colors.textSecondary,
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
                          iconColor: colors.textSecondary,
                          title: '本地测试服务器',
                          subtitle: isAndroid()
                              ? '通过 10.0.2.2:3000 连接本地服务'
                              : '连接本地开发服务器',
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
                      ],
                    ),
                    const SizedBox(height: TpTokens.sectionGap),
                    TpSectionCard(
                      title: '诊断与工具',
                      children: [
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
                            iconColor: colors.textSecondary,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
