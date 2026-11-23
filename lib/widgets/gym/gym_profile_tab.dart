import 'package:flutter/material.dart';

import '../../models/oa_gym.dart';
import '../../services/oa_gym_service.dart';
import '../../services/service_provider.dart';
import '../../theme/theme.dart';
import '../adaptive_button.dart';
import '../adaptive_feedback.dart';
import '../app_shell/app_shell_metrics.dart';
import '../design_system/design_system.dart';

class GymProfileTab extends StatefulWidget {
  const GymProfileTab({super.key});

  @override
  State<GymProfileTab> createState() => _GymProfileTabState();
}

class _GymProfileTabState extends State<GymProfileTab> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  OaGymService? _service;
  String _owner = '';
  OaBookingProfile _lastProfile =
      const OaBookingProfile(name: '', phone: '', email: '');

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final service = ServiceProvider.of(context).oaGymService;
    if (identical(service, _service)) return;
    _service?.removeListener(_onProfileChanged);
    _service = service;
    service.addListener(_onProfileChanged);
    _applyProfile();
  }

  void _applyProfile({bool replaceEdits = false}) {
    final service = _service!;
    final profile = service.bookingProfile();
    final replace = replaceEdits || _owner != service.profileOwner;
    if (replace || _name.text == _lastProfile.name) _name.text = profile.name;
    if (replace || _phone.text == _lastProfile.phone) {
      _phone.text = profile.phone;
    }
    if (replace || _email.text == _lastProfile.email) {
      _email.text = profile.email;
    }
    _owner = service.profileOwner;
    _lastProfile = profile;
  }

  void _onProfileChanged() {
    if (!mounted) return;
    setState(_applyProfile);
  }

  @override
  void dispose() {
    _service?.removeListener(_onProfileChanged);
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await ServiceProvider.of(context).oaGymService.saveBookingProfile(
          OaBookingProfile(
            name: _name.text.trim(),
            phone: _phone.text.trim(),
            email: _email.text.trim(),
          ),
        );
    if (!mounted) return;
    showAdaptiveFeedback(
      context: context,
      message: '预约信息已保存',
      style: AdaptiveFeedbackStyle.success,
    );
  }

  Future<void> _sync() async {
    final service = _service!;
    final owner = service.profileOwner;
    await service.syncBookingProfile(overwrite: true);
    if (!mounted || owner != service.profileOwner) return;
    final error = service.profileSyncError;
    if (error == null) setState(() => _applyProfile(replaceEdits: true));
    showAdaptiveFeedback(
      context: context,
      message: error ?? '个人信息已更新',
      style: error == null
          ? AdaptiveFeedbackStyle.success
          : AdaptiveFeedbackStyle.error,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final sp = ServiceProvider.of(context);
    final tpAuth = sp.thirdPartyAuthService;
    final service = sp.oaGymService;
    final ids = tpAuth.idsAccount;

    final displayName = service.bookingProfile().name.isNotEmpty
        ? service.bookingProfile().name
        : ids?.name?.isNotEmpty == true
            ? ids!.name!
            : (ids?.account.isNotEmpty == true ? ids!.account : 'TechPie 用户');
    final studentId = service.bookingStudentId;
    final avatarText = displayName.characters.firstOrNull ?? 'U';

    return ListView(
      padding: EdgeInsets.fromLTRB(
        TpTokens.pageHorizontalPadding,
        TpTokens.space3,
        TpTokens.pageHorizontalPadding,
        AppShellMetrics.bottomContentPaddingOf(context),
      ),
      children: [
        TpPageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TpCard(
                padding: const EdgeInsets.all(TpTokens.space4),
                child: Row(
                  children: [
                    TpAvatarBadge(text: avatarText, size: 46),
                    const SizedBox(width: TpTokens.space3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style: TpTypography.cardTitle(colors)
                                .copyWith(fontSize: 17),
                          ),
                          if (studentId.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              studentId,
                              style: TpTypography.itemMeta(colors),
                            ),
                          ],
                        ],
                      ),
                    ),
                    TpBadge(
                      label: service.profileSynced ? '已同步 OA' : '本地信息',
                      tone: service.profileSynced
                          ? TpBadgeTone.success
                          : TpBadgeTone.muted,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TpTokens.sectionGap),
              TpCard(
                leadingIcon: TpIcons.profile,
                title: '预约提交信息',
                padding: const EdgeInsets.fromLTRB(
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space1,
                  TpTokens.cardPaddingHorizontal,
                  TpTokens.space4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '绑定 IDS 后自动从 OA 同步，用于场馆预约。姓名和手机号必填，邮箱可选，也可手动修改。',
                      style:
                          TpTypography.itemMeta(colors).copyWith(height: 1.45),
                    ),
                    const SizedBox(height: TpTokens.space3),
                    if (service.profileSyncing) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: TpTokens.space2),
                      Text(
                        '正在从 OA 同步个人信息…',
                        style: TpTypography.itemMeta(colors),
                      ),
                    ] else if (service.profileSyncError != null)
                      Text(
                        service.profileSyncError!,
                        style: TpTypography.itemMeta(colors).copyWith(
                          color: colors.dangerRed,
                        ),
                      )
                    else if (service.profileSynced)
                      Text(
                        '已同步 OA 提供的信息，空缺项可手动补充。',
                        style: TpTypography.itemMeta(colors).copyWith(
                          color: colors.successGreen,
                        ),
                      ),
                    const SizedBox(height: TpTokens.space2),
                    AdaptiveButton(
                      onPressed: service.profileSyncing ? null : _sync,
                      icon: TpIcons.refresh,
                      sfSymbol: 'arrow.triangle.2.circlepath',
                      label: '从 OA 同步',
                      loading: service.profileSyncing,
                      height: 44,
                      accessibilityLabel: '从 OA 同步个人信息',
                    ),
                    const SizedBox(height: TpTokens.space4),
                    TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: '姓名',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: TpTokens.space3),
                    TextField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: '手机号',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: TpTokens.space3),
                    TextField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: '邮箱',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: TpTokens.space4),
                    AdaptiveButton(
                      onPressed: _save,
                      icon: TpIcons.check,
                      sfSymbol: 'square.and.arrow.down',
                      label: '保存',
                      role: AdaptiveButtonRole.prominent,
                      height: 46,
                      accessibilityLabel: '保存预约信息',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
