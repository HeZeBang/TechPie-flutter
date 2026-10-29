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

  for (final platform in [
    TargetPlatform.linux,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.android,
  ]) {
    testWidgets(
      '$platform uses the appropriate refresh controls',
      (tester) async {
        final desktop = platform == TargetPlatform.linux ||
            platform == TargetPlatform.macOS ||
            platform == TargetPlatform.windows;
        await tester.pumpWidget(
          host(
            Column(
              children: [
                PageRefreshButton(onRefresh: () async {}),
                Expanded(
                  child: PageRefreshIndicator(
                    onRefresh: () async {},
                    child: ListView(children: const [Text('content')]),
                  ),
                ),
              ],
            ),
          ),
        );
        expect(find.byType(IconButton), desktop ? findsOneWidget : findsNothing);
        expect(
          find.byType(RefreshIndicator),
          desktop ? findsNothing : findsOneWidget,
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
          desktop ? findsNothing : findsOneWidget,
        );
      },
      variant: TargetPlatformVariant({platform}),
    );
  }

  testWidgets(
    'refresh waits for completion and supports retry after failure',
    (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(
        host(
          PageRefreshButton(
            onRefresh: () async {
              calls++;
              if (calls == 1) return gate.future;
              if (calls == 2) throw StateError('failed');
            },
          ),
        ),
      );

      final button = tester.widget<IconButton>(find.byType(IconButton));
      button.onPressed!();
      button.onPressed!();
      await tester.pump();
      expect(calls, 1);
      expect(find.byTooltip('正在刷新'), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(find.text('刷新失败，请重试'), findsOneWidget);

      await tester.tap(find.byTooltip('刷新'));
      await tester.pumpAndSettle();
      expect(calls, 3);
    },
    variant: const TargetPlatformVariant({TargetPlatform.linux}),
  );
}
