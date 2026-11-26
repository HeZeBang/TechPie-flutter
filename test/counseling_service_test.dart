import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/counseling_reservation.dart';
import 'package:techpie/pages/counseling_page.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/counseling_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('owner, dates and appointment data stay in the current visit', () async {
    final writes = <MethodCall>[];
    const storage = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storage, (call) async {
      writes.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(storage, null));
    final logs = <String>[];
    await runZoned(
      () async {
        final f = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
          final model = request.uri.pathSegments.last.split('.').first;
          if (!request.uri.path.contains('/modules/')) return respond({});
          final form = request.data as Map;
          final row = switch (model) {
            'wdyyxx' => {
                'YYRQ': '2026-12-01',
                'XM': 'private-counselor',
                'LXDH': 'private-contact',
              },
            'getResDate' => {'YYRQ': '2026-12-01'},
            'zxsbd' => {
                'XM': 'private-counselor',
                'ZGH': 'A',
                'SDDM': '1',
                'ZXSJ': '2026-12-01 08:00',
                'YYZT': '0',
              },
            _ => throw StateError('unexpected fixture action'),
          };
          if (model == 'wdyyxx') expect(form['userid'], '20240000');
          if (model == 'zxsbd') expect(form['YYRQ'], '2026-12-01');
          return respond({
            'code': 0,
            'datas': {
              model: {
                'rows': [row],
                'totalSize': 1,
              },
            },
          });
        });
        final service = CounselingService(EmapClient(f.session), '20240000');
        expect((await service.myReservations()).single.contact, 'private-contact');
        final date = (await service.dates()).single;
        final slot = (await service.slots(date)).single;
        expect(slot.name, 'private-counselor');
        expect(slot.availabilityLabel, isEmpty);
        expect(slot.displayStatus, '可预约');
        expect(slot.isBookable, isTrue);
        await expectLater(service.slots('2026-02-30'), throwsFormatException);
        service.dispose();
        expect(service.reservations, isEmpty);
        await expectLater(service.myReservations(), throwsException);
        final other = CounselingService(EmapClient(f.session), '20240000');
        f.identity = (user: 'next', ids: 'next');
        await expectLater(other.myReservations(), throwsException);
      },
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)),
    );
    expect(writes, isEmpty);
    expect(logs.join(), isNot(matches('private-|13912345678')));
  });

  test('a delayed response after exit cannot restore appointment records', () async {
    final started = Completer<void>();
    final release = Completer<void>();
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) async {
      if (!r.uri.path.endsWith('/wdyyxx.do')) return respond({});
      started.complete();
      await release.future;
      return respond({
        'code': 0,
        'datas': {
          'wdyyxx': {
            'rows': [
              {'XM': 'old-user'},
            ],
            'totalSize': 1,
          },
        },
      });
    });
    final service = CounselingService(EmapClient(f.session), '20240000');
    final request = service.myReservations();
    await started.future;
    service.dispose();
    release.complete();
    await expectLater(request, fails(CampusErrorKind.sessionExpired));
    expect(service.reservations, isEmpty);
  });

  test('supports alternate getResDate response shapes', () async {
    var mode = 0;
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (!r.uri.path.contains('/modules/')) return respond({});
      return respond(
        mode == 0
            ? {
                'code': '0',
                'data': ['2026-12-06', 'invalid-date'],
              }
            : {
                'datas': [
                  {'YYRQ': '2026-12-07'},
                  {'YYRQ': '2026-12-07'},
                ],
              },
      );
    });
    final service = CounselingService(EmapClient(f.session), '20240000');
    expect(await service.dates(), ['2026-12-06']);
    mode = 1;
    expect(await service.dates(), ['2026-12-07']);
    service.dispose();
  });

  test('validates 11-digit phone and bookable status before submitting once with zero storage/logs',
      () async {
    final writes = <MethodCall>[];
    const storage = MethodChannel('plugins.flutter.io/shared_preferences');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(storage, (call) async {
      writes.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(storage, null));

    final bookedPayloads = <Map<String, dynamic>>[];
    Map<String, dynamic> bookResponse = {'code': '0', 'returnCode': '#E000000000000'};
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (!r.uri.path.contains('/modules/')) return respond({});
      expect(r.uri.path, '/xsfw/sys/xljkapp/modules/mh_reservation_xs/T_XG_ZXYY_ZXYY_ADD.do');
      final raw = (r.data as Map)['T_XG_ZXYY_ZXYY_ADD'] as String;
      bookedPayloads.add(jsonDecode(raw) as Map<String, dynamic>);
      return respond(bookResponse);
    });
    final service = CounselingService(EmapClient(f.session), '20240000');
    final availableSlot = CounselingSlot.fromJson({
      'XM': '咨询师甲',
      'ZGH': 'C01',
      'SDDM': '2',
      'SDMC': '下午',
      'XQDM': '01',
      'ZXSJ': '2026-12-08 14:00',
      'ZXDD': '心理中心',
      'YYZT': '0',
    });
    final fullSlot = CounselingSlot.fromJson({
      'XM': '咨询师乙',
      'ZGH': 'C02',
      'YYZT': '1',
      'YYZT_DISPLAY': '已约满',
    });

    const phone = '13912345678';
    const note = 'private-session-topic';
    final logs = <String>[];
    await runZoned(
      () async {
        expect(CounselingService.validPhone('12345'), isFalse);
        expect(CounselingService.validPhone(phone), isTrue);

        await expectLater(
          service.bookSlot(date: '2026-12-08', slot: fullSlot, phone: phone),
          fails(CampusErrorKind.rejected),
        );
        await expectLater(
          service.bookSlot(date: '2026-12-08', slot: availableSlot, phone: '23912345678'),
          throwsFormatException,
        );
        expect(f.requests, isEmpty);

        await service.bookSlot(
          date: '2026-12-08',
          slot: availableSlot,
          phone: phone,
          note: note,
        );
        expect(bookedPayloads.single, {
          'XSBH': '20240000',
          'ZGH': 'C01',
          'YYRQ': '2026-12-08',
          'XQDM': '01',
          'SDDM': '2',
          'SDMC': '下午',
          'ZXSJ': '2026-12-08 14:00',
          'YYDD': '心理中心',
          'SJH': phone,
          'ZXWT': note,
        });

        bookResponse = {'code': '-1', 'success': false};
        await expectLater(
          service.bookSlot(date: '2026-12-08', slot: availableSlot, phone: phone),
          fails(CampusErrorKind.rejected),
        );
      },
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)),
    );

    expect(writes, isEmpty);
    expect(logs.join(), isNot(contains(phone)));
    expect(logs.join(), isNot(contains(note)));
    service.dispose();
  });

  testWidgets('personal bookings and dated schedules render only the selected pane and book slot',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 750));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final booked = <Map<String, dynamic>>[];
    final f = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (!r.uri.path.contains('/modules/')) return respond({});
      final model = r.uri.pathSegments.last.split('.').first;
      if (model == 'T_XG_ZXYY_ZXYY_ADD') {
        final raw = (r.data as Map)['T_XG_ZXYY_ZXYY_ADD'] as String;
        booked.add(jsonDecode(raw) as Map<String, dynamic>);
        return respond({'code': '0', 'returnCode': '#E000000000000'});
      }
      final rows = switch (model) {
        'wdyyxx' => [
            {'XSBH': '20240000', 'SDMC': '下午', 'YYRQ': '2026-12-01', 'YYDD': '测试地点'},
            {'XSBH': 'other', 'YYDD': '他人地点'},
          ],
        'getResDate' => [
            {'YYRQ': '2026-12-05'},
            {'YYRQ': '2026-02-30'},
          ],
        'zxsbd' => [
            {
              'ZGH': 'T01',
              'SDDM': '1',
              'SDMC': '上午',
              'XM': '排班老师',
              'ZXSJ': '2026-12-05 09:00',
              'YYZT': '0',
              'YYZT_DISPLAY': '可预约 校方排班状态',
            },
          ],
        _ => throw StateError('unexpected model'),
      };
      if (model == 'zxsbd') expect((r.data as Map)['YYRQ'], '2026-12-05');
      return respond({
        'code': 0,
        'datas': {
          model: {'rows': rows, 'totalSize': rows.length},
        },
      });
    });
    await tester.pumpWidget(
      MaterialApp(home: CounselingPanels(client: EmapClient(f.session), studentId: '20240000')),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('测试地点'), findsOneWidget);
    expect(find.textContaining('他人地点'), findsNothing);
    await tester.tap(find.text('日期排班'));
    await tester.pumpAndSettle();
    expect(find.textContaining('测试地点'), findsNothing);
    expect(find.text('2026-02-30'), findsNothing);
    await tester.tap(find.text('2026-12-05'));
    await tester.pumpAndSettle();
    expect(find.textContaining('校方排班状态'), findsOneWidget);
    expect(find.textContaining('排班老师'), findsOneWidget);
    expect(find.text('在校园网页中预约'), findsOneWidget);

    await tester.ensureVisible(find.text('预约'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('预约'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const ValueKey('counseling-phone')), '12345');
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(find.text('请输入 11 位中国大陆手机号'), findsOneWidget);
    expect(booked, isEmpty);

    await tester.enterText(find.byKey(const ValueKey('counseling-phone')), '13800138000');
    await tester.tap(find.text('提交预约'));
    await tester.pumpAndSettle();
    expect(find.text('确认提交心理咨询预约？'), findsOneWidget);
    expect(find.textContaining('138****8000'), findsOneWidget);
    expect(booked, isEmpty);

    await tester.tap(find.text('确认预约'));
    await tester.pumpAndSettle();
    expect(booked, hasLength(1));
    expect(booked.single['SJH'], '13800138000');
    expect(booked.single['ZGH'], 'T01');
    expect(find.textContaining('测试地点'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
