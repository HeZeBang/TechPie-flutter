import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/widgets/feedback_entry.dart';

void main() {
  testWidgets('successful launch preserves feedback entry without a dialog',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackEntry(
            launcher: (url) async {
              opened = url;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('用户反馈与工单'));
    await tester.pumpAndSettle();
    expect(opened.toString(), 'https://techpie-feedback.dzhes.app');
    expect(find.text('无法打开反馈页面'), findsNothing);
  });

  for (final throws in [false, true]) {
    testWidgets('launch ${throws ? 'exception' : 'false'} offers copyable link',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: FeedbackEntry(
              launcher: (_) async {
                if (throws) throw PlatformException(code: 'unavailable');
                return false;
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('用户反馈与工单'));
      await tester.pumpAndSettle();
      expect(find.text('无法打开反馈页面'), findsOneWidget);
      await tester.tap(find.text('复制链接'));
      await tester.pumpAndSettle();
      expect(copied, 'https://techpie-feedback.dzhes.app');
    });
  }

  testWidgets('late launch failure after navigation does not display a dialog',
      (tester) async {
    final pending = Completer<bool>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FeedbackEntry(
            launcher: (_) => pending.future,
          ),
        ),
      ),
    );
    await tester.tap(find.text('用户反馈与工单'));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    pending.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('无法打开反馈页面'), findsNothing);
  });
}
