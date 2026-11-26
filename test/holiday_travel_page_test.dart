import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/holiday_travel_page.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/holiday_travel_service.dart';
import 'package:techpie/services/storage_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  testWidgets(
      'reuses the dated registration, ignores unrelated forms and clears an open draft on account switch',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
      if (request.uri.path.contains('getAppConfig')) return respond({});
      final model = request.uri.pathSegments.last.split('.').first;
      final records = switch (model) {
        'xsdjlsjlbg' => [
            {'WID': 'old', 'DJRQ': '2025-02-01', 'YL4': '旧去向'},
            {
              'WID': 'recent',
              'DJWID': 'session',
              'DJRQ': '2026-02-01',
              'YL4': '新去向',
              'LXRQ': '2026-02-03',
            },
          ],
        'xsbgdjbd' => [
            {'WID': 'old', 'DJWID': 'session', 'JJLXRDH': 'other-phone'},
            {'WID': 'recent', 'DJWID': 'session', 'JJLXRDH': 'selected-phone'},
          ],
        _ => throw StateError(model),
      };
      return respond({
        'code': 0,
        'datas': {
          model: {'rows': records, 'totalSize': records.length},
        },
      });
    });
    final service = HolidayTravelService(EmapClient(fixture.session), storage, account);
    await tester.pumpWidget(MaterialApp(home: HolidayTravelPage(service: service)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复用上次登记去向'));
    await tester.pumpAndSettle();
    final summaryField = find.byKey(const ValueKey('holiday-summary'));
    final draft = tester.widget<TextField>(summaryField).controller!.text;
    expect(draft, contains('selected-phone'));
    expect(draft, contains('新去向'));
    expect(draft, isNot(contains('other-phone')));
    expect(draft, isNot(contains('2026-02-03')));
    expect(find.text('添加本次离返校日期'), findsOneWidget);
    expect(storage.readEmapCache('holiday_travel'), isNot(contains('selected-phone')));
    String? copied;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await tester.enterText(summaryField, '本次核对的去向');
    await tester.ensureVisible(find.text('复制摘要'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('复制摘要'));
    await tester.pump();
    expect(copied, '本次核对的去向');
    await tester.ensureVisible(find.text('历史记录'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('历史记录'));
    await tester.pumpAndSettle();
    expect(find.text('复用此记录的去向'), findsNWidgets(2));
    expect(find.text('确认返校'), findsNWidgets(2));
    fixture.identity = (user: null, ids: null);
    account.value++;
    await tester.pumpAndSettle();
    expect(find.text('登录 TechPie'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    account.dispose();
  });

  testWidgets('confirmation dialog preserves draft on cancel and submits SaveRegister once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final submissions = <Map<String, dynamic>>[];
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
      if (request.uri.path.contains('getAppConfig')) return respond({});
      final last = request.uri.pathSegments.last;
      if (last == 'xsdjlsjlbg.do') {
        return respond({
          'code': 0,
          'datas': {
            'xsdjlsjlbg': {
              'rows': [
                {
                  'WID': 'recent',
                  'DJWID': 'session',
                  'DJRQ': '2026-02-01',
                  'YL5': '310000',
                  'YL5_DISPLAY': '上海市',
                  'YL4': '张江路99号',
                },
              ],
              'totalSize': 1,
            },
          },
        });
      }
      if (last == 'xsbgdjbd.do') {
        return respond({
          'code': 0,
          'datas': {
            'xsbgdjbd': {
              'rows': [
                {
                  'WID': 'recent',
                  'DJWID': 'session',
                  'QXSF': '310000',
                  'QXSF_DISPLAY': '上海市',
                  'QXDZ': '张江路99号',
                  'JJLXRDH': '13800138000',
                },
              ],
              'totalSize': 1,
            },
          },
        });
      }
      if (last == 'SaveRegister.do') {
        final raw = (request.data as Map)['data'] as String;
        submissions.add(jsonDecode(raw) as Map<String, dynamic>);
        return respond({'code': '0', 'msg': 'true'});
      }
      throw StateError('Unexpected $last');
    });
    final service = HolidayTravelService(EmapClient(fixture.session), storage, account);
    await tester.pumpWidget(MaterialApp(home: HolidayTravelPage(service: service)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('复用上次登记去向'));
    await tester.pumpAndSettle();

    // Pick date range using the Flutter date range picker dialog.
    await tester.tap(find.text('添加本次离返校日期'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10').first);
    await tester.tap(find.text('12').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save').first);
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('提交离校登记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交离校登记'));
    await tester.pumpAndSettle();
    expect(find.text('确认提交离校登记？'), findsOneWidget);
    expect(submissions, isEmpty);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(submissions, isEmpty);
    expect(
      tester.widget<TextField>(find.byKey(const ValueKey('holiday-address'))).controller!.text,
      '张江路99号',
    );

    await tester.ensureVisible(find.text('提交离校登记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('提交离校登记'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();

    expect(submissions, hasLength(1));
    expect(submissions.single['QXSF'], '310000');
    expect(submissions.single['QXDZ'], '张江路99号');
    expect(submissions.single['JJLXRDH'], '13800138000');
    expect(storage.readEmapCache('holiday_travel'), isNot(contains('13800138000')));
    expect(find.text('确认返校'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    service.dispose();
    account.dispose();
  });
}
