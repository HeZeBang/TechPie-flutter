import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/theme/tp_icons.dart';

/// Pages explicitly exempted from the TechPie Design System content guardrails.
///
/// Repository-wide enforcement is **default-on** for every `.dart` file in
/// `lib/pages/` and `lib/widgets/gym/`. Only WebView/auth bridges, immersive
/// video playback, the dedicated Campus Card host (bridged separately via
/// `GpColors.fromTheme`), and developer/debug utilities belong here.
const Set<String> designSystemExemptPages = <String>{
  // WebView & SSO bridges
  'lib/pages/campus_session_handle.dart',
  'lib/pages/generic_webview_page.dart',
  'lib/pages/uni_auth_webview_page.dart',
  'lib/pages/webview_host.dart',
  // Immersive video player
  'lib/pages/elrc_player_page.dart',
  // Dedicated Campus Card host (bridges via GpColors.fromTheme)
  'lib/pages/campus_card_page.dart',
  // Developer & debug utilities
  'lib/pages/debug_log_page.dart',
  'lib/pages/debug_webview_page.dart',
  'lib/pages/developer_lab_page.dart',
};

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

List<String> _dartFilesIn(String directoryPath) {
  final dir = Directory(directoryPath);
  if (!dir.existsSync()) return const [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .map((file) => file.path.replaceAll('\\', '/'))
      .where((path) => path.endsWith('.dart'))
      .toList()
    ..sort();
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
      'lib/widgets/design_system/design_system.dart',
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

  test('all exempt design system paths exist on disk', () {
    for (final path in designSystemExemptPages) {
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Stale exemption in designSystemExemptPages: $path',
      );
    }
  });

  test(
    'every non-exempt page and gym module conforms to TechPie Design System guardrails',
    () {
      final targets = <String>[
        ..._dartFilesIn('lib/pages')
            .where((path) => !designSystemExemptPages.contains(path)),
        ..._dartFilesIn('lib/widgets/gym'),
      ];
      expect(targets, isNotEmpty);

      final allViolations = <String>[];
      for (final path in targets) {
        final violations = findDesignSystemViolations(
          File(path).readAsStringSync(),
        );
        for (final violation in violations) {
          allViolations.add('$path: $violation');
        }
      }

      expect(
        allViolations,
        isEmpty,
        reason: 'Files violate docs/DESIGN_SYSTEM.md:\n'
            '${allViolations.join('\n')}',
      );
    },
  );
}
