import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/pages/feedback_page.dart';
import 'package:techpie/services/feedback_service.dart';
import 'package:techpie/services/usage_telemetry.dart';

class _Recorder extends Fake implements UsageTelemetry {
  final form = _FormVisit();
  @override
  void featureOpened(String feature) => form.events.add(feature);
  @override
  UsageVisit beginFeedback() {
    form.events.add('open');
    return form;
  }
}

class _FormVisit extends Fake implements UsageVisit {
  final events = <String>[];
  @override
  void feedbackAttempt() => events.add('attempt');
  @override
  void feedbackResult(bool delivered) => events.add(delivered ? 'success' : 'failure');
}

class _FeedbackService extends Fake implements FeedbackService {
  Exception? error;
  final messages = <String>[];

  @override
  Future<void> submit(
    String message, {
    bool includeUsername = false,
    bool includeEmail = false,
    String contact = '',
    List<FeedbackImage> images = const [],
    VoidCallback? onImageChanged,
  }) async {
    messages.add(message);
    if (error case final failure?) throw failure;
  }
}

void main() {
  for (final outcome in ['success', 'failure', 'timeout']) {
    testWidgets('group invitation after $outcome', (tester) async {
      final service = _FeedbackService()
        ..error = switch (outcome) {
          'failure' => Exception('服务暂不可用'),
          'timeout' => TimeoutException('request timed out'),
          _ => null,
        };
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') copied = call.arguments['text'] as String;
          return null;
        },
      );
      final recorder = _Recorder();
      await tester
          .pumpWidget(MaterialApp(home: FeedbackPage(service: service, telemetry: recorder)));
      await tester.enterText(find.byType(TextField).first, '同步课表时遇到了问题');
      Future<void> submit() async {
        final button = find.text('提交反馈');
        await tester.drag(find.byType(ListView), const Offset(0, -600));
        await tester.pumpAndSettle();
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await submit();
      final dialog = find.byType(AlertDialog);
      final title = switch (outcome) {
        'success' => '反馈已提交',
        'failure' => '提交失败',
        _ => '未能确认送达',
      };
      expect(find.descendant(of: dialog, matching: find.text(title)), findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.textContaining('1130168501')),
        findsOneWidget,
      );
      if (outcome != 'success') {
        expect(find.textContaining('直接反馈'), findsOneWidget);
      }
      await tester.tap(find.text(outcome == 'timeout' ? '关闭' : '复制群号'));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      expect(copied, outcome == 'timeout' ? isNull : '1130168501');
      if (outcome == 'success') {
        expect(find.text('反馈已发送'), findsOneWidget);
      } else {
        expect(find.text('同步课表时遇到了问题'), findsOneWidget);
        service.error = null;
        await submit();
        expect(find.text('反馈已提交'), findsOneWidget);
        expect(service.messages, ['同步课表时遇到了问题', '同步课表时遇到了问题']);
      }
      expect(recorder.form.events, [
        'feedback',
        'open',
        'attempt',
        if (outcome == 'failure') 'failure',
        if (outcome != 'success') 'attempt',
        'success',
      ]);
    });
  }
}
