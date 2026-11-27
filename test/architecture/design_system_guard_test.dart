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

/// Transition rules that new pages must obey immediately while legacy pages are
/// progressively migrated across staged PRs (anti-stale ratcheted allowlist).
enum DesignSystemRule {
  bareCard,
  bareAppBar,
  materialIcons,
  rawSnackBar,
}

/// Strictly shrinking allowlist of existing pages with remaining legacy
/// Material usage. Any migrated page MUST be removed immediately.
const Map<String, Set<DesignSystemRule>> legacyMaterialTransitionPages =
    <String, Set<DesignSystemRule>>{
  'lib/pages/assignments_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/custom_course_editor_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/feedback_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/hidden_assignments_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/schedule_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/sync_settings_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
  'lib/pages/third_party_accounts_page.dart': <DesignSystemRule>{
    DesignSystemRule.materialIcons,
  },
};

final _rawHexColorPattern = RegExp(r'\bColor\s*\(\s*0x[0-9A-Fa-f]+');
final _legacyMaterialCardPattern = RegExp(r'\bCard\.(outlined|filled)\b');
final _platformStyleBranchPattern =
    RegExp(r'\b(isIos|usesIosLiquidGlass|usesLegacyIosChrome)\s*\(');
final _magicBorderRadiusPattern =
    RegExp(r'BorderRadius\.circular\(\s*\d+(?:\.\d+)?\s*\)');

final _bareCardPattern = RegExp(r'(?<![A-Za-z0-9_])Card\s*\(');
final _bareAppBarPattern = RegExp(r'(?<![A-Za-z0-9_])AppBar\s*\(');
final _materialIconsPattern = RegExp(r'(?<![A-Za-z0-9_])Icons\.[A-Za-z0-9_]+');
final _rawSnackBarPattern = RegExp(r'\bshowSnackBar\s*\(');
final _rawSwitchPattern = RegExp(r'\b(Switch|SwitchListTile)\s*\(|\bSwitch\.adaptive\s*\(');
final _rawSegmentedButtonPattern = RegExp(r'\bSegmentedButton\s*(?:<|\()');
final _rawDropdownPattern = RegExp(r'\bDropdownButton(?:FormField)?\s*(?:<|\()');
final _rawDatePickerPattern = RegExp(r'\bshowDate(?:Range)?Picker\s*\(');

Set<DesignSystemRule> findMatchedLegacyRules(String source) {
  final matched = <DesignSystemRule>{};
  for (final line in source.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
    if (_bareCardPattern.hasMatch(line)) matched.add(DesignSystemRule.bareCard);
    if (_bareAppBarPattern.hasMatch(line)) {
      matched.add(DesignSystemRule.bareAppBar);
    }
    if (_materialIconsPattern.hasMatch(line)) {
      matched.add(DesignSystemRule.materialIcons);
    }
    if (_rawSnackBarPattern.hasMatch(line)) {
      matched.add(DesignSystemRule.rawSnackBar);
    }
  }
  return matched;
}

List<String> findDesignSystemViolations(
  String source, {
  Set<DesignSystemRule> allowedLegacyRules = const <DesignSystemRule>{},
}) {
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
    if (_rawSwitchPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw Switch / SwitchListTile — use AdaptiveSwitch / AdaptiveSwitchRow instead',
      );
    }
    if (_rawSegmentedButtonPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw SegmentedButton — use AdaptiveSegmentedControl instead',
      );
    }
    if (_rawDropdownPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw DropdownButton — use AdaptiveSelect instead',
      );
    }
    if (_rawDatePickerPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw showDatePicker / showDateRangePicker — use showAdaptiveDate*Picker instead',
      );
    }
    if (!allowedLegacyRules.contains(DesignSystemRule.bareCard) &&
        _bareCardPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: bare Material Card( — use TpCard instead',
      );
    }
    if (!allowedLegacyRules.contains(DesignSystemRule.bareAppBar) &&
        _bareAppBarPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: bare AppBar( — use AdaptiveNavigationScaffold.adaptiveBar instead',
      );
    }
    if (!allowedLegacyRules.contains(DesignSystemRule.materialIcons) &&
        _materialIconsPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: Material Icons.* — use TpIcons.* instead',
      );
    }
    if (!allowedLegacyRules.contains(DesignSystemRule.rawSnackBar) &&
        _rawSnackBarPattern.hasMatch(line)) {
      violations.add(
        'L$lineNumber: raw showSnackBar( — use showAdaptiveFeedback instead',
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
      'lib/theme/tp_density.dart',
      'lib/theme/tp_colors.dart',
      'lib/theme/tp_typography.dart',
      'lib/theme/tp_icons.dart',
      'lib/widgets/design_system/design_system.dart',
      'lib/widgets/design_system/tp_skeleton.dart',
      'lib/widgets/design_system/tp_state_card.dart',
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
      TpIcons.alertCircle,
      TpIcons.warning,
      TpIcons.inbox,
      TpIcons.command,
      TpIcons.wifiOff,
    ]) {
      expect(icon.fontFamily, 'lucide');
      expect(icon.fontPackage, 'flutter_lucide');
    }
  });

  test('guard detects all twelve forbidden style and control drift patterns', () {
    const badSnippet = '''
Widget build(BuildContext context) {
  final c = const Color(0xFF123456);
  final ios = isIos();
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('hi')));
  return Scaffold(
    appBar: AppBar(leading: Icon(Icons.home)),
    body: Column(
      children: [
        Card.outlined(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        Card(child: Text('bare')),
        Switch(value: true, onChanged: (_) {}),
        SegmentedButton<int>(segments: const [], selected: const {}, onSelectionChanged: (_) {}),
        DropdownButton<String>(items: const [], onChanged: (_) {}),
        ElevatedButton(onPressed: () => showDatePicker(context: context, firstDate: DateTime(2020), lastDate: DateTime(2030)), child: const Text('pick')),
      ],
    ),
  );
}
''';
    final violations = findDesignSystemViolations(badSnippet);
    expect(violations, hasLength(12));

    const cleanSnippet = '''
Widget build(BuildContext context) {
  final colors = context.tpColors;
  return AdaptiveNavigationScaffold(
    appBar: AdaptiveNavigationScaffold.adaptiveBar(
      title: const Text('Clean'),
      backIcon: TpIcons.chevronLeft,
    ),
    body: Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(TpTokens.radiusM),
      ),
      child: TpCard(
        leadingIcon: TpIcons.home,
        child: const Icon(CupertinoIcons.check_mark),
      ),
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

  test('legacyMaterialTransitionPages contains no missing or stale rules', () {
    for (final entry in legacyMaterialTransitionPages.entries) {
      final path = entry.key;
      final expectedRules = entry.value;
      expect(
        File(path).existsSync(),
        isTrue,
        reason: 'Missing file in legacyMaterialTransitionPages: $path',
      );
      expect(
        designSystemExemptPages.contains(path),
        isFalse,
        reason: 'Exempt file should not appear in transition allowlist: $path',
      );
      expect(
        expectedRules,
        isNotEmpty,
        reason: 'Empty rule set in legacyMaterialTransitionPages: $path',
      );
      final actualMatched =
          findMatchedLegacyRules(File(path).readAsStringSync());
      expect(
        actualMatched,
        expectedRules,
        reason: 'Stale or out-of-sync transition allowlist for $path. '
            'Update legacyMaterialTransitionPages to match actual code ($actualMatched).',
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
        final allowed =
            legacyMaterialTransitionPages[path] ?? const <DesignSystemRule>{};
        final violations = findDesignSystemViolations(
          File(path).readAsStringSync(),
          allowedLegacyRules: allowed,
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
