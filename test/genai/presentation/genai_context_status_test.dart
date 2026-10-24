import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/domain/genai_context_usage.dart';
import 'package:techpie/features/genai/presentation/genai_context_status.dart';

void main() {
  testWidgets('preparation states fit narrow layouts and explain estimates', (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final stage in GenAiContextStage.values) {
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.6),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: GenAiContextStatus(
              usage: GenAiContextUsage(
                stage: stage,
                estimatedInputUnits: 40000,
                allowedInputUnits: 100000,
                originalInputUnits: 110000,
                completedChunks: 2,
                totalChunks: 3,
                compacted: stage == GenAiContextStage.ready,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      if (stage == GenAiContextStage.compacting) {
        expect(find.byTooltip('正在整理上下文 · 2/3'), findsOneWidget);
      }
    }
    expect(find.byTooltip('已整理上下文 · 估算 40%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('genai-context-status')));
    await tester.pumpAndSettle();
    expect(find.textContaining('不是实际 Token 用量或计费额度'), findsOneWidget);
    expect(find.textContaining('整理前约为 110%'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
