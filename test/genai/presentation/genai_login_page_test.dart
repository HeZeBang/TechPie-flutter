import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/genai/data/demo_genai_backend.dart';
import 'package:techpie/features/genai/domain/genai_session.dart';
import 'package:techpie/features/genai/presentation/genai_login_page.dart';

import '../support/fakes.dart';

void main() {
  testWidgets(
      'token import stays obscured, rejects foreign URLs, and returns only a valid credential',
      (tester) async {
    final demo = await GenAiDemo.create(connected: false);
    addTearDown(demo.dispose);
    GenAiCredential? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<GenAiCredential>(
                  MaterialPageRoute(
                    builder: (_) => GenAiLoginPage(
                      sessions: demo.sessions,
                      openPortal: (_) async => true,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('genai-token'));
    final field = tester.widget<TextField>(input);
    expect(field.obscureText, isTrue);
    expect(field.enableSuggestions, isFalse);
    await tester.enterText(input, 'https://evil.example/?token=synthetic');
    await tester.tap(find.text('验证并连接'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(find.textContaining('请输入有效的 GenAI'), findsOneWidget);
    await tester.enterText(
      input,
      'https://genai.shanghaitech.edu.cn/?token=synthetic.jwt',
    );
    await tester.tap(find.text('验证并连接'));
    await tester.pumpAndSettle();
    expect(result?.token, 'synthetic.jwt');
    expect(
      demo.sessions.session,
      isNull,
    ); // Server verification is the next explicit step.
  });

  testWidgets(
      'account change dismisses an open login without returning a token',
      (tester) async {
    final demo = await GenAiDemo.create(connected: false);
    addTearDown(demo.dispose);
    GenAiCredential? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<GenAiCredential>(
                  MaterialPageRoute(
                    builder: (_) => GenAiLoginPage(
                      sessions: demo.sessions,
                      openPortal: (_) async => true,
                    ),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('genai-token')),
      'private-token',
    );
    await demo.sessions.setOwner(ownerB);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('genai-token')), findsNothing);
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
