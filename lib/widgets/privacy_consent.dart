import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/service_provider.dart';
import 'adaptive_button.dart';

const privacyPolicyUrl = 'https://techpie.geekpie.club/privacy';

/// Opens the published policy in the system browser: it must be readable before
/// any account exists, so it cannot depend on the in-app session.
Future<void> openPrivacyPolicy() => launchUrl(
  Uri.parse(privacyPolicyUrl),
  mode: LaunchMode.externalApplication,
);

/// Blocks the app until this device has been shown the policy and agreed to it.
///
/// A store review asks for this on first launch *and* at the sign-in entry; this
/// is the first half. It is deliberately a page rather than a dialog: nothing
/// behind it may run before the answer, and «not now» has to leave the user with
/// something readable instead of a dead screen.
class PrivacyGate extends StatefulWidget {
  const PrivacyGate({super.key, required this.child});

  final Widget child;

  @override
  State<PrivacyGate> createState() => _PrivacyGateState();
}

class _PrivacyGateState extends State<PrivacyGate> {
  Future<void> _accept() async {
    await ServiceProvider.of(context).storageService.setPrivacyAccepted(true);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final storage = ServiceProvider.of(context).storageService;
    if (storage.privacyAccepted) return widget.child;
    return PrivacyConsentPage(onAccept: _accept);
  }
}

/// The consent itself, shared by the first-launch gate and the sign-in dialog.
class PrivacyConsentPage extends StatelessWidget {
  const PrivacyConsentPage({
    super.key,
    required this.onAccept,
    this.onDecline,
    this.compact = false,
  });

  final Future<void> Function() onAccept;
  final VoidCallback? onDecline;

  /// Dialog-sized instead of full-screen.
  final bool compact;

  /// Leaving the user on a dead screen is not an answer: say why the app cannot
  /// go on, and let them change their mind.
  void _explainDecline(BuildContext context) {
    unawaited(
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('需要你的同意'),
          content: const Text(
            '不同意隐私政策时，TechPie 无法连接校园服务，也就无法提供课表、作业和校园卡功能。'
            '你仍然可以随时重新打开应用并选择同意。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('隐私政策', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        Text(
          'TechPie 是第三方校园工具，需要连接校园服务才能显示课表、作业与校园卡信息。'
          '在你使用之前，请阅读并同意《隐私政策》。我们会说明收集哪些信息、'
          '用于什么目的，以及你如何查询、更正或删除它们。',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => openPrivacyPolicy(),
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('查看《隐私政策》'),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: AdaptiveButton(
                label: '不同意',
                icon: Icons.close,
                sfSymbol: 'xmark',
                role: AdaptiveButtonRole.plain,
                onPressed: () {
                  if (onDecline != null) {
                    onDecline!();
                    return;
                  }
                  _explainDecline(context);
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdaptiveButton(
                label: '同意并继续',
                icon: Icons.check,
                sfSymbol: 'checkmark',
                role: AdaptiveButtonRole.prominent,
                onPressed: () => unawaited(onAccept()),
              ),
            ),
          ],
        ),
      ],
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
        child: SafeArea(top: false, child: body),
      );
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: body,
            ),
          ),
        ),
      ),
    );
  }
}

/// Asks for the same consent at a sign-in entry, so a user that somehow reached
/// the login without the first-launch gate still answers before an account is
/// touched. Returns whether the app may proceed.
Future<bool> ensurePrivacyAccepted(BuildContext context) async {
  final storage = ServiceProvider.of(context).storageService;
  if (storage.privacyAccepted) return true;
  var accepted = false;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => PrivacyConsentPage(
      compact: true,
      onAccept: () async {
        await storage.setPrivacyAccepted(true);
        accepted = true;
        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
      },
      onDecline: () => Navigator.of(sheetContext).pop(),
    ),
  );
  return accepted;
}

/// The one-line notice a sign-in screen has to carry, with the policy one tap
/// away. The sign-in itself is the agreement, which is why this text says so
/// rather than asking for a second checkbox.
class PrivacyNotice extends StatelessWidget {
  const PrivacyNotice({super.key, this.alignment = TextAlign.center});

  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      alignment: alignment == TextAlign.center ? WrapAlignment.center : WrapAlignment.start,
      children: [
        Text(
          '登录即表示你已阅读并同意',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        InkWell(
          onTap: () => openPrivacyPolicy(),
          child: Text(
            '《隐私政策》',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: theme.colorScheme.primary,
            ),
          ),
        ),
      ],
    );
  }
}
