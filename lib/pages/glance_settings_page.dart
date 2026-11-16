import 'dart:async';

import 'package:flutter/material.dart';

import '../models/screen_form_factor.dart';
import '../services/glance_settings_service.dart';
import '../services/screen_form_factor_service.dart';
import '../services/service_provider.dart';
import '../widgets/adaptive_page_navigation.dart';
import '../widgets/blurred_app_bar.dart';
import 'glance_preview_page.dart';

/// Controls the rear-screen / cover-screen glance and shows what the native
/// probe currently reports, which is the only way to verify the thresholds on
/// a device without one attached to the build machine.
class GlanceSettingsPage extends StatelessWidget {
  const GlanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final services = ServiceProvider.of(context);
    final settings = services.glanceSettings;
    final formFactor = services.screenFormFactorService;
    if (settings == null || formFactor == null) {
      return const Scaffold(
        appBar: BlurredAppBar(title: Text('背屏与小屏')),
        body: Center(child: Text('当前版本未启用副屏适配')),
      );
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: const BlurredAppBar(title: Text('背屏与小屏')),
      body: ListenableBuilder(
        listenable: Listenable.merge([settings, formFactor]),
        builder: (context, _) {
          final info = formFactor.info;
          final surface = classifyGlanceSurface(
            logicalSize: MediaQuery.sizeOf(context),
            info: info,
            enabled: true,
          );
          return ListView(
            padding: EdgeInsets.fromLTRB(
              0,
              kToolbarHeight + MediaQuery.viewPaddingOf(context).top + 12,
              0,
              32,
            ),
            children: [
              _StatusCard(
                surface: surface,
                info: info,
                onRefresh: () => unawaited(formFactor.refresh()),
              ),
              const SizedBox(height: 4),
              SwitchListTile(
                secondary: const Icon(Icons.auto_awesome_outlined),
                title: const Text('自动切换到小屏界面'),
                subtitle: const Text('在小米背屏或折叠屏外屏上显示精简界面'),
                value: settings.enabled,
                onChanged: (value) => unawaited(settings.setEnabled(value)),
              ),
              const Divider(),
              _sectionLabel(context, '显示内容'),
              for (final section in GlanceSection.values)
                SwitchListTile(
                  secondary: Icon(_sectionIcon(section)),
                  title: Text(_sectionTitle(section)),
                  subtitle: Text(_sectionSubtitle(section)),
                  value: settings.isEnabled(section),
                  onChanged: settings.isEnabled(section) &&
                          !settings.canDisable(section)
                      ? null
                      : (value) =>
                          unawaited(settings.setSection(section, value)),
                ),
              const Divider(),
              _sectionLabel(context, '预览'),
              if (info?.isFlipDevice == true)
                ListTile(
                  leading: const Icon(Icons.stay_current_portrait),
                  title: const Text('外屏预览'),
                  subtitle: const Text('MIX Flip · 1392 × 1208 px（约 506 × 439 dp）'),
                trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(
                    pushAdaptivePage<void>(
                      context,
                      builder: (_) => const GlancePreviewPage(
                        surface: GlanceSurface.cover,
                      ),
                    ),
                  ),
                ),
              if (info?.isRearDevice == true)
                ListTile(
                  leading: const Icon(Icons.stay_current_landscape),
                  title: const Text('背屏预览'),
                  subtitle: const Text('小米 17 Pro 系列 · 340 × 210 dp'),
                trailing: const Icon(Icons.chevron_right),
                  onTap: () => unawaited(
                    pushAdaptivePage<void>(
                      context,
                      builder: (_) => const GlancePreviewPage(
                        surface: GlanceSurface.rear,
                      ),
                    ),
                  ),
                ),
              const Divider(),
              _sectionLabel(context, '说明'),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Text(
                  'MIX Flip：需在系统「设置 → 外屏 → 应用管理」中添加 TechPie；'
                  '折叠与展开会保留当前页面。',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Text(
                  '小米背屏：TechPie 是否出现在背屏应用列表由系统控制；'
                  '本页的预览可在任何设备上检查布局。',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  static IconData _sectionIcon(GlanceSection section) => switch (section) {
        GlanceSection.courses => Icons.calendar_month_outlined,
        GlanceSection.assignments => Icons.assignment_outlined,
        GlanceSection.payment => Icons.qr_code_2_outlined,
      };

  static String _sectionTitle(GlanceSection section) => switch (section) {
        GlanceSection.courses => '今日课程',
        GlanceSection.assignments => '待办作业',
        GlanceSection.payment => '消费码',
      };

  static String _sectionSubtitle(GlanceSection section) => switch (section) {
        GlanceSection.courses => '显示下一节课与今日剩余课程',
        GlanceSection.assignments => '显示最近的待办截止时间',
        GlanceSection.payment => '显示在线付款码（不生成离线码）',
      };

  static Widget _sectionLabel(BuildContext context, String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.surface,
    required this.info,
    required this.onRefresh,
  });

  final GlanceSurface surface;
  final ScreenFormFactorInfo? info;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon) = switch (surface) {
      GlanceSurface.cover => ('当前：折叠外屏', Icons.stay_current_portrait),
      GlanceSurface.rear => ('当前：背屏', Icons.stay_current_landscape),
      GlanceSurface.none => ('当前：普通屏幕', Icons.smartphone),
    };
    final details = info == null
        ? '未读取到屏幕信息'
        : '${info!.manufacturer} ${info!.model} · display ${info!.displayId}'
            ' · ${info!.windowWidthPx}×${info!.windowHeightPx}px'
            ' · ${info!.windowWidthDp.toStringAsFixed(0)}×'
            '${info!.windowHeightDp.toStringAsFixed(0)}dp'
            ' · ${info!.densityDpi}dpi';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details,
                    style: TextStyle(
                      fontSize: 11,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  if (surface == GlanceSurface.none && info != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      '当前设备没有检测到背屏/外屏；可在下方预览。',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 18),
              tooltip: '重新检测',
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }
}
