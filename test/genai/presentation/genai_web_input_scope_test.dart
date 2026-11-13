import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_web_input_scope.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

class _InputStatus extends StatelessWidget {
  const _InputStatus();

  @override
  Widget build(BuildContext context) =>
      Text(GenAiWebInputScope.blocks(context) ? 'blocked' : 'active');
}

Future<void> _showWorkspace(WidgetTester tester, {required Size size}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
  addTearDown(demo.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: const SizedBox.shrink()));
  unawaited(
    navigator.currentState!.push<void>(
      MaterialPageRoute(
        builder: (_) => GenAiWorkspace(
          controller: demo.workspace,
          audioRecorder: FakeGenAiAudioRecorder(),
          login: (_) async => null,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

bool _promptBlocked(WidgetTester tester) =>
    GenAiWebInputScope.blocks(tester.element(find.byKey(const ValueKey('genai-prompt'))));

void main() {
  for (final closeDialogFirst in [true, false]) {
    testWidgets('input stays blocked until both overlays close (dialog first: $closeDialogFirst)', (
      tester,
    ) async {
      final scope = ValueNotifier<bool>(false);
      addTearDown(scope.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: scope,
            child: const _InputStatus(),
            builder: (_, blocked, child) => GenAiWebInputScope(blocked: blocked, child: child!),
          ),
        ),
      );
      final context = tester.element(find.byType(_InputStatus));
      expect(find.text('active'), findsOneWidget);

      void openDialog() => unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => const Dialog(child: Text('modal')),
        ),
      );
      void closeDialog() => Navigator.of(context).pop();
      void blockScope() => scope.value = true;
      void unblockScope() => scope.value = false;
      final actions = closeDialogFirst
          ? [openDialog, blockScope, closeDialog, unblockScope]
          : [blockScope, openDialog, unblockScope, closeDialog];
      for (final action in actions.take(3)) {
        action();
        await tester.pumpAndSettle();
        expect(find.text('blocked'), findsOneWidget);
      }
      actions.last();
      await tester.pumpAndSettle();
      expect(find.text('active'), findsOneWidget);
    });
  }

  testWidgets('compact drawer publishes blocking and closing clears it', (tester) async {
    await _showWorkspace(tester, size: const Size(375, 812));
    expect(_promptBlocked(tester), isFalse);
    expect(find.byType(Drawer), findsNothing);

    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(_promptBlocked(tester), isTrue);
    tester.state<ScaffoldState>(find.byType(Scaffold)).closeDrawer();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(_promptBlocked(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned wide rail stays unblocked across collapse and expand', (tester) async {
    await _showWorkspace(tester, size: const Size(1200, 900));
    expect(find.byType(Drawer), findsNothing);
    expect(_promptBlocked(tester), isFalse);

    await tester.tap(find.byTooltip('收起侧栏'));
    await tester.pumpAndSettle();
    expect(_promptBlocked(tester), isFalse);

    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(_promptBlocked(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crossing the 960 boundary with an open drawer cannot leak blocking', (tester) async {
    await _showWorkspace(tester, size: const Size(959, 812));
    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    expect(_promptBlocked(tester), isTrue);

    // At the breakpoint the drawer leaves the tree; its flag must clear too.
    tester.view.physicalSize = const Size(960, 812);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(_promptBlocked(tester), isFalse);

    // Resizing back to compact must be visually consistent: either the drawer
    // stays closed and input is unblocked, or the drawer is visible and input
    // is blocked. A visible drawer that reports unblocked is the phantom state
    // this test rejects.
    tester.view.physicalSize = const Size(959, 812);
    await tester.pumpAndSettle();
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    final drawerVisible = find.byType(Drawer).evaluate().isNotEmpty;
    expect(
      _promptBlocked(tester),
      drawerVisible,
      reason: 'blocking must match whether the drawer covers the content',
    );
    expect(scaffold.isDrawerOpen, drawerVisible);
    if (drawerVisible) {
      scaffold.closeDrawer();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(_promptBlocked(tester), isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
