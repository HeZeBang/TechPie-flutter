import 'package:flutter/widgets.dart';

bool appAnimationsEnabled(BuildContext context) =>
    !MediaQuery.disableAnimationsOf(context);

Duration appAnimationDuration(
  BuildContext context,
  Duration duration,
) =>
    appAnimationsEnabled(context) ? duration : Duration.zero;
