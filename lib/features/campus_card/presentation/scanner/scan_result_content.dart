import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/models/scan_models.dart';
import '../../domain/ports/platform_ports.dart';
import '../icons/platform_icons.dart';
import '../theme/colors.dart';
import '../theme/tokens.dart';
import '../widgets/apple_wallet_components.dart';

final class ScanFailureContent extends StatefulWidget {
  const ScanFailureContent({
    super.key,
    required this.message,
    required this.onRescan,
    this.feedback,
  });

  final String message;
  final VoidCallback onRescan;
  final FeedbackPort? feedback;

  @override
  State<ScanFailureContent> createState() => _ScanFailureContentState();
}

class _ScanFailureContentState extends State<ScanFailureContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(widget.feedback?.play(FeedbackEvent.error));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          GpPlatformIcons.errorCircle(context),
          color: context.gpColors.danger,
          size: 82,
        ),
        const SizedBox(height: 20),
        const Text(
          '识别失败',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Text(
          widget.message,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: context.gpColors.textSecondary,
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 28),
        FilledButton(
          onPressed: widget.onRescan,
          style: FilledButton.styleFrom(
            backgroundColor: context.gpColors.action,
            minimumSize: const Size.fromHeight(54),
            shape: const StadiumBorder(),
          ),
          child: const Text('重新扫码'),
        ),
      ],
    );
  }
}

final class ScanResultContent extends StatelessWidget {
  const ScanResultContent({
    super.key,
    required this.success,
    required this.onDone,
    this.feedback,
  });

  final ScanSucceeded success;
  final VoidCallback onDone;
  final FeedbackPort? feedback;

  @override
  Widget build(BuildContext context) {
    final title = switch (success.kind) {
      ScanSuccessKind.payment => '支付成功',
      ScanSuccessKind.attendance => '签到成功',
      ScanSuccessKind.openDevice => '开阀成功',
      ScanSuccessKind.bindTray => '绑盘成功',
      ScanSuccessKind.unknown => '处理完成',
    };
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedSuccessCheck(
          size: 112,
          color: success.kind == ScanSuccessKind.payment
              ? GpTokens.campusRed
              : null,
          reduceMotion: MediaQuery.disableAnimationsOf(context),
          feedback: feedback,
        ),
        const SizedBox(height: 22),
        Text(
          title,
          style: TextStyle(
            color: success.kind == ScanSuccessKind.payment ? GpTokens.campusRed : null,
            fontSize: 26,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (success.kind == ScanSuccessKind.payment &&
            success.amount != null) ...[
          const SizedBox(height: 12),
          Text(
            formatMoneyFen(success.amount!.value),
            style: const TextStyle(
              color: GpTokens.campusRed,
              fontSize: 44,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (success.fee != null && success.fee!.value > 0) ...[
          const SizedBox(height: 8),
          Text(
            '含管理费 ${formatMoneyFen(success.fee!.value)}',
            style: TextStyle(color: context.gpColors.textSecondary),
          ),
        ],
        if (success.message != null && success.message!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(
            success.message!,
            textAlign: TextAlign.center,
            style: TextStyle(color: context.gpColors.textSecondary),
          ),
        ],
        for (final detail in <String, String?>{
          '支付时间': success.paidAt == null
              ? null
              : DateFormat(
                  'yyyy-MM-dd HH:mm:ss',
                ).format(success.paidAt!.toLocal()),
          '授权码': success.authorizationCode,
          '交易流水号': success.transactionId,
          '终端编号': success.terminalCode,
          '交易代码': success.transactionCode,
        }.entries)
          if (detail.value != null) ...[
            const SizedBox(height: 8),
            Text(
              '${detail.key} ${detail.value}',
              textAlign: TextAlign.center,
              style: TextStyle(color: context.gpColors.textSecondary),
            ),
          ],
        if (success.balance != null) ...[
          const SizedBox(height: 8),
          Text(
            '交易后余额 '
            '${formatMoneyFen(success.balance!.value)}',
            style: TextStyle(color: context.gpColors.textSecondary),
          ),
        ],
        const SizedBox(height: 30),
        FilledButton(
          onPressed: onDone,
          style: FilledButton.styleFrom(
            backgroundColor: context.gpColors.action,
            minimumSize: const Size.fromHeight(54),
            shape: const StadiumBorder(),
          ),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
