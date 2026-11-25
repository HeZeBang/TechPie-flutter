import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_service.dart';
import 'adaptive_alert_dialog.dart';

/// The dialogs the update check can raise.
///
/// Shared, because the check runs twice — silently at launch and on resume, and
/// loudly when the version tile is tapped — and the two must not grow different
/// answers to the same question.

/// An update is available. Offered by both paths.
Future<void> showUpdateAvailableDialog(
  BuildContext context,
  ReleaseInfo release,
) async {
  final openReleasePage = await showAdaptiveAlertDialog<bool>(
    context: context,
    title: '发现新版本 ${release.name}',
    message: release.notes,
    actions: const [
      AdaptiveAlertAction<bool>(label: '以后再说'),
      AdaptiveAlertAction<bool>(
        label: '前往更新',
        value: true,
        isDefault: true,
      ),
    ],
  );
  if (openReleasePage == true) {
    await _openReleasePage(release.source);
  }
}

/// The manual check ran and found nothing newer. Only the manual path says this:
/// the silent one has nothing to report when it succeeds quietly.
Future<void> showUpToDateDialog(
  BuildContext context,
  String version, {
  required UpdateSource source,
}) {
  return showAdaptiveAlertDialog<void>(
    context: context,
    title: '已是最新版本',
    message: '当前版本 $version 已是 ${source.label} 上的最新版本。',
    actions: const [AdaptiveAlertAction<void>(label: '好')],
  );
}

/// The manual check failed. Offer to open the release page directly.
Future<void> showUpdateFailureDialog(
  BuildContext context, {
  required String message,
  required UpdateSource source,
}) async {
  final instructions = switch (source) {
    UpdateSource.github => '可以前往 GitHub 的 releases 页面查看最新版本，并手动下载。',
    UpdateSource.appStore => '可以前往 App Store 查看更新。',
  };
  final openReleasePage = await showAdaptiveAlertDialog<bool>(
    context: context,
    title: '检查更新失败',
    message: '$message\n\n$instructions',
    actions: [
      const AdaptiveAlertAction<bool>(label: '取消'),
      AdaptiveAlertAction<bool>(
        label: '前往 ${source.label}',
        value: true,
        isDefault: true,
      ),
    ],
  );
  if (openReleasePage == true) {
    await _openReleasePage(source);
  }
}

Future<void> _openReleasePage(UpdateSource source) async {
  try {
    await launchUrl(
      Uri.parse(source.releasePage),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    // The dialog already names the destination if the device cannot open it.
  }
}
