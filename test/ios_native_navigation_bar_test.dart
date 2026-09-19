import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS header is backed by the native navigation bar', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          appBar: IosNativeNavigationBar(
            title: 'Cloud sync',
            leadingItems: [
              IosNativeNavigationBarItem(
                id: 'back',
                title: 'Settings',
                sfSymbol: 'chevron.left',
                accessibilityLabel: '返回 Settings',
              ),
            ],
          ),
          body: SizedBox(),
        ),
      ),
    );

    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    expect(platformView.viewType, 'techpie/native_navigation_bar');
    expect(platformView.creationParams, {
      'brightness': 'light',
      'title': 'Cloud sync',
      'subtitle': null,
      'leadingItems': [
        {
          'id': 'back',
          'title': 'Settings',
          'sfSymbol': 'chevron.left',
          'role': 'normal',
          'enabled': true,
          'hidden': false,
          'accessibilityLabel': '返回 Settings',
          'placementGroup': null,
          'menuItems': <Object?>[],
        },
      ],
      'trailingItems': <Object?>[],
      'selectionMode': false,
      'largeTitleMode': false,
    });
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('native header follows app theme changes without recreation',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final theme = ValueNotifier(ThemeData.light());
    addTearDown(theme.dispose);
    final updates = <Map<Object?, Object?>>[];
    const channel = MethodChannel('techpie/native_navigation_bar/987');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async {
        updates.add(call.arguments as Map<Object?, Object?>);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const page = Scaffold(
      appBar: IosNativeNavigationBar(title: 'Settings'),
    );
    await tester.pumpWidget(
      ValueListenableBuilder<ThemeData>(
        valueListenable: theme,
        builder: (_, value, child) => MaterialApp(theme: value, home: child),
        child: page,
      ),
    );
    final platformView = tester.widget<UiKitView>(find.byType(UiKitView));
    platformView.onPlatformViewCreated!(987);
    await tester.pump();
    expect(updates.last['brightness'], 'light');
    for (final value in [
      ThemeData.dark(),
      ThemeData.dark().copyWith(scaffoldBackgroundColor: Colors.black),
      ThemeData.light(),
    ]) {
      theme.value = value;
      await tester.pumpAndSettle();
      expect(updates.last['brightness'], value.brightness.name);
      expect(find.byType(UiKitView), findsOneWidget);
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
