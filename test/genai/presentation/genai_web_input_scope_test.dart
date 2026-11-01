import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/presentation/genai_web_input_scope.dart';
import 'package:techpie/features/genai/presentation/genai_workspace.dart';

import '../support/fakes.dart';
import '../support/workspace_server.dart';

/// A stateful probe that publishes what the scope resolves for its context and
/// keeps observable state across scope toggles.
final class _Probe extends StatefulWidget {
  const _Probe();

  @override
  State<_Probe> createState() => _ProbeState();
}

final class _ProbeState extends State<_Probe> {
  bool blocked = false;
  bool blocks = false;
  int builds = 0;
  int taps = 0;

  void bump() => setState(() => taps++);

  @override
  Widget build(BuildContext context) {
    builds++;
    blocked = GenAiWebInputScope.blockedOf(context);
    blocks = GenAiWebInputScope.blocks(context);
    return Text(
      'probe: blocked=$blocked blocks=$blocks taps=$taps',
      textDirection: TextDirection.ltr,
    );
  }
}

/// Hosts the probe on a route so a dialog or menu can cover it, with a
/// test-controlled scope above it.
final class _RouteHarness extends StatelessWidget {
  const _RouteHarness({required this.scope});

  final ValueNotifier<bool> scope;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: ValueListenableBuilder<bool>(
              valueListenable: scope,
              builder: (_, blocked, __) => GenAiWebInputScope(
                blocked: blocked,
                child: const _Probe(),
              ),
            ),
          ),
          TextButton(
            key: const ValueKey('scope-open-dialog'),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const Dialog(
                child: SizedBox(width: 80, height: 80, child: Text('modal')),
              ),
            ),
            child: const Text('open'),
          ),
        ],
      ),
    );
  }
}

Future<(ValueNotifier<bool>, _ProbeState)> _pumpHarness(
  WidgetTester tester, {
  bool initial = false,
}) async {
  final scope = ValueNotifier<bool>(initial);
  addTearDown(scope.dispose);
  await tester.pumpWidget(MaterialApp(home: _RouteHarness(scope: scope)));
  return (scope, tester.state<_ProbeState>(find.byType(_Probe)));
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('scope-open-dialog')));
  await tester.pumpAndSettle();
  expect(find.text('modal'), findsOneWidget);
}

Future<void> _popRoute(WidgetTester tester) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pop();
  await tester.pumpAndSettle();
  expect(find.text('modal'), findsNothing);
}

Future<TestGenAiWorkspace> _showWorkspace(
  WidgetTester tester, {
  required Size size,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final demo = await TestGenAiWorkspace.create(chunkDelay: Duration.zero);
  addTearDown(demo.dispose);
  final navigator = GlobalKey<NavigatorState>();
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: navigator,
      home: const SizedBox.shrink(),
    ),
  );
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
  return demo;
}

/// The scope value published to the workspace body.
bool _publishedBlock(WidgetTester tester) =>
    tester.widget<GenAiWebInputScope>(find.byType(GenAiWebInputScope)).blocked;

/// What a child inside the workspace body resolves through the inherited scope.
bool _blockedAtPrompt(WidgetTester tester) => GenAiWebInputScope.blockedOf(
      tester.element(find.byKey(const ValueKey('genai-prompt'))),
    );

void main() {
  testWidgets('defaults to unblocked without a scope or route', (tester) async {
    await tester.pumpWidget(const _Probe());
    final probe = tester.state<_ProbeState>(find.byType(_Probe));
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isFalse);
  });

  testWidgets('scope toggles preserve the child state and only notify on change',
      (tester) async {
    const probe = _Probe();
    Widget tree(bool blocked) =>
        GenAiWebInputScope(blocked: blocked, child: probe);

    await tester.pumpWidget(tree(false));
    final state = tester.state<_ProbeState>(find.byType(_Probe));
    expect(state.blocked, isFalse);
    expect(state.blocks, isFalse);

    state.bump();
    await tester.pump();
    expect(state.taps, 1);
    final buildsWhileBlocked = state.builds;

    await tester.pumpWidget(tree(true));
    expect(identical(tester.state<_ProbeState>(find.byType(_Probe)), state), isTrue);
    expect(state.taps, 1);
    expect(state.blocked, isTrue);
    expect(state.blocks, isTrue);
    expect(state.builds, buildsWhileBlocked + 1);

    // Re-publishing the same value with the same child must not rebuild it.
    await tester.pumpWidget(tree(true));
    expect(state.builds, buildsWhileBlocked + 1);

    await tester.pumpWidget(tree(false));
    expect(identical(tester.state<_ProbeState>(find.byType(_Probe)), state), isTrue);
    expect(state.taps, 1);
    expect(state.blocked, isFalse);
    expect(state.blocks, isFalse);
  });

  testWidgets('a covering route blocks and popping restores input', (tester) async {
    final (_, probe) = await _pumpHarness(tester);
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isFalse);

    await _openDialog(tester);
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isTrue);

    await _popRoute(tester);
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isFalse);
  });

  testWidgets('route first: closing the scope cannot unblock while covered',
      (tester) async {
    final (scope, probe) = await _pumpHarness(tester);

    await _openDialog(tester);
    expect(probe.blocks, isTrue);

    scope.value = true;
    await tester.pump();
    expect(probe.blocked, isTrue);
    expect(probe.blocks, isTrue);

    // Popping the covered route must not re-enable input while the scope blocks.
    await _popRoute(tester);
    expect(probe.blocked, isTrue);
    expect(probe.blocks, isTrue);

    scope.value = false;
    await tester.pump();
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isFalse);
  });

  testWidgets('scope first: closing the route cannot unblock while scoped',
      (tester) async {
    // Start blocked so the probe's very first build evaluates the scope first;
    // a short-circuit there would leave it without a route dependency.
    final (scope, probe) = await _pumpHarness(tester, initial: true);
    expect(probe.blocked, isTrue);
    expect(probe.blocks, isTrue);
    final buildsBeforeCover = probe.builds;

    await _openDialog(tester);
    // Both reads register dependencies, so the covering route rebuilds the
    // probe even while the scope already blocks.
    expect(probe.builds, greaterThan(buildsBeforeCover));
    expect(probe.blocks, isTrue);

    // Closing the scope must not re-enable input while the route covers it.
    scope.value = false;
    await tester.pump();
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isTrue);

    await _popRoute(tester);
    expect(probe.blocked, isFalse);
    expect(probe.blocks, isFalse);
  });

  testWidgets('compact drawer publishes blocking and closing clears it',
      (tester) async {
    await _showWorkspace(tester, size: const Size(375, 812));
    final prompt = find.byKey(const ValueKey('genai-prompt'));
    expect(prompt, findsOneWidget);
    expect(_publishedBlock(tester), isFalse);
    expect(_blockedAtPrompt(tester), isFalse);
    expect(find.byType(Drawer), findsNothing);

    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsOneWidget);
    expect(_publishedBlock(tester), isTrue);
    expect(_blockedAtPrompt(tester), isTrue);
    expect(
      GenAiWebInputScope.blocks(tester.element(prompt)),
      isTrue,
      reason: 'the drawer is a local overlay, so the scope must carry the block',
    );

    tester.state<ScaffoldState>(find.byType(Scaffold)).closeDrawer();
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(_publishedBlock(tester), isFalse);
    expect(_blockedAtPrompt(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pinned wide rail stays unblocked across collapse and expand',
      (tester) async {
    await _showWorkspace(tester, size: const Size(1200, 900));
    expect(find.byType(Drawer), findsNothing);
    expect(_publishedBlock(tester), isFalse);
    expect(_blockedAtPrompt(tester), isFalse);

    await tester.tap(find.byTooltip('收起侧栏'));
    await tester.pumpAndSettle();
    expect(_publishedBlock(tester), isFalse);
    expect(_blockedAtPrompt(tester), isFalse);

    await tester.tap(find.byTooltip('展开侧栏'));
    await tester.pumpAndSettle();
    expect(_publishedBlock(tester), isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('crossing the 960 boundary with an open drawer cannot leak blocking',
      (tester) async {
    await _showWorkspace(tester, size: const Size(959, 812));
    await tester.tap(find.byTooltip('打开导航与历史'));
    await tester.pumpAndSettle();
    expect(_publishedBlock(tester), isTrue);
    expect(_blockedAtPrompt(tester), isTrue);

    // At the breakpoint the drawer leaves the tree; its flag must clear too.
    tester.view.physicalSize = const Size(960, 812);
    await tester.pumpAndSettle();
    expect(find.byType(Drawer), findsNothing);
    expect(_publishedBlock(tester), isFalse);
    expect(_blockedAtPrompt(tester), isFalse);

    // Resizing back to compact must be visually consistent: either the drawer
    // stays closed and input is unblocked, or the drawer is visible and input
    // is blocked. A visible drawer that reports unblocked is the phantom state
    // this test rejects.
    tester.view.physicalSize = const Size(959, 812);
    await tester.pumpAndSettle();
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold));
    final drawerVisible = find.byType(Drawer).evaluate().isNotEmpty;
    expect(
      _publishedBlock(tester),
      drawerVisible,
      reason: 'blocking must match whether the drawer covers the content',
    );
    expect(scaffold.isDrawerOpen, drawerVisible);
    expect(_blockedAtPrompt(tester), drawerVisible);
    if (drawerVisible) {
      scaffold.closeDrawer();
      await tester.pumpAndSettle();
      expect(find.byType(Drawer), findsNothing);
      expect(_publishedBlock(tester), isFalse);
      expect(_blockedAtPrompt(tester), isFalse);
    }
    expect(tester.takeException(), isNull);
  });
}
