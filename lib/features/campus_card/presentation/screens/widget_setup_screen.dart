import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:techpie/widgets/adaptive_button.dart';

import '../../app/app_providers.dart';
import '../../domain/ports/platform_ports.dart';
import '../app/navigation.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../widgets/apple_wallet_components.dart';

/// Manual home-screen-widget steps, per platform. The launcher's picker cannot
/// be driven from the app, so the fallback path has to spell them out.
const _iosWidgetSteps = <String>[
  '回到主屏幕，长按空白处，轻点“编辑”或左上角的“+”。',
  '选择“添加小组件”，搜索 TechPie，再选择“消费码”。',
  '轻点“添加小组件”，放到合适的位置后点“完成”。',
];

const _androidWidgetSteps = <String>[
  '回到主屏幕，长按空白处，打开“小组件”。',
  '找到 TechPie，长按“消费码”小组件并拖到主屏幕。',
  '放到合适的位置；以后轻触小组件即可打开消费码。',
];

final class WidgetSetupScreen extends ConsumerStatefulWidget {
  const WidgetSetupScreen({super.key});

  @override
  ConsumerState<WidgetSetupScreen> createState() => _WidgetSetupScreenState();
}

class _WidgetSetupScreenState extends ConsumerState<WidgetSetupScreen> {
  late Future<HomeWidgetAvailability> _availability;
  bool _pinning = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _availability = Future.sync(
      () async =>
          await ref.read(homeWidgetPortProvider)?.availability() ??
          HomeWidgetAvailability.manual,
    );
  }

  Future<void> _requestPin() async {
    if (_pinning) return;
    setState(() => _pinning = true);
    var requested = false;
    try {
      requested = await ref.read(homeWidgetPortProvider)?.requestPin() ?? false;
    } catch (_) {
      // The manual guide remains usable if the launcher rejects the request.
    }
    if (!mounted) return;
    setState(() {
      _pinning = false;
      _message = requested ? '请在系统弹窗中确认添加。' : '当前桌面未接受添加请求，请按下方步骤手动添加。';
      if (!requested) {
        _availability = Future.value(HomeWidgetAvailability.manual);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final apple = Theme.of(context).platform == TargetPlatform.iOS;
    return Scaffold(
      body: AppleWalletPage(
        child: ApplePinnedHeaderLayout(
          title: '添加消费码小组件',
          leading: CampusCardHeaderAction(
            id: 'back',
            sfSymbol: 'chevron.left',
            icon: GpPlatformIcons.back(context),
            label: '返回',
            onPressed: () => popCampusCard(context),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              20,
              ApplePinnedHeaderLayout.contentTop + 20,
              20,
              40,
            ),
            children: [
              const Center(child: PayWidgetPreview()),
              const SizedBox(height: 24),
              const Text('将消费码放到主屏幕，轻触小组件即可打开。', textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FutureBuilder<HomeWidgetAvailability>(
                future: _availability,
                builder: (context, snapshot) {
                  final availability =
                      snapshot.data ?? HomeWidgetAvailability.manual;
                  if (availability == HomeWidgetAvailability.unsupported) {
                    return const AppleSection(
                      children: [
                        Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('此系统暂不支持主屏幕小组件。iPhone 需要 iOS 14 或更新版本。'),
                        ),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (availability == HomeWidgetAvailability.nativePin) ...[
                        AdaptiveButton(
                          key: const Key('request-pin-widget'),
                          onPressed: _pinning ? null : _requestPin,
                          icon: GpPlatformIcons.homeWidget(context),
                          sfSymbol: 'square.grid.2x2',
                          label: '添加到主屏幕',
                          role: AdaptiveButtonRole.prominent,
                          loading: _pinning,
                          width: double.infinity,
                        ),
                        const SizedBox(height: 18),
                      ],
                      if (_message != null) ...[
                        Text(_message!, textAlign: TextAlign.center),
                        const SizedBox(height: 18),
                      ],
                      AppleSection(
                        header: '手动添加步骤',
                        children: [
                          for (var step = 1; step <= 3; step++)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 16,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    radius: 13,
                                    backgroundColor:
                                        context.gpColors.surfaceRaised,
                                    foregroundColor: context.gpColors.action,
                                    child: Text(
                                      '$step',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      (apple
                                          ? _iosWidgetSteps
                                          : _androidWidgetSteps)[step - 1],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

final class PayWidgetPreview extends StatelessWidget {
  const PayWidgetPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '消费码',
      image: true,
      child: ExcludeSemantics(
        child: Container(
          width: 176,
          height: 176,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: const DecorationImage(
              image: AssetImage(GeekPayAssets.widgetBackground),
              fit: BoxFit.cover,
            ),
            boxShadow: const [
              BoxShadow(
                color: Color(0x18000000),
                blurRadius: 16,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                GpPlatformIcons.qrCode(context),
                size: 36,
                color: GpTokens.campusRed,
              ),
              const Spacer(),
              const Text(
                '消费码',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF242428),
                ),
              ),
              const SizedBox(height: 3),
              const Text(
                '支付一触即达',
                style: TextStyle(fontSize: 12, color: Color(0xFF76656A)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
