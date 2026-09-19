import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Contracts whose subject is an artifact something outside Dart consumes: the
/// lock's resolution, the pubspec's asset declarations, the Android manifest, the
/// iOS project, the bundled artwork.
///
/// Nothing here reads this repository's own Dart source. A source-text assertion
/// breaks when a symbol is renamed for a good reason and passes when the thing it
/// forbids returns under a new name — the feature's behaviour is covered by its
/// widget tests instead.
void main() {
  test('resolved package language versions fit the active Dart SDK', () {
    final sdk =
        Platform.version.split(' ').first.split('.').map(int.parse).toList();
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    for (final entry in config['packages'] as List<dynamic>) {
      final package = entry as Map<String, dynamic>;
      final language = (package['languageVersion'] as String)
          .split('.')
          .map(int.parse)
          .toList();
      expect(
        language[0] < sdk[0] ||
            (language[0] == sdk[0] && language[1] <= sdk[1]),
        isTrue,
        reason:
            '${package['name']} requires Dart ${package['languageVersion']}',
      );
    }
  });

  test('campus-card artwork is declared and bundled', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    for (final directory in ['audio', 'data', 'images']) {
      expect(
        pubspec,
        contains('- assets/campus_card/$directory/'),
        reason: directory,
      );
    }
    for (final path in [
      'assets/campus_card/images/card-full.png',
      'assets/campus_card/images/card-top.png',
      'assets/campus_card/images/card-bottom.png',
      'assets/campus_card/images/network-online.png',
      'assets/campus_card/images/network-offline.png',
      'assets/campus_card/images/network-warning.png',
      'assets/campus_card/images/widget-background.png',
      'assets/campus_card/audio/payment-success.wav',
      'assets/campus_card/audio/network-disconnected.wav',
    ]) {
      expect(File(path).lengthSync(), greaterThan(0), reason: path);
    }
  });

  test('TechPie declares the permissions the scanner and picker need', () {
    final manifest = File(
      'android/app/src/main/AndroidManifest.xml',
    ).readAsStringSync();
    final plist = File('ios/Runner/Info.plist').readAsStringSync();

    expect(manifest, contains('android.permission.CAMERA'));
    expect(plist, contains('NSCameraUsageDescription'));
    expect(plist, contains('NSPhotoLibraryUsageDescription'));
  });

  test('the home screen widget deep-links to the pay code', () {
    final widget = File(
      'ios/EcardPayWidget/EcardPayWidget.swift',
    ).readAsStringSync();
    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();

    // The URL scheme is the contract between the widget process and the app; the
    // appex target is what puts the widget on the home screen at all.
    expect(widget, contains('techpie://ecard/pay'));
    expect(project, contains('EcardPayWidget.appex'));
  });

  test('feature icons go through the platform icon layer', () {
    // The one source scan kept: `CupertinoIcons` is an API token from another
    // package, not our prose, so it cannot be renamed away to dodge this.
    final presentation = Directory(
      'lib/features/campus_card/presentation',
    );
    for (final entity in presentation.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('/icons/platform_icons.dart')) continue;
      expect(
        entity.readAsStringSync(),
        isNot(contains('CupertinoIcons.')),
        reason: entity.path,
      );
    }
  });
}
