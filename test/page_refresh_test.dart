import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/presentation/widgets/apple_wallet_components.dart';
import 'package:techpie/widgets/adaptive_feedback.dart';
import 'package:techpie/widgets/page_refresh.dart';

void main() {
  Widget host(Widget child) => MaterialApp(
        builder: (context, child) => AdaptiveFeedbackHost(
          key: adaptiveFeedbackHostKey,
          child: child!,
        ),
        home: Scaffold(body: child),
      );

  testOnPlatform('Linux refresh awaits the full task and blocks repeat clicks', (tester) async {
    final first = Completer<void>();
    final second = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      host(
        PageRefreshButton(
          onRefresh: () {
            calls++;
            return calls == 1 ? first.future : second.future;
          },
        ),
      ),
    );
    // Invoke twice before the next frame as well as through the disabled UI.
    final click = tester.widget<IconButton>(find.byType(IconButton)).onPressed!;
    click();
    click();
    await tester.pump();
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    first.complete();
    await tester.pump();
    await tester.tap(find.byTooltip('刷新'));
    expect(calls, 2);
    second.complete();
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testOnPlatform('a refresh failure is visible and can be retried', (tester) async {
    var calls = 0;
    await tester.pumpWidget(
      host(
        PageRefreshButton(
          onRefresh: () async {
            if (++calls == 1) throw StateError('failed');
          },
        ),
      ),
    );
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(find.text('刷新失败，请重试'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('刷新'));
    await tester.pump();
    expect(calls, 2);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testOnPlatform('background loading disables refresh and disposal is safe', (tester) async {
    final pending = Completer<void>();
    await tester.pumpWidget(
      host(
        PageRefreshButton(
          refreshing: true,
          onRefresh: () => pending.future,
        ),
      ),
    );
    expect(tester.widget<IconButton>(find.byType(IconButton)).onPressed, isNull);
    await tester.pumpWidget(host(PageRefreshButton(onRefresh: () => pending.future)));
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.completeError(StateError('late failure'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  for (final platform in TargetPlatform.values) {
    testOnPlatform(
      '$platform uses the expected refresh interaction',
      (tester) async {
        await tester.pumpWidget(
          host(
            Column(
              children: [
                PageRefreshButton(onRefresh: () async {}),
                Expanded(
                  child: PageRefreshIndicator(
                    onRefresh: () async {},
                    child: ListView(children: const [Text('Empty or failed page')]),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(
          find.byType(IconButton),
          platform == TargetPlatform.linux ? findsOneWidget : findsNothing,
        );
        expect(
          find.byType(RefreshIndicator),
          platform == TargetPlatform.linux ? findsNothing : findsOneWidget,
        );
        await tester.pumpWidget(
          host(
            CustomScrollView(
              slivers: [
                EcardSliverRefreshControl(onRefresh: () async {}),
              ],
            ),
          ),
        );
        expect(
          find.byType(CupertinoSliverRefreshControl, skipOffstage: false),
          platform == TargetPlatform.linux ? findsNothing : findsOneWidget,
        );
      },
      platform: platform,
    );
  }
}

void testOnPlatform(
  String description,
  WidgetTesterCallback callback, {
  TargetPlatform platform = TargetPlatform.linux,
}) =>
    testWidgets(description, callback, variant: TargetPlatformVariant({platform}));
