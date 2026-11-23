import 'package:flutter/material.dart';

class IdsRebindBanner extends StatelessWidget {
  const IdsRebindBanner({super.key, required this.onRebind});
  final VoidCallback onRebind;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      child: Semantics(
        button: true,
        child: Material(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onRebind,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.key_rounded,
                      size: MediaQuery.textScalerOf(context).scale(22),
                      color: colors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '更新校园登录方式',
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.3,
                            fontWeight: FontWeight.w600,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '绑定 IDS Passkey，继续使用校园服务。',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.35,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '重新绑定',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
