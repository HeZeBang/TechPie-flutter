import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/adaptive_navigation_scaffold.dart';
import 'package:techpie/widgets/ios/ios_native_navigation_bar.dart';

void main() {
  setUp(() => debugDefaultTargetPlatformOverride = TargetPlatform.iOS);
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  void portrait(WidgetTester tester) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  double headerHeight(WidgetTester tester) => tester
      .renderObject<RenderSliver>(find.byType(CupertinoSliverNavigationBar))
      .geometry!
      .paintExtent;

  testWidgets('selection mode preserves the list position and native actions', (tester) async {
    portrait(tester);
    late StateSetter rebuild;
    var selection = false;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return AdaptiveNavigationScaffold(
              appBar: IosNativeNavigationBar(
                title: selection ? '已选择 1 个' : 'Deadlines',
                largeTitleMode: !selection,
                leadingItems: selection
                    ? const [IosNativeNavigationBarItem(id: 'cancel', title: '取消')]
                    : const [],
                onItemPressed: (_) => rebuild(() => selection = false),
              ),
              body: ListView.builder(
                key: const ValueKey('assignments'),
                itemExtent: 60,
                itemCount: 80,
                itemBuilder: (_, index) => Text('Assignment $index'),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(
      find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable)),
    );
    final offset = scrollable.position.pixels;
    final collapsed = headerHeight(tester);
    rebuild(() => selection = true);
    await tester.pumpAndSettle();
    expect(find.text('已选择 1 个'), findsOneWidget);
    expect(scrollable.position.pixels, closeTo(offset, 0.1));
    tester.widget<CNButton>(find.byType(CNButton)).onPressed!();
    await tester.pumpAndSettle();
    expect(find.byType(CupertinoSliverNavigationBar), findsOneWidget);
    expect(scrollable.position.pixels, closeTo(offset, 0.1));
    expect(headerHeight(tester), closeTo(collapsed, 0.1));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('timetable swipes, title collapse and pull-to-refresh coexist', (tester) async {
    portrait(tester);
    var refreshes = 0;
    var page = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: AdaptiveNavigationScaffold(
          appBar: const IosNativeNavigationBar(title: 'Schedule', largeTitleMode: true),
          body: RefreshIndicator(
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.vertical && notification.depth <= 1,
            onRefresh: () async => refreshes++,
            child: PageView.builder(
              itemCount: 2,
              onPageChanged: (value) => page = value,
              itemBuilder: (_, week) => SingleChildScrollView(
                key: ValueKey(week),
                physics: const AlwaysScrollableScrollPhysics(),
                child: const SizedBox(height: 1600, child: Text('Timetable')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));
    final expanded = headerHeight(tester);
    await tester.drag(find.byType(PageView), const Offset(-800, 0));
    await tester.pumpAndSettle();
    expect(page, 1);
    expect(headerHeight(tester), closeTo(expanded, 0.1));
    await tester.drag(find.byType(PageView), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(headerHeight(tester), lessThan(expanded));
    expect(find.text('Schedule').hitTestable(), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(0, 800));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(PageView), const Offset(0, 350));
    await tester.pumpAndSettle();
    expect(refreshes, greaterThan(0));
    expect(headerHeight(tester), closeTo(expanded, 0.1));
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });
}
