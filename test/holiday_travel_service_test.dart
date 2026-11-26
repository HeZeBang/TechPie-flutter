import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/holiday_travel.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/holiday_travel_service.dart';
import 'package:techpie/services/storage_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reads history display names; reuses only destination and emergency contact from form',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      final model = r.uri.pathSegments.last.split('.').first;
      if (model == 'xsbgdjbd') {
        expect((r.data as Map)['WID'], 'old');
        expect((r.data as Map)['DJWID'], 'old-registration');
      }
      final records = [
        {
          'WID': 'old',
          'DJWID': 'old-registration',
          'JJRDM': '01',
          'JJRDM_DISPLAY': '暑假',
          'QRZT_DISPLAY': '已确认',
          'YL5': 'p',
          'YL6': 'c',
          'YL7': 'd',
          'YL4': 'street',
          'JJLXRDH': 'fixture-phone',
          'PRIVATE': 'private',
        }
      ];
      return respond({
        'code': 0,
        'datas': {
          model: {'totalSize': model == 'xsbgdjbd' ? -1 : 1, 'rows': records},
        },
      });
    });
    final s = HolidayTravelService(EmapClient(fixture.session), storage, account);
    await s.refresh();
    expect(s.history.single.holiday, '暑假');
    expect(s.history.single.status, '已确认');
    expect(storage.readEmapCache('holiday_travel'), isNot(contains('fixture-phone')));
    expect(storage.readEmapCache('holiday_travel'), isNot(contains('private')));
    expect((await s.loadDestination(s.history.single, s.revision)).destinationDefaults(), {
      'QXSF': 'p',
      'QXCS': 'c',
      'QXQX': 'd',
      'QXDZ': 'street',
      'JJLXRDH': 'fixture-phone',
    });
    fixture.identity = (user: 'other', ids: 'other');
    account.value++;
    expect(s.history, isEmpty);
    expect(storage.readEmapCache('holiday_travel'), isNull);
    s.dispose();
  });

  test('a shared batch never identifies the emergency contact or address', () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      expect(r.uri.pathSegments.last, 'xsbgdjbd.do');
      final rows = [
        {'DJWID': 'shared', 'JJLXRDH': 'batch-phone', 'QXDZ': 'batch-address'},
        {'WID': 'other', 'DJWID': 'shared', 'JJLXRDH': 'other-phone'},
        {'WID': 'mine', 'DJWID': 'other-batch', 'JJLXRDH': 'conflicting-phone'},
      ];
      return respond({
        'code': 0,
        'datas': {
          'xsbgdjbd': {'rows': rows},
        },
      });
    });
    final service = HolidayTravelService(EmapClient(fixture.session), storage, account);
    final batchOnly = HolidayTravel({'DJWID': 'shared', 'YL4': 'my-address'});
    expect(await service.loadDestination(batchOnly, service.revision), same(batchOnly));
    expect(fixture.requests, isEmpty);
    final withId = HolidayTravel({'WID': 'mine', ...batchOnly.fields});
    final result = await service.loadDestination(withId, service.revision);
    expect(result, same(withId));
    expect(result.destinationDefaults()['QXDZ'], 'my-address');
    expect(result['JJLXRDH'], isEmpty);
    service.dispose();
    account.dispose();
  });

  test('compares departure and return by calendar day', () {
    final start = DateTime(2026, 11, 25, 22);
    expect(HolidayTravel.validDates(start, DateTime(2026, 11, 25)), isTrue);
    expect(HolidayTravel.validDates(start, DateTime(2026, 11, 24)), isFalse);
  });

  test('submits departure and return registrations once, validates dates and rejects code=-1',
      () async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    Map<String, dynamic> saveResponse = {'code': '0', 'msg': 'ok'};
    Map<String, dynamic> returnResponse = {'code': '0', 'msg': 'ok'};
    final savedPayloads = <Map<String, dynamic>>[];
    final returnPayloads = <List<dynamic>>[];
    final logs = <String>[];
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (r) {
      if (r.uri.path.contains('getAppConfig')) return respond({});
      final last = r.uri.pathSegments.last;
      final form = r.data as Map;
      if (last == 'SaveRegister.do') {
        savedPayloads.add(jsonDecode(form['data'] as String) as Map<String, dynamic>);
        return respond(saveResponse);
      }
      if (last == 'T_JJR_FXDJ_SAVE.do') {
        returnPayloads.add(jsonDecode(form['T_JJR_FXDJ_SAVE'] as String) as List<dynamic>);
        return respond(returnResponse);
      }
      throw StateError('Unexpected $last');
    });
    final service = HolidayTravelService(EmapClient(fixture.session), storage, account);

    await runZoned(
      () async {
        await expectLater(
          service.submitDeparture(
            holidayCode: '02',
            departure: DateTime(2026, 10, 8),
            expectedReturn: DateTime(2026, 10, 7),
            province: '上海市',
            city: '上海市',
            district: '浦东新区',
            address: '示例路1号',
            emergencyPhone: 'secret-emergency-phone',
            expectedRevision: service.revision,
          ),
          throwsFormatException,
        );
        expect(fixture.requests, isEmpty);

        await service.submitDeparture(
          holidayCode: '02',
          departure: DateTime(2026, 10, 1),
          expectedReturn: DateTime(2026, 10, 7),
          province: '上海市',
          city: '上海市',
          district: '浦东新区',
          address: '示例路1号',
          emergencyPhone: 'secret-emergency-phone',
          abroad: false,
          expectedRevision: service.revision,
        );
        expect(savedPayloads.single, {
          'JJRDM': '02',
          'LXRQ': '2026-10-01',
          'YJFXRQ': '2026-10-07',
          'QXSF': '上海市',
          'QXCS': '上海市',
          'QXQX': '浦东新区',
          'QXDZ': '示例路1号',
          'YL5': '上海市',
          'YL6': '上海市',
          'YL7': '浦东新区',
          'YL4': '示例路1号',
          'YL8': '0',
          'JJLXRDH': 'secret-emergency-phone',
        });

        saveResponse = {'code': '-1', 'msg': 'false'};
        await expectLater(
          service.submitDeparture(
            holidayCode: '02',
            departure: DateTime(2026, 10, 1),
            expectedReturn: DateTime(2026, 10, 7),
            province: '上海市',
            city: '上海市',
            district: '浦东新区',
            address: '示例路1号',
            emergencyPhone: 'secret-emergency-phone',
            expectedRevision: service.revision,
          ),
          fails(CampusErrorKind.rejected),
        );

        await service.submitReturn(
          recordId: 'wid-1',
          returnDate: DateTime(2026, 10, 7),
          expectedRevision: service.revision,
        );
        expect(returnPayloads.single, [
          {'WID': 'wid-1', 'FXRQ': '2026-10-07'},
        ]);
      },
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)),
    );

    expect(storage.readEmapCache('holiday_travel'), isNot(contains('secret-emergency-phone')));
    expect(logs.join(), isNot(contains('secret-emergency-phone')));
    service.dispose();
    account.dispose();
  });
}
