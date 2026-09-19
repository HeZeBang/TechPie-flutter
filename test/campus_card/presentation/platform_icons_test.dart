import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/presentation/icons/platform_icons.dart';

void main() {
  test('every semantic icon has Apple and Material resources', () {
    expect(GpPlatformIcons.all, hasLength(37));
    for (final icon in GpPlatformIcons.all) {
      final apple = icon.forPlatform(TargetPlatform.iOS);
      final mac = icon.forPlatform(TargetPlatform.macOS);
      final android = icon.forPlatform(TargetPlatform.android);
      expect(apple, icon.apple);
      expect(mac, icon.apple);
      expect(android, icon.android);
      expect(apple.fontPackage, CupertinoIcons.iconFontPackage);
      expect(android.fontFamily, 'MaterialIcons');
    }
  });

  testWidgets('theme platform controls the icon selected by a widget', (
    tester,
  ) async {
    Future<IconData> resolve(TargetPlatform platform) async {
      late IconData resolved;
      await tester.pumpWidget(
        MaterialApp(
          key: ValueKey(platform),
          theme: ThemeData(platform: platform),
          home: Builder(
            builder: (context) {
              resolved = GpPlatformIcons.scan(context);
              return Icon(resolved);
            },
          ),
        ),
      );
      return resolved;
    }

    expect(await resolve(TargetPlatform.iOS), GpPlatformIcons.scan.apple);
    expect(await resolve(TargetPlatform.android), GpPlatformIcons.scan.android);
  });
}
