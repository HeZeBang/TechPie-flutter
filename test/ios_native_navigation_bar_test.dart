import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_native_navigation_bar.dart';

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
}
