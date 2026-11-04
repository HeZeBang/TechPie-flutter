import 'dart:async';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/ids_passkey.dart';
import 'package:techpie/models/oa_gym.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';

import 'support/fake_ids_client.dart';
import 'support/oa_school_client.dart';

bool _isContact(http.Request request) => request.url.path.endsWith('/HrmResourceContactEdit.jsp');

void main() {
  test('shared courts use physical availability and never expose the unused court', () async {
    final fixture = await _serviceFixture();
    final school = OaSchoolClient();
    final service = _service(fixture, school);
    final progress = <int>[];
    final result = await service.checkAvailability(
      sports: {OaSport.tennis, OaSport.pickleball},
      date: '2026-10-08',
      startSlot: 8,
      endSlot: 9,
      onProgress: (rows) => progress.add(rows.length),
    );
    expect(progress, [2, 4]);
    expect(result.where((row) => row.sport == OaSport.tennis).first.availableCourts, [1, 2, 4]);
    expect(result.where((row) => row.sport == OaSport.pickleball).first.availableCourts, [1, 2]);
    expect(oaCourtForSport(OaSport.pickleball, 2).label, contains('网球场1号'));
    expect(school.requests.every((r) => r.url.host == 'oa.shanghaitech.edu.cn'), true);
  });

  test('booking shared courts submits the physical OA court without repeating a submission',
      () async {
    final fixture = await _serviceFixture();
    final school = OaSchoolClient();
    final service = _service(fixture, school);
    await service.bookCourt(
        sport: OaSport.tennis, date: '2026-10-08', timeSlot: 8, courtNumber: 4, playersCount: 2,);
    await service.bookCourt(
        sport: OaSport.pickleball,
        date: '2026-10-08',
        timeSlot: 8,
        courtNumber: 2,
        playersCount: 2,);
    final bookings =
        school.requests.where((r) => r.url.path.endsWith('/RequestOperation.jsp')).toList();
    expect(bookings.map((r) => Uri.splitQueryString(r.body)['field31883']), ['63_43', '63_25']);
    await expectLater(
        service.bookCourt(
            sport: OaSport.pickleball,
            date: '2026-10-08',
            timeSlot: 8,
            courtNumber: 3,
            playersCount: 2,),
        throwsA(isA<OaGymException>()),);
    expect(
        school.requests.where((r) => r.url.path.endsWith('/RequestOperation.jsp')), hasLength(2),);
  });

  test('metadata is single flight and reused until the session is cleared', () async {
    final fixture = await _serviceFixture();
    final started = Completer<void>();
    final release = Completer<void>();
    var browsers = 0;
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.endsWith('/CommonSingleBrowser.jsp') && ++browsers == 1) {
          started.complete();
          await release.future;
        }
        return null;
      };
    final service = _service(fixture, school);
    final first = service.ensureReady();
    final second = service.ensureReady();
    await started.future;
    expect(browsers, 1);
    release.complete();
    await Future.wait([first, second]);
    expect(browsers, 2);
    await service.ensureReady();
    expect(browsers, 2);
    service.clearSession();
    await service.ensureReady();
    expect(browsers, 4);
    expect(service.loading, false);
  });

  test('local search bounds concurrency and reports failures instead of empty results', () async {
    final fixture = await _serviceFixture();
    var active = 0;
    var peak = 0;
    var searches = 0;
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.endsWith('/SplitPageXmlServlet') &&
            Uri.splitQueryString(request.body)['tableString'] == 'BB') {
          return OaSchoolClient.text(
              '<rows>${List.generate(6, (i) => '<row><col>${13 + i}</col><col/><col showvalue="羽毛球场地${i + 1}号"/></row>').join()}</rows>',);
        }
        if (request.url.path.contains('/CustomSearch')) {
          final attempt = ++searches;
          active++;
          if (active > peak) peak = active;
          await Future<void>.delayed(const Duration(milliseconds: 1));
          active--;
          if (attempt == 3) return OaSchoolClient.text('failed', status: 503);
        }
        return null;
      };
    final service = _service(fixture, school);
    await expectLater(
        service.searchCourts(
            startDate: '2026-10-08',
            endDate: '2026-10-08',
            venueNames: {},
            timeRanges: ['18:00-19:00'],),
        throwsA(isA<OaGymException>()),);
    expect(peak, lessThanOrEqualTo(3));
    expect(searches, greaterThanOrEqualTo(3));
    expect(service.loading, false);
  });

  test('superseded availability stops queued hours without overlapping checks', () async {
    final fixture = await _serviceFixture();
    final started = Completer<void>();
    final release = Completer<void>();
    final slots = <int>[];
    var current = true;
    var active = 0;
    var peak = 0;
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.contains('/CustomTreeBrowser') &&
            Uri.splitQueryString(request.body)['pid'] == '63_1') {
          slots.add(int.parse(RegExp(r'_sfn_31902_sfv_(\d+)')
              .firstMatch(request.url.queryParameters['dataconditionParam']!)!
              .group(1)!,),);
          active++;
          if (active > peak) peak = active;
          if (slots.length == 1) {
            started.complete();
            await release.future;
          }
          active--;
        }
        return null;
      };
    final service = _service(fixture, school);
    final first = service.checkAvailability(
        sports: {OaSport.badminton},
        date: '2026-10-08',
        startSlot: 8,
        endSlot: 10,
        shouldContinue: () => current,);
    await started.future;
    current = false;
    final second = service.checkAvailability(
        sports: {OaSport.badminton}, date: '2026-10-09', startSlot: 9, endSlot: 9,);
    await Future<void>.delayed(Duration.zero);
    expect(slots, [8]);
    release.complete();
    final result = await Future.wait([first, second]);
    expect(slots, [8, 9]);
    expect(peak, 1);
    expect(result.first, hasLength(1));
    expect(result.last.single.date, '2026-10-09');
    expect(service.loading, false);
  });

  test('booking timeout tells the user to check records and never retries the POST', () async {
    final fixture = await _serviceFixture();
    var submits = 0;
    final school = OaSchoolClient()
      ..intercept = (request) async {
        if (request.url.path.endsWith('/RequestOperation.jsp')) {
          submits++;
          throw TimeoutException('synthetic timeout');
        }
        return null;
      };
    final service = _service(fixture, school);
    await expectLater(
        service.bookCourt(
            sport: OaSport.tennis,
            date: '2026-10-08',
            timeSlot: 8,
            courtNumber: 1,
            playersCount: 2,),
        throwsA(
            isA<OaGymException>().having((e) => e.message, 'message', contains('先查询预约记录确认结果')),),);
    expect(submits, 1);
  });

  group('OA personal information', () {
    test('automatically syncs Passkey contacts after binding', () async {
      final fixture = await _serviceFixture(bindIds: false);
      final school = OaSchoolClient();
      final started = Completer<void>();
      final release = Completer<void>();
      school.intercept = (request) async {
        if (request.url.path == '/hrm/resource/HrmResourceContactEdit.jsp') {
          started.complete();
          await release.future;
        }
        return null;
      };
      final service = _service(fixture, school);
      service.startProfileSync();
      await fixture.tpAuth.bindIds(
        account: '20240001',
        password: 'fixture-password',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      await started.future;
      final completed = service.syncBookingProfile();
      release.complete();
      await completed;
      expect(service.profileSynced, true);
      expect(service.profileSyncError, isNull);
      expect(service.bookingProfile().phone, '13900000000');
      expect(service.bookingProfile().email, 'student@shanghaitech.edu.cn');
      expect(
        school.requests.where((r) => r.url.path == '/hrm/resource/HrmResourceContactEdit.jsp'),
        hasLength(1),
      );
      expect(
        school.requests.every((r) => r.method == 'GET' && r.url.host == 'oa.shanghaitech.edu.cn'),
        true,
      );
    });

    test('Passkey gym reads and submits directly to OA while keeping saved contacts', () async {
      final fixture = await _serviceFixture(bindIds: false);
      final school = OaSchoolClient();
      final service = _service(fixture, school);
      await fixture.tpAuth.bindIds(
        account: '20240001',
        password: 'fixture-password',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      await service.saveBookingProfile(
        const OaBookingProfile(name: 'OA User', phone: '13900000000', email: ''),
      );
      await service.syncBookingProfile();
      expect(service.profileSyncError, isNull);
      expect(service.profileSynced, true);
      expect(service.bookingProfile().email, 'student@shanghaitech.edu.cn');
      expect(service.bookingStudentId, '20240001');
      expect(service.profileOwner, 'user|20240001');
      expect(fixture.tpAuth.idsNode.cookieProvider!.studentId, '20240001');
      expect(service.bookingProfile().phone, '13900000000');
      await service.ensureReady();
      expect(service.timeSlots, {'18:00-19:00': '8'});
      final available = await service.checkAvailability(
        sports: {OaSport.pickleball},
        date: '2026-11-03',
        startSlot: 8,
        endSlot: 8,
      );
      expect(available.single.availableCourts, [1, 2]);
      final records = await service.searchCourts(
        startDate: '2026-11-03',
        endDate: '2026-11-03',
        venueNames: {'室内羽毛球场'},
        timeRanges: ['18:00-19:00'],
      );
      expect(records.single.rows.single.last, '已通过');
      await service.bookCourt(
        sport: OaSport.badminton,
        date: '2026-10-08',
        timeSlot: 8,
        courtNumber: 1,
        playersCount: 2,
      );
      expect(
        school.requests.every((request) => request.url.host == 'oa.shanghaitech.edu.cn'),
        true,
      );
      final booking = Uri.splitQueryString(school.requests.last.body);
      expect(booking['field34283'], '20240001');
      expect(booking['field31879'], '13900000000');
    });

    test('Passkey OA expiry remints locally and retries without contacting the backend', () async {
      final fixture = await _serviceFixture(bindIds: false);
      await fixture.tpAuth.bindIds(
        account: '20240001',
        password: 'fixture-password',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      var expired = false;
      final school = OaSchoolClient()
        ..intercept = (_) async {
          if (expired) return null;
          expired = true;
          return OaSchoolClient.text('expired', status: 401);
        };
      final service = _service(fixture, school);
      final epoch = fixture.tpAuth.oaNode.epoch;
      await service.ensureReady();
      expect(service.sessionReady, true);
      expect(fixture.tpAuth.oaNode.epoch, epoch + 2);
      expect(school.requests, hasLength(5));
      expect(
        school.requests.every((request) => request.url.host == 'oa.shanghaitech.edu.cn'),
        true,
      );
    });

    test('Passkey repeated OA expiry stops after one retry', () async {
      final fixture = await _serviceFixture(bindIds: false);
      await fixture.tpAuth.bindIds(
        account: '20240001',
        password: 'fixture-password',
        promptCaptcha: (_, __, {required refresh}) async => null,
      );
      final school = OaSchoolClient()
        ..intercept = (_) async => OaSchoolClient.text('expired', status: 401);
      final service = _service(fixture, school);
      await expectLater(
        service.ensureReady(),
        throwsA(
          isA<OaGymException>().having((e) => e.message, 'message', contains('OA 登录态已失效')),
        ),
      );
      expect(school.requests, hasLength(2));
    });

    test('syncs on binding and rebinding without repeating on a session refresh', () async {
      final fixture = await _serviceFixture(bindIds: false);
      var contacts = 0;
      final school = OaSchoolClient()
        ..intercept = (request) async {
          if (_isContact(request)) return OaSchoolClient.contacts(phone: '1390000000${++contacts}');
          return null;
        };
      final service = _service(fixture, school)..startProfileSync();
      expect(contacts, 0);
      await _setAccount(fixture, '20240001', DateTime.utc(2026, 10, 8));
      await service.syncBookingProfile();
      expect(contacts, 1);
      await fixture.tpAuth.updateRaw(
          ThirdPartyPlatform.ids, {...fixture.tpAuth.idsAccount!.raw, 'cookies': 'CASTGC=renewed'},);
      await Future<void>.delayed(Duration.zero);
      expect(contacts, 1);
      await _setAccount(fixture, '20240001', DateTime.utc(2026, 10, 9));
      await service.syncBookingProfile();
      expect(contacts, 2);
      expect(service.bookingProfile().phone, '13900000002');
    });

    test('shares a pending profile request without marking court queries as loading', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      final started = Completer<void>();
      final response = Completer<http.Response>();
      final school = OaSchoolClient()
        ..intercept = (request) async {
          if (_isContact(request)) {
            started.complete();
            return response.future;
          }
          return null;
        };
      final service = _service(fixture, school);
      final first = service.syncBookingProfile();
      final second = service.syncBookingProfile();
      expect(identical(first, second), true);
      await started.future;
      expect(service.profileSyncing, true);
      expect(service.loading, false);
      response.complete(OaSchoolClient.contacts());
      await first;
      expect(service.profileSyncing, false);
    });

    test('contacts stay account-scoped and ignore the old unscoped record', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      await fixture.storage.saveOaBookingProfile(
          const OaBookingProfile(name: 'Old contact', phone: '13600000000', email: ''),);
      final service = _service(fixture, OaSchoolClient());
      expect(service.bookingProfile().phone, isEmpty);
      await service.syncBookingProfile();
      await service.saveBookingProfile(service.bookingProfile().copyWith(phone: '13800000000'));
      await _setAccount(fixture, '20240002', DateTime.utc(2026, 10, 8));
      expect(service.bookingProfile().phone, isEmpty);
      await service.syncBookingProfile();
      expect(service.bookingProfile().phone, '13900000000');
      await _setAccount(fixture, '20240001', DateTime.utc(2026, 10, 9));
      expect(service.bookingProfile().phone, '13800000000');
      expect(fixture.storage.loadOaBookingProfile().phone, '13600000000');
    });

    test('late contacts cannot overwrite a replacement account or stop its sync', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      final responses = <Completer<http.Response>>[];
      final school = OaSchoolClient()
        ..intercept = (request) async {
          if (!_isContact(request)) return null;
          final response = Completer<http.Response>();
          responses.add(response);
          return response.future;
        };
      final service = _service(fixture, school)..startProfileSync();
      final old = service.syncBookingProfile();
      await Future<void>.delayed(Duration.zero);
      await _setAccount(fixture, '20240002', DateTime.utc(2026, 10, 8));
      final current = service.syncBookingProfile();
      await Future<void>.delayed(Duration.zero);
      expect(responses, hasLength(2));
      responses.first.complete(OaSchoolClient.contacts());
      await old;
      expect(service.profileSyncing, true);
      expect(service.bookingProfile().phone, isEmpty);
      responses.last.complete(OaSchoolClient.contacts(phone: '13700000000'));
      await current;
      expect(service.bookingProfile().phone, '13700000000');
      expect(service.profileSyncError, isNull);
      expect(fixture.storage.loadOaBookingProfile(owner: 'user|20240001').phone, isEmpty);
    });

    test('OA updates preserve manual overrides unless overwrite was requested', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      var response = OaSchoolClient.contacts();
      final school = OaSchoolClient()
        ..intercept = (request) async => _isContact(request) ? response : null;
      final service = _service(fixture, school);
      await service.syncBookingProfile();
      await service.saveBookingProfile(service.bookingProfile().copyWith(phone: '13800000000'));
      response =
          OaSchoolClient.contacts(phone: '13700000000', email: 'updated@shanghaitech.edu.cn');
      await service.syncBookingProfile();
      expect(service.bookingProfile().name, 'User');
      expect(service.bookingProfile().email, 'updated@shanghaitech.edu.cn');
      expect(service.bookingProfile().phone, '13800000000');
      await service.syncBookingProfile(overwrite: true);
      expect(service.bookingProfile().phone, '13700000000');
    });

    test('a manual save made during a profile request wins over its late response', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      final response = Completer<http.Response>();
      final school = OaSchoolClient()
        ..intercept = (request) async => _isContact(request) ? response.future : null;
      final service = _service(fixture, school);
      final request = service.syncBookingProfile(overwrite: true);
      await service.saveBookingProfile(
          const OaBookingProfile(name: 'Manual', phone: '13800000000', email: ''),);
      response.complete(OaSchoolClient.contacts());
      await request;
      expect(service.bookingProfile().name, 'Manual');
      expect(service.bookingProfile().phone, '13800000000');
      expect(service.bookingProfile().email, isEmpty);
    });

    test('masked phone numbers and a different user contact form are rejected', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      var response = OaSchoolClient.contacts(phone: '1390000****');
      final school = OaSchoolClient()
        ..intercept = (request) async => _isContact(request) ? response : null;
      final service = _service(fixture, school);
      await service.syncBookingProfile();
      expect(service.bookingProfile().phone, isEmpty);
      expect(service.bookingProfile().email, 'student@shanghaitech.edu.cn');
      await expectLater(
          service.bookCourt(
              sport: OaSport.badminton,
              date: '2026-10-08',
              timeSlot: 8,
              courtNumber: 1,
              playersCount: 2,),
          throwsA(isA<OaGymException>()),);
      response = OaSchoolClient.contacts(id: 'different-user');
      await service.syncBookingProfile(overwrite: true);
      expect(service.profileSyncError, contains('当前用户'));
      expect(service.bookingProfile().phone, isEmpty);
    });

    test('unavailable OA contacts still allow manual details and court queries', () async {
      final fixture = await _serviceFixture(withBookingProfile: false);
      final school = OaSchoolClient()
        ..intercept = (request) async =>
            _isContact(request) ? OaSchoolClient.text('not found', status: 404) : null;
      final service = _service(fixture, school);
      await service.syncBookingProfile();
      expect(service.profileSyncError, isNotNull);
      await service.saveBookingProfile(
          const OaBookingProfile(name: 'Manual', phone: '13800000000', email: ''),);
      await service.ensureReady();
      expect(service.sessionReady, true);
      expect(service.bookingProfile().phone, '13800000000');
    });
  });

  test('court queries require a local Passkey binding', () async {
    final fixture = await _serviceFixture(bindIds: false);
    final school = OaSchoolClient();
    final service = _service(fixture, school);
    expect(
        () => service.checkAvailability(
            sports: {OaSport.badminton}, date: '2026-05-23', startSlot: 8, endSlot: 8,),
        throwsA(isA<OaGymException>()),);
    expect(school.requests, isEmpty);
  });
}

Future<_Fixture> _serviceFixture({bool bindIds = true, bool withBookingProfile = true}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveSession(UserSession(
      userId: 'user',
      userName: 'User',
      schoolName: 'School',
      phoneNumber: '13800000000',
      studentId: '',
      createdAt: DateTime.utc(2026),),);
  if (bindIds) {
    await storage.saveThirdPartyAccount(FakeIdsClient.account('20240001'));
    if (withBookingProfile) {
      await storage.saveOaBookingProfile(
          const OaBookingProfile(name: 'User', phone: '13800000000', email: ''),
          owner: 'user|20240001',);
    }
  }
  final api = LoggingHttpClient(DebugLogger());
  final auth = AuthService(storage, api, UniAuthService());
  final tpAuth = ThirdPartyAuthService(storage, api, idsClient: FakeIdsClient());
  await auth.loadSession();
  await tpAuth.initialize();
  return _Fixture(storage, auth, tpAuth);
}

OaGymService _service(_Fixture fixture, OaSchoolClient school) {
  final service = OaGymService(fixture.auth, fixture.storage, fixture.tpAuth, client: school);
  addTearDown(service.dispose);
  return service;
}

Future<void> _setAccount(_Fixture fixture, String username, DateTime time) =>
    fixture.tpAuth.applyIdsSyncBinding(IdsSyncBinding(
        credential: FakeIdsClient.key(username), updatedAt: time, deviceId: 'fixture',),);

class _Fixture {
  const _Fixture(this.storage, this.auth, this.tpAuth);
  final StorageService storage;
  final AuthService auth;
  final ThirdPartyAuthService tpAuth;
}
