import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../utils/platform.dart';

/// Platform-adaptive loading spinner using native Apple
/// `CupertinoActivityIndicator` on iOS/macOS and `CircularProgressIndicator`
/// elsewhere.
class AdaptiveActivityIndicator extends StatelessWidget {
  const AdaptiveActivityIndicator({
    super.key,
    this.size = 20.0,
    this.strokeWidth = 2.0,
    this.color,
    this.semanticLabel,
  });

  final double size;
  final double strokeWidth;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    if (isApplePlatform()) {
      final indicator = CupertinoActivityIndicator(
        radius: (size / 2).clamp(6.0, 20.0),
        color: color,
      );
      if (semanticLabel != null) {
        return Semantics(label: semanticLabel, child: indicator);
      }
      return indicator;
    }

    return SizedBox.square(
      dimension: size,
      child: CircularProgressIndicator(
        strokeWidth: strokeWidth,
        color: color,
        semanticsLabel: semanticLabel,
      ),
    );
  }
}
