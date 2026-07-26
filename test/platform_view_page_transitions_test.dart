import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_platform_view_page_transitions.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('iOS navigation uses CupertinoPageRoute', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final observer = _RouteObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              pushPlatformViewPage<void>(
                context,
                builder: (_) => const Scaffold(body: Text('Next page')),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(observer.lastPushedRoute, isA<CupertinoPageRoute<void>>());
    debugDefaultTargetPlatformOverride = null;

    await tester.pumpAndSettle();
    expect(find.text('Next page'), findsOneWidget);
  });

  testWidgets('non-iOS navigation uses MaterialPageRoute', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final observer = _RouteObserver();

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => unawaited(
              pushPlatformViewPage<void>(
                context,
                builder: (_) => const Scaffold(body: Text('Next page')),
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(observer.lastPushedRoute, isA<MaterialPageRoute<void>>());
    debugDefaultTargetPlatformOverride = null;
  });
}

class _RouteObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    lastPushedRoute = route;
    super.didPush(route, previousRoute);
  }
}
