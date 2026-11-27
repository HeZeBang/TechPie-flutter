import 'dart:async';

import 'package:flutter/material.dart';

import '../services/service_provider.dart';
import '../theme/theme.dart';
import '../widgets/adaptive_button.dart';
import '../widgets/adaptive_navigation_scaffold.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/adaptive_segmented_control.dart';
import '../widgets/app_shell/app_shell_metrics.dart';
import '../widgets/blurred_app_bar.dart';
import '../widgets/design_system/design_system.dart';
import '../widgets/gym/gym_booking_tab.dart';
import '../widgets/gym/gym_profile_tab.dart';
import '../widgets/gym/gym_search_tab.dart';
import '../widgets/ios/ios_native_navigation_bar.dart';
import '../widgets/uni_auth_login.dart';
import 'third_party_accounts_page.dart';

class OaGymPage extends StatefulWidget {
  const OaGymPage({super.key});

  @override
  State<OaGymPage> createState() => _OaGymPageState();
}

class _OaGymPageState extends State<OaGymPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  int _selectedTab = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_selectedTab == _tabController.index || !mounted) return;
    setState(() => _selectedTab = _tabController.index);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final auth = sp.authService;
    final tpAuth = sp.thirdPartyAuthService;
    final topInset = AdaptiveNavigationScaffold.contentTopInsetOf(context);

    return Scaffold(
      backgroundColor: colors.canvas,
      extendBodyBehindAppBar:
          AdaptiveNavigationScaffold.extendsBodyBehindAppBar(),
      appBar: AdaptiveNavigationScaffold.adaptiveBar(
        ios: () => IosNativeNavigationBar(
          title: '场馆预约',
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
        material: () => const BlurredAppBar(title: Text('场馆预约')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([auth, tpAuth]),
        builder: (context, _) {
          final ready = auth.isLoggedIn && tpAuth.hasIdsBinding;
          if (!ready) {
            return ListView(
              padding: EdgeInsets.fromLTRB(
                TpTokens.pageHorizontalPadding,
                topInset + TpTokens.space4,
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
                            color: colors.brandSoft,
                            borderRadius:
                                BorderRadius.circular(TpTokens.radiusM),
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            TpIcons.gym,
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
                              ? '场馆预约复用 IDS 绑定的校园网登录态，请在「第三方账号」中绑定 IDS 后再使用。'
                              : '场馆预约复用 IDS 绑定的校园网登录态，不需要单独保存 OA 密码。',
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

          return Column(
            children: [
              SizedBox(height: topInset),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.pageHorizontalPadding,
                  TpTokens.space2,
                  TpTokens.pageHorizontalPadding,
                  0,
                ),
                child: TpPageBody(
                  child: AdaptiveSegmentedControl(
                    value: _selectedTab,
                    segments: const ['预约', '查询', '个人信息'],
                    onChanged: _tabController.animateTo,
                  ),
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: const [
                    GymBookingTab(),
                    GymSearchTab(),
                    GymProfileTab(),
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
