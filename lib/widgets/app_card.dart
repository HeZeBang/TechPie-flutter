import 'package:flutter/material.dart';

import '../models/feature.dart';
import '../theme/tp_icons.dart';
import 'design_system/tp_feature_grid.dart';

class AppCard extends StatelessWidget {
  final List<Feature> features;
  final int rows;
  final int columns;
  final ValueChanged<Feature>? onFeatureTap;

  const AppCard({
    super.key,
    required this.features,
    this.rows = 2,
    this.columns = 4,
    this.onFeatureTap,
  });

  @override
  Widget build(BuildContext context) {
    if (features.isEmpty) {
      return const SizedBox.shrink();
    }

    final capacity = columns * rows;
    final hasOverflow = features.length > capacity;
    final visible = hasOverflow
        ? [...features.take(capacity - 1), moreFeature]
        : features;

    return TpFeatureGrid(
      columns: columns,
      items: [
        for (final feature in visible)
          TpFeatureGridItem(
            id: feature.id,
            label: feature.description,
            icon: feature.icon.icon ?? TpIcons.activities,
            onTap: () => onFeatureTap?.call(feature),
          ),
      ],
    );
  }
}
