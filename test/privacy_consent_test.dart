import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/widgets/privacy_consent.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the consent is unset until it is accepted, and it sticks', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    expect(storage.privacyAccepted, isFalse);

    await storage.setPrivacyAccepted(true);
    expect(storage.privacyAccepted, isTrue);

    // A second instance reads the same store, which is what a relaunch does.
    final reopened = StorageService(await SharedPreferences.getInstance());
    expect(reopened.privacyAccepted, isTrue);
  });

  testWidgets('the consent page reports both answers', (tester) async {
    var accepted = 0;
    var declined = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyConsentPage(
          onAccept: () async => accepted++,
          onDecline: () => declined++,
        ),
      ),
    );

    expect(find.text('隐私政策'), findsOneWidget);
    expect(find.textContaining('查看《隐私政策》'), findsOneWidget);

    await tester.tap(find.text('同意并继续'));
    await tester.pumpAndSettle();
    expect(accepted, 1);
    expect(declined, 0);

    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(declined, 1);
  });

  testWidgets('declining without a handler explains the consequence', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: PrivacyConsentPage(onAccept: () async {}),
      ),
    );

    await tester.tap(find.text('不同意'));
    await tester.pumpAndSettle();
    expect(find.text('需要你的同意'), findsOneWidget);
  });

  testWidgets('the sign-in notice points at the policy', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PrivacyNotice())),
    );
    expect(find.text('登录即表示你已阅读并同意'), findsOneWidget);
    expect(find.text('《隐私政策》'), findsOneWidget);
  });
}
