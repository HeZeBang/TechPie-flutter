import 'package:flutter/material.dart';

import '../../theme/tp_colors.dart';
import '../../theme/tp_tokens.dart';
import '../../theme/tp_typography.dart';
import 'tp_press_scale.dart';
import 'tp_tap_surface.dart';

class TpFeatureGridItem {
  const TpFeatureGridItem({
    required this.id,
    required this.label,
    required this.icon,
    required this.onTap,
    this.key,
  });

  final String id;
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Key? key;
}

/// Uniform quick-action tile grid matching the TechPie showcase style:
/// rounded neutral icon tiles (`surfaceSubtle`) with brand-colored stroke icons.
class TpFeatureGrid extends StatelessWidget {
  const TpFeatureGrid({
    super.key,
    required this.items,
    this.columns = 4,
    this.padding = const EdgeInsets.fromLTRB(
      TpTokens.space3,
      TpTokens.space1,
      TpTokens.space3,
      TpTokens.space3,
    ),
  });

  final List<TpFeatureGridItem> items;
  final int columns;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final safeColumns = columns < 1 ? 1 : columns;
    final rows = <List<TpFeatureGridItem?>>[];
    for (var i = 0; i < items.length; i += safeColumns) {
      final row = <TpFeatureGridItem?>[];
      for (var c = 0; c < safeColumns; c++) {
        final idx = i + c;
        row.add(idx < items.length ? items[idx] : null);
      }
      rows.add(row);
    }

    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var r = 0; r < rows.length; r++) ...[
            if (r > 0) const SizedBox(height: TpTokens.space2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final item in rows[r])
                  Expanded(
                    child: item == null
                        ? const SizedBox.shrink()
                        : _FeatureTile(item: item),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({required this.item});

  final TpFeatureGridItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.tpColors;
    final radius = BorderRadius.circular(TpTokens.radiusS);
    return TpPressScale(
      pressedScale: 0.95,
      child: Material(
        color: Colors.transparent,
        child: TpTapSurface(
          key: item.key,
          style: TpTapFeedbackStyle.tile,
          borderRadius: radius,
          enablePressScale: false,
          onTap: item.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: TpTokens.space1 + 2,
              horizontal: 2,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ink(
                  width: TpTokens.featureTileSize,
                  height: TpTokens.featureTileSize,
                  decoration: BoxDecoration(
                    color: colors.surfaceSubtle,
                    borderRadius: radius,
                  ),
                  child: Icon(
                    item.icon,
                    size: TpTokens.iconM,
                    color: colors.brandInk,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.label,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TpTypography.featureLabel(colors),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
