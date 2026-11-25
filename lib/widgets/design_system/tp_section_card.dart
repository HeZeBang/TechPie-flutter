import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_card.dart';

/// Inset grouped section wrapper with a muted uppercase-style label above a
/// [TpCard] containing list rows or controls.
class TpSectionCard extends StatelessWidget {
  const TpSectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            TpTokens.space2,
            0,
            TpTokens.space2,
            TpTokens.space2,
          ),
          child: Text(
            title,
            style: TpTypography.cardMeta(colors).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TpCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}
