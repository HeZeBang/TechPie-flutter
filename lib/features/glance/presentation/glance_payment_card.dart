import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../campus_card/presentation/theme/tokens.dart';
import '../../campus_card/presentation/widgets/payment_code_qr.dart';

/// Renders an online payment code on a light card that stays readable on both
/// the cover and the rear screen. The caller supplies the data and the
/// countdown widget, so the preview can reuse the exact layout without polling.
class GlancePaymentCard extends StatelessWidget {
  const GlancePaymentCard({
    super.key,
    required this.payload,
    required this.binaryPayload,
    required this.statusLabel,
    required this.hint,
    required this.onTap,
    this.balanceText,
    this.countdown,
    this.qrKey = const Key('glance-payment-qr'),
  });

  final String payload;
  final bool binaryPayload;
  final String statusLabel;
  final String hint;
  final VoidCallback onTap;
  final String? balanceText;
  final Widget? countdown;
  final Key qrKey;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: GpTokens.cardCanvas,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final landscape = constraints.maxWidth > constraints.maxHeight;
          final large = landscape &&
              constraints.maxWidth >= 380 &&
              constraints.maxHeight >= 300;
          if (landscape) {
            final qrSize = math
                .min(constraints.maxWidth * 0.55, constraints.maxHeight - 10)
                .clamp(90.0, 280.0)
                .toDouble();
            return Row(
              children: [
                PaymentCodeQr(
                  payload: payload,
                  binaryPayload: binaryPayload,
                  size: qrSize,
                  onTap: onTap,
                  qrKey: qrKey,
                ),
                SizedBox(width: large ? 18 : 10),
                Expanded(
                  child: _PaymentDetails(
                    statusLabel: statusLabel,
                    balanceText: balanceText,
                    hint: hint,
                    countdown: countdown,
                    compact: true,
                    large: large,
                  ),
                ),
              ],
            );
          }

          final qrSize = math
              .min(constraints.maxWidth - 10, constraints.maxHeight * 0.60)
              .clamp(120.0, 260.0)
              .toDouble();
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PaymentDetails(
                statusLabel: statusLabel,
                balanceText: balanceText,
                hint: null,
                countdown: null,
                compact: false,
                large: false,
              ),
              const SizedBox(height: 6),
              PaymentCodeQr(
                payload: payload,
                binaryPayload: binaryPayload,
                size: qrSize,
                onTap: onTap,
                qrKey: qrKey,
              ),
              if (countdown != null) ...[
                const SizedBox(height: 4),
                countdown!,
              ],
              const SizedBox(height: 2),
              Text(
                hint,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  color: GpTokens.campusRed.withValues(alpha: 0.55),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PaymentDetails extends StatelessWidget {
  const _PaymentDetails({
    required this.statusLabel,
    required this.balanceText,
    required this.hint,
    required this.countdown,
    required this.compact,
    required this.large,
  });

  final String statusLabel;
  final String? balanceText;
  final String? hint;
  final Widget? countdown;
  final bool compact;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment:
          compact ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Text(
          statusLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: compact ? (large ? 12 : 10) : 11,
            fontWeight: FontWeight.w600,
            color: GpTokens.campusRed,
          ),
        ),
        if (balanceText != null) ...[
          SizedBox(height: compact ? (large ? 4 : 2) : 1),
          Text(
            balanceText!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? (large ? 26 : 18) : 20,
              fontWeight: FontWeight.w700,
              color: GpTokens.campusRed,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
        if (countdown != null) ...[
          SizedBox(height: large ? 6 : 3),
          countdown!,
        ],
        if (hint != null) ...[
          SizedBox(height: large ? 6 : 4),
          Text(
            hint!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: large ? 10 : 9,
              color: GpTokens.campusRed.withValues(alpha: 0.55),
            ),
          ),
        ],
      ],
    );
  }
}

/// Static preview used by the settings page: a real QR of a harmless sample
/// payload, no auth, no polling, and no offline quota.
class GlancePaymentPreviewCard extends StatelessWidget {
  const GlancePaymentPreviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    return GlancePaymentCard(
      payload: 'https://techpie.geekpie.club',
      binaryPayload: false,
      statusLabel: '示例消费码',
      balanceText: '¥ 128.00',
      hint: '预览，不会生成付款码',
      countdown: Text(
        '30秒后刷新',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 10,
          color: GpTokens.campusRed.withValues(alpha: 0.62),
        ),
      ),
      onTap: () {},
    );
  }
}
