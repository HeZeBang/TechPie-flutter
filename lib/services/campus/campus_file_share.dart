import 'package:flutter/foundation.dart';

import 'campus_file_share_io.dart' if (dart.library.js_interop) 'campus_file_share_web.dart' as impl;

enum CampusFileOpenStatus {
  opened,
  shared,
  downloaded,
  savedOnly,
}

class CampusFileOpenResult {
  const CampusFileOpenResult({
    required this.status,
    this.path,
  });

  const CampusFileOpenResult.downloaded() : this(status: CampusFileOpenStatus.downloaded);

  final CampusFileOpenStatus status;
  final String? path;

  bool get succeeded => status != CampusFileOpenStatus.savedOnly;
}

class CampusFileShare {
  CampusFileShare._();

  static final RegExp _scopePattern = RegExp(r'^[a-z0-9_-]{1,32}$');

  @visibleForTesting
  static String normalizeScope(String scope) {
    final trimmed = scope.trim().toLowerCase();
    if (!_scopePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(scope, 'scope', 'Invalid campus file scope');
    }
    return trimmed;
  }

  @visibleForTesting
  static String sanitizeFilename(String filename) {
    var base = filename.split(RegExp(r'[/\\]')).last.trim();
    base = base.replaceAll(RegExp(r'[\x00-\x1f\x7f<>:"|?*]'), '_');
    while (base.startsWith('.')) {
      base = base.substring(1);
    }
    base = base.replaceAll('..', '_');
    if (base.isEmpty || base == '.' || base == '..') {
      return 'file.bin';
    }
    if (base.length > 120) {
      final dot = base.lastIndexOf('.');
      if (dot > 0 && dot < base.length - 1 && base.length - dot <= 16) {
        final ext = base.substring(dot);
        return '${base.substring(0, 120 - ext.length)}$ext';
      }
      return base.substring(0, 120);
    }
    return base;
  }

  static Future<CampusFileOpenResult> openOrShare({
    required String scope,
    required String filename,
    required List<int> bytes,
    String? mimeType,
    bool preferShare = false,
  }) {
    final safeScope = normalizeScope(scope);
    final safeName = sanitizeFilename(filename);
    return impl.openOrShareImpl(
      scope: safeScope,
      filename: safeName,
      bytes: bytes,
      mimeType: mimeType,
      preferShare: preferShare,
    );
  }

  static Future<void> clearScopedFiles({String? scope}) {
    final safeScope = scope == null ? null : normalizeScope(scope);
    return impl.clearScopedFilesImpl(scope: safeScope);
  }
}
