import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/theme/tp_icons.dart';

/// Pages locked to the unified TechPie Design System (`docs/DESIGN_SYSTEM.md`).
///
/// Each migration PR appends newly migrated pages here until PR 8 enables
/// repository-wide enforcement with explicit exemptions.
const List<String> migratedDesignSystemPages = <String>[
  'lib/pages/home_page.dart',
];

final _rawHexColorPattern = RegExp(r'\bColor\s*\(\s*0x[0-9A-Fa-f]+');
final _legacyMaterialCardPattern = RegExp(r'\bCard\.(outlined|filled)\b');
final _platformStyleBranchPattern =
    RegExp(r'\b(isIos|usesIosLiquidGlass|usesLegacyIosChrome)\s*\(');
final _magicBorderRadiusPattern =
    RegExp(r'BorderRadius\.circular\(\s*\d+(?:\.\d+)?\s*\)');

List<String> findDesignSystemViolations(String source) {
  final violations = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final trimmed = line.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;

    final lineNumber = i + 1;
    if (_rawHexColorPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw Color(0x...) literal — use context.tpColors instead',
      );
    }
    if (_legacyMaterialCardPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: legacy Card.outlined/filled — use TpCard instead',
      );
    }
    if (_platformStyleBranchPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: direct platform style branch in page — encapsulate in shell/adaptive widget',
      );
    }
    if (_magicBorderRadiusPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: magic BorderRadius.circular(...) — use TpTokens.radius* instead',
      );
    }
  }
  return violations;
}

void main() {
  test('design system specification and foundation files exist', () {
    for (final path in [
      'docs/DESIGN_SYSTEM.md',
      'lib/theme/theme.dart',
      'lib/theme/tp_tokens.dart',
      'lib/theme/tp_colors.dart',
      'lib/theme/tp_typography.dart',
      'lib/theme/tp_icons.dart',
    ]) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Missing required design system file: $path',
      );
    }
  });

  test('TpIcons resolves pure-Dart flutter_lucide font glyphs', () {
    for (final icon in [
      TpIcons.home,
      TpIcons.schedule,
      TpIcons.deadlines,
      TpIcons.profile,
      TpIcons.campusCard,
      TpIcons.recordings,
      TpIcons.gym,
      TpIcons.linkedAccounts,
      TpIcons.sidebar,
    ]) {
      expect(icon.fontFamily, 'lucide');
      expect(icon.fontPackage, 'flutter_lucide');
    }
  });

  test('guard detects all four forbidden style drift patterns', () {
    const badSnippet = '''
Widget build(BuildContext context) {
  final c = const Color(0xFF123456);
  final ios = isIos();
  return Card.outlined(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(13),
    ),
  );
}
''';
    final violations = findDesignSystemViolations(badSnippet);
    expect(violations, hasLength(4));

    const cleanSnippet = '''
Widget build(BuildContext context) {
  final colors = context.tpColors;
  return Container(
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(TpTokens.radiusM),
    ),
  );
}
''';
    expect(findDesignSystemViolations(cleanSnippet), isEmpty);
  });

  test('migrated pages conform to the TechPie Design System guardrails', () {
    for (final path in migratedDesignSystemPages) {
      final file = File(path);
      expect(
        file.existsSync(),
        isTrue,
        reason: 'Migrated page listed in guard does not exist: $path',
      );
      final violations = findDesignSystemViolations(file.readAsStringSync());
      expect(
        violations,
        isEmpty,
        reason: '$path violates docs/DESIGN_SYSTEM.md:\n${violations.join('\n')}',
      );
    }
  });
}
