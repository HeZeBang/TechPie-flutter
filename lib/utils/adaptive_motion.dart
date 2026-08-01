import 'package:flutter/widgets.dart';

import 'platform.dart';

bool appAnimationsEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

Duration appAnimationDuration(
  BuildContext context,
  Duration duration,
) =>
    appAnimationsEnabled(context) ? duration : Duration.zero;

Curve appAnimationCurve(
  Curve materialCurve, {
  Curve iosCurve = Curves.easeInOut,
}) =>
    isIos() ? iosCurve : materialCurve;
