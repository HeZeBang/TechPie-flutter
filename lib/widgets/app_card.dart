import 'package:flutter/material.dart';

import '../models/feature.dart';

class AppCard extends StatelessWidget {
  final List<Feature> features;
  final ValueChanged<Feature>? onFeatureTap;

  const AppCard({
    super.key,
    required this.features,
    this.onFeatureTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (features.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const itemWidth = 72.0;
        const sideRatio = 0.6;
        final availableWidth = constraints.maxWidth;
        const minGap = 12.0;
        final rawPerRow =
            ((availableWidth - (2 * sideRatio - 1) * minGap) /
                    (itemWidth + minGap))
                .floor();
        final effectivePerRow = rawPerRow < 1 ? 1 : rawPerRow;
        final freeWidth = availableWidth - effectivePerRow * itemWidth;
        final gap = freeWidth > 0
            ? freeWidth / (effectivePerRow - 1 + 2 * sideRatio)
            : 0.0;
        final sidePadding = gap * sideRatio;
        return Material(
          color: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: sidePadding,
              vertical: 12,
            ),
            child: Wrap(
              // Tiny slack keeps float rounding from wrapping a row early.
              spacing: gap > 0.01 ? gap - 0.01 : 0,
              runSpacing: 12,
              children: [
                for (final feature in features)
                  SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        onFeatureTap?.call(feature);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconTheme(
                              data: IconThemeData(
                                color: theme.colorScheme.primary,
                                size: 28,
                              ),
                              child: feature.icon,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              feature.description,
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
