import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'design_system/design_system.dart';

class IdsRebindBanner extends StatelessWidget {
  const IdsRebindBanner({super.key, required this.onRebind});
  final VoidCallback onRebind;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    return Semantics(
      button: true,
      child: TpCard(
        onTap: onRebind,
        padding: const EdgeInsets.fromLTRB(
          TpTokens.cardPaddingHorizontal,
          TpTokens.space3,
          TpTokens.cardPaddingHorizontal,
          TpTokens.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                TpIcons.lock,
                size: MediaQuery.textScalerOf(context).scale(20),
                color: colors.brandInk,
              ),
            ),
            const SizedBox(width: TpTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '更新校园登录方式',
                    style: TpTypography.itemTitle(colors),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '绑定 IDS Passkey，继续使用校园服务。',
                    style: TpTypography.itemMeta(colors),
                  ),
                  const SizedBox(height: TpTokens.space2),
                  Text(
                    '重新绑定',
                    style: TpTypography.itemTitle(colors).copyWith(
                      fontWeight: FontWeight.w500,
                      color: colors.brandInk,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
