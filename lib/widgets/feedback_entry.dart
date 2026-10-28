import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'adaptive_alert_dialog.dart';

/// Opens the public feedback page and provides a usable fallback on failure.
class FeedbackEntry extends StatefulWidget {
  const FeedbackEntry({super.key, this.launcher});

  final Future<bool> Function(Uri)? launcher;

  @override
  State<FeedbackEntry> createState() => _FeedbackEntryState();
}

class _FeedbackEntryState extends State<FeedbackEntry> {
  static final _url = Uri.parse('https://techpie-feedback.dzhes.app');
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      var opened = false;
      try {
        opened = await (widget.launcher?.call(_url) ??
            launchUrl(_url, mode: LaunchMode.externalApplication));
      } catch (_) {
        // Both a false result and a platform failure need the same recovery.
      }
      if (opened || !mounted) return;
      final copy = await showAdaptiveAlertDialog<bool>(
        context: context,
        title: '无法打开反馈页面',
        message: '请复制链接后在浏览器中打开。\n$_url',
        actions: const [
          AdaptiveAlertAction(label: '关闭', value: false),
          AdaptiveAlertAction(label: '复制链接', value: true, isDefault: true),
        ],
      );
      if (copy == true) await Clipboard.setData(ClipboardData(text: '$_url'));
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
        leading: const Icon(Icons.feedback_outlined),
        title: const Text('用户反馈与工单'),
        subtitle: const Text('提交问题、建议，或查看工单进度'),
        trailing: const Icon(Icons.open_in_new),
        enabled: !_opening,
        onTap: () => unawaited(_open()),
      );
}
