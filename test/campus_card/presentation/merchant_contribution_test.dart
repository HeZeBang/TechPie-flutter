import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/data/storage/merchant_contribution_preferences.dart';
import 'package:techpie/features/campus_card/domain/models/merchant_contribution_models.dart';
import 'package:techpie/features/campus_card/presentation/screens/merchant_contribution_screen.dart';

void main() {
  for (final width in [320.0, 390.0, 1280.0]) {
    testWidgets('contribution preview fits width $width with a local photo',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Uri? opened;
      final photo = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            merchantPhotoPickerProvider
                .overrideWithValue(() async => Uint8List.fromList(photo)),
            merchantIssueLauncherProvider.overrideWithValue((uri) async {
              opened = uri;
              return true;
            }),
          ],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const MerchantContributionScreen(
              merchantId: 'SYNTHETIC-MERCHANT',
              posCode: '0238',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextFormField).at(0),
        List.filled(30, '区域').join(),
      );
      await tester.enterText(
        find.byType(TextFormField).at(2),
        List.filled(30, '店铺').join(),
      );
      final scrollable = find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('选择招牌照片（可选）'),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('选择招牌照片（可选）'));
      await tester.pumpAndSettle();
      expect(find.byType(Image), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('预览资料'),
        200,
        scrollable: scrollable,
      );
      await tester.tap(find.text('预览资料'));
      await tester.pumpAndSettle();
      expect(opened, isNull);
      await tester.scrollUntilVisible(
        find.text('确认并前往 GitHub'),
        200,
        scrollable: scrollable,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('确认并前往 GitHub'));
      await tester.pumpAndSettle();
      expect(opened, isNotNull);
      expect(opened!.queryParameters['body'], isNot(contains('iVBOR')));
    });
  }

  test('generated issue contains only explicitly selected merchant fields', () {
    const contribution = MerchantContribution(
      merchantId: 'SYNTHETIC-MERCHANT',
      posCode: '0238',
      cafeteria: 'Synthetic area & garden',
      floor: '2',
      stall: 'Synthetic stall',
      correction: true,
    );
    final uri = contribution.issueUri;
    expect(uri.host, 'github.com');
    expect(uri.path, '/HeZeBang/TechPie-flutter/issues/new');
    expect(uri.queryParameters['body'], contribution.issueBody);
    expect(uri.queryParameters['body'], contains('0238'));
    expect(
      contribution.fields.keys.toSet(),
      {'merchantId', 'posCode', 'cafeteria', 'floor', 'stall'},
    );
    for (final field in [
      'amount',
      'balance',
      'occurredAt',
      'journo',
      'account',
      'openid',
      'qrcode',
      'photo',
    ]) {
      expect(contribution.fields, isNot(contains(field)));
      expect(contribution.issueBody, isNot(contains('"$field"')));
    }
    expect(contribution.issueBody, contains('待维护者核实'));
  });

  test(
      'dismissal survives a new preference instance and is per composite identity',
      () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = MerchantContributionPreferences();
    expect(await preferences.hasSeen('A/0238'), isFalse);
    await preferences.markSeen('A/0238');
    expect(await MerchantContributionPreferences().hasSeen('A/0238'), isTrue);
    expect(await preferences.hasSeen('B/0238'), isFalse);
  });

  testWidgets(
      'requires a preview and explicit confirmation before opening GitHub',
      (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantIssueLauncherProvider.overrideWithValue((uri) async {
            opened = uri;
            return true;
          }),
        ],
        child: const MaterialApp(
          home: MerchantContributionScreen(
            merchantId: 'SYNTHETIC-MERCHANT',
            posCode: '0238',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'Synthetic cafeteria',
    );
    await tester.enterText(find.byType(TextFormField).at(1), '2');
    await tester.enterText(find.byType(TextFormField).at(2), 'Synthetic stall');
    await tester.scrollUntilVisible(
      find.text('预览资料'),
      200,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.tap(find.text('预览资料'));
    await tester.pumpAndSettle();
    expect(opened, isNull);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Synthetic cafeteria'), findsOneWidget);
    expect(find.text('Synthetic stall'), findsOneWidget);
    await tester.ensureVisible(find.text('确认并前往 GitHub'));
    await tester.tap(find.text('确认并前往 GitHub'));
    await tester.pumpAndSettle();
    expect(opened?.queryParameters['body'], contains('Synthetic cafeteria'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('launch failure preserves preview and allows retry',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          merchantIssueLauncherProvider.overrideWithValue((_) async => false),
        ],
        child: const MaterialApp(
          home: MerchantContributionScreen(merchantId: 'SYNTHETIC'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(
      find.byType(TextFormField).first,
      'Synthetic cafeteria',
    );
    await tester.ensureVisible(find.text('预览资料'));
    await tester.tap(find.text('预览资料'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('确认并前往 GitHub'));
    await tester.tap(find.text('确认并前往 GitHub'));
    await tester.pumpAndSettle();
    expect(find.text('无法打开 GitHub，请稍后重试。'), findsOneWidget);
    expect(find.text('Synthetic cafeteria'), findsOneWidget);
  });
}
