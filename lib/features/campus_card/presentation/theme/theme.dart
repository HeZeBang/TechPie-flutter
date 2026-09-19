import 'package:flutter/material.dart';

import 'colors.dart';

abstract final class GeekPayTheme {
  /// Adds campus-card semantic colors while preserving the host theme.
  static ThemeData inherit(ThemeData host) {
    final extensions = Map<Object, ThemeExtension<dynamic>>.of(host.extensions);
    extensions[GpColors] = GpColors.fromTheme(host);
    return host.copyWith(extensions: extensions.values);
  }
}
