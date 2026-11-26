import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/pages/campus_services_page.dart';
import 'package:techpie/services/storage_service.dart';

Future<StorageService> openHub(WidgetTester tester, {double width = 390, bool dark = false}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: CampusServicesPage(storage: storage),
    ),
  );
  await tester.pumpAndSettle();
  return storage;
}

void main() {
  test('resolves retired IDs, duplicates and hero entries while preserving pin order', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    expect(storage.pinnedQuickFeatureIds, isNull);
    expect(
      homeQuickFeatures(null).map((f) => f.id),
      ['elrc_recordings', 'ecourse', 'student_leave', 'oa_gym', 'egate_xshd'],
    );
    expect(
      homeQuickFeatures(['retired', 'student_allowance', 'student_allowance', 'campus_card'])
          .map((f) => f.id),
      ['student_allowance', 'elrc_recordings', 'ecourse', 'student_leave', 'oa_gym'],
    );
    // Use an existing user's saved order across catalog additions.
    await storage.setPinnedQuickFeatureIds([
      'campus_card', 'oa_gym', 'oa_gym', 'elrc_recordings',
      'ecourse', 'student_leave', 'egate_xshd', 'student_allowance',
    ]);
    expect(
      storage.pinnedQuickFeatureIds,
      ['oa_gym', 'elrc_recordings', 'ecourse', 'student_leave', 'egate_xshd'],
    );
  });

  for (final width in [320.0, 1120.0]) {
    for (final dark in [false, true]) {
      testWidgets('groups and filters services at ${width}dp, dark=$dark', (tester) async {
        await openHub(tester, width: width, dark: dark);
        final first = tester.getTopLeft(find.text('课程录播'));
        final second = tester.getTopLeft(find.text('E云课堂'));
        if (width == 320) {
          expect(second.dy, greaterThan(first.dy));
        } else {
          expect(second.dy, first.dy);
          expect(second.dx, greaterThan(first.dx));
        }
        final search = find.byType(TextField);
        for (final query in ['预约', 'GYM', 'changguan']) {
          await tester.enterText(search, query);
          await tester.pumpAndSettle();
          expect(find.text('场馆预约'), findsOneWidget);
          expect(find.text('课程录播'), findsNothing);
        }
        await tester.enterText(search, 'xxx');
        await tester.pumpAndSettle();
        expect(find.text('没有找到相关服务'), findsOneWidget);
        await tester.tap(find.text('清除搜索'));
        await tester.pumpAndSettle();
        expect(find.text('课程录播'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('save, reorder, reopen and cancel quick shortcuts', (tester) async {
    final storage = await openHub(tester);
    Future<void> edit() async {
      await tester.tap(find.byTooltip('编辑首页快捷'));
      await tester.pumpAndSettle();
    }

    Finder checkbox(String title) => find.widgetWithText(CheckboxListTile, title);
    Future<void> toggle(String title) async {
      final tile = checkbox(title);
      await tester.ensureVisible(tile);
      await tester.tap(tile);
      await tester.pumpAndSettle();
    }

    await edit();
    expect(find.text('已选 5/5'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(checkbox('学生津贴')).onChanged, isNull);
    expect(checkbox('校园卡'), findsNothing);
    await toggle('学生请假');
    await toggle('学生津贴');
    final up = find.descendant(
      of: find.byKey(const ValueKey('pin-student_allowance')),
      matching: find.byTooltip('上移'),
    );
    await tester.ensureVisible(up);
    await tester.tap(up);
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    const expected = ['elrc_recordings', 'ecourse', 'oa_gym', 'student_allowance', 'egate_xshd'];
    expect(storage.pinnedQuickFeatureIds, expected);
    await edit();
    await toggle('学生津贴');
    await tester.tap(find.byTooltip('取消'));
    await tester.pumpAndSettle();
    expect(storage.pinnedQuickFeatureIds, expected);
    await edit();
    expect(tester.widget<CheckboxListTile>(checkbox('学生津贴')).value, isTrue);
    expect(tester.takeException(), isNull);
  });
}
