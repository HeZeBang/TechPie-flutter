import 'package:flutter/material.dart';

/// Keep TechPie's palette, typography and component styles as the source of
/// truth, including dynamic colors, platform styling and AMOLED surfaces.
/// Only delay incidental hover help in the densely interactive chat workspace.
ThemeData genAiTheme(ThemeData base) => base.copyWith(
      tooltipTheme: base.tooltipTheme.copyWith(
        waitDuration: const Duration(milliseconds: 700),
        showDuration: const Duration(seconds: 2),
      ),
    );
