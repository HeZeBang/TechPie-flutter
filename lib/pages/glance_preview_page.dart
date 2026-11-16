import 'package:flutter/material.dart';

import '../features/glance/presentation/glance_payment_card.dart';
import '../features/glance/presentation/live_glance_shell.dart';
import '../models/screen_form_factor.dart';
import '../services/service_provider.dart';
import '../widgets/blurred_app_bar.dart';

/// Fixed-size preview so the layouts can be checked on a normal phone.
class GlancePreviewPage extends StatefulWidget {
  const GlancePreviewPage({super.key, required this.surface});

  final GlanceSurface surface;

  @override
  State<GlancePreviewPage> createState() => _GlancePreviewPageState();
}

class _GlancePreviewPageState extends State<GlancePreviewPage> {
  late GlanceSurface _surface = widget.surface == GlanceSurface.rear
      ? GlanceSurface.rear
      : GlanceSurface.cover;

  @override
  Widget build(BuildContext context) {
    final services = ServiceProvider.of(context);
    final settings = services.glanceSettings;
    final cover = _surface == GlanceSurface.cover;
    final width = cover ? 506.0 : 340.0;
    final height = cover ? 439.0 : 210.0;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const BlurredAppBar(title: Text('小屏预览')),
      body: settings == null
          ? const Center(child: Text('当前版本未启用副屏适配'))
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                16,
                kToolbarHeight + MediaQuery.viewPaddingOf(context).top + 12,
                16,
                32,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: SegmentedButton<GlanceSurface>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(
                          value: GlanceSurface.cover,
                          label: Text('外屏'),
                          icon: Icon(Icons.stay_current_portrait, size: 16),
                        ),
                        ButtonSegment(
                          value: GlanceSurface.rear,
                          label: Text('背屏'),
                          icon: Icon(Icons.stay_current_landscape, size: 16),
                        ),
                      ],
                      selected: {_surface},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        setState(() => _surface = selection.first);
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    cover
                        ? 'MIX Flip 外屏 · 1392 × 1208 px（约 506 × 439 dp）'
                        : '小米 17 Pro 系列背屏 · 340 × 210 dp（904 × 572 / 976 × 596 px）',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    // The cover preview is wider than a phone screen; scale the
                    // whole 506×439 surface down so the preview keeps the real
                    // aspect ratio instead of being clamped to the screen width.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topCenter,
                      child: Container(
                        width: width,
                        height: height,
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(cover ? 26 : 14),
                          border: Border.all(
                            color: Theme.of(
                              context,
                            ).colorScheme.outlineVariant,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.16),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            size: Size(width, height),
                            padding: EdgeInsets.zero,
                            viewPadding: EdgeInsets.zero,
                            viewInsets: EdgeInsets.zero,
                          ),
                          child: LiveGlanceShell(
                            surface: _surface,
                            settings: settings,
                            scheduleService: services.scheduleService,
                            assignmentService: services.assignmentService,
                            authService: services.authService,
                            consumeEntry: false,
                            paymentBuilder: (_) =>
                                const GlancePaymentPreviewCard(),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '预览使用真实课程/作业数据与示例付款码，不会生成真实消费码，'
                    '也不会消耗离线支付次数。',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
