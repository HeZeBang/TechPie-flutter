import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/ios_liquid/ios_platform_view_page_transitions.dart';

void main() {
  const presenterChannel = MethodChannel('techpie/native_glass_presenter');

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('animated iOS route delegates the transition to UIKit', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenterChannel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presenterChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
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
    await tester.pump();

    expect(find.text('Next page'), findsOneWidget);
    expect(nativeCalls.map((call) => call.method), [
      'beginPageTransition',
      'finishPageTransition',
    ]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('reduced motion skips native iOS page transition animation', (
    WidgetTester tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;

    final nativeCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(presenterChannel, (call) async {
      nativeCalls.add(call);
      return null;
    });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(presenterChannel, null),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: Builder(
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
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pump();

    expect(find.text('Next page'), findsOneWidget);
    expect(nativeCalls, isEmpty);
    debugDefaultTargetPlatformOverride = null;
  });
}
