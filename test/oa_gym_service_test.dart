import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
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

void main() {
  test('queries availability through TechPie backend with CASTGC payload',
      () async {
    final fixture = await _serviceFixture();
    final requests = <Uri>[];
    final client = _FakeClient((request) async {
      requests.add(request.url);
      expect(request.url.host, anyOf('techpie.geekpie.club', 'localhost'));
      expect(request.url.path, '/api/oa/gym/availability');
      expect(request.headers['Content-Type'], contains('application/json'));

      final body = jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>;
      expect(body['auth']['tgc'], 'tgc-value');
      expect(body['auth']['cookies'], 'happyVoyage=happy; CASTGC=tgc-value');
      expect(body['sports'], ['badminton']);
      expect(body['date'], '2026-05-23');
      expect(body['startSlot'], 8);
      expect(body['endSlot'], 8);
      return _jsonResponse({
        'success': true,
        'data': [
          {
            'sport': 'badminton',
            'date': '2026-05-23',
            'timeSlot': 8,
            'availableCourts': [1, 3],
            'totalCourts': 6,
          }
        ],
      });
    });

    final service =
        OaGymService(
      fixture.auth,
      fixture.storage,
      fixture.tpAuth,
      client: client,
    );
    final result = await service.checkAvailability(
      sports: {OaSport.badminton},
      date: '2026-05-23',
      startSlot: 8,
      endSlot: 8,
    );

    expect(result, hasLength(1));
    expect(result.single.availableCourts, [1, 3]);
    expect(requests.single.host, isNot(contains('shanghaitech.edu.cn')));
  });

  test('loads metadata and searches courts through TechPie backend', () async {
    final fixture = await _serviceFixture();
    final paths = <String>[];
    final client = _FakeClient((request) async {
      paths.add(request.url.path);
      expect(request.url.host, anyOf('techpie.geekpie.club', 'localhost'));
      final body = jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>;
      expect(body['auth']['tgc'], 'tgc-value');

      if (request.url.path == '/api/oa/gym/metadata') {
        return _jsonResponse({
          'success': true,
          'data': {
            'venues': {
              '所有场地': 'all',
              '室内羽毛球场': 'badminton_group',
              '羽毛球场地 １ 号（东馆）': '13',
            },
            'allVenues': {
              '羽毛球场地 １ 号（东馆）': '13',
            },
            'timeSlots': {
              '18:00-19:00': '8',
            },
          },
        });
      }

      expect(request.url.path, '/api/oa/gym/search');
      expect(body['startDate'], '2026-05-23');
      expect(body['endDate'], '2026-05-23');
      expect(body['venueNames'], ['室内羽毛球场']);
      expect(body['timeRanges'], ['18:00-19:00']);
      return _jsonResponse({
        'success': true,
        'data': [
          {
            'venue': '羽毛球场地 １ 号（东馆）',
            'timeRange': '18:00-19:00',
            'rows': [
              [
                '1',
                '',
                '2026-05-23',
                '',
                '',
                '',
                '已通过',
                'User',
                '',
                '2026-05-24',
              ],
            ],
          }
        ],
      });
    });

    final service =
        OaGymService(
      fixture.auth,
      fixture.storage,
      fixture.tpAuth,
      client: client,
    );
    final result = await service.searchCourts(
      startDate: '2026-05-23',
      endDate: '2026-05-23',
      venueNames: {'室内羽毛球场'},
      timeRanges: const ['18:00-19:00'],
    );

    expect(result, hasLength(1));
    expect(result.single.venue, '羽毛球场地 １ 号（东馆）');
    expect(result.single.rows.single[6], '已通过');
    expect(paths, ['/api/oa/gym/metadata', '/api/oa/gym/search']);
  });

  test('books courts through TechPie backend', () async {
    final fixture = await _serviceFixture();
    final client = _FakeClient((request) async {
      expect(request.url.path, '/api/oa/gym/book');
      final body = jsonDecode(await request.finalize().bytesToString())
          as Map<String, dynamic>;
      expect(body['auth']['tgc'], 'tgc-value');
      expect(body['booking']['sport'], 'badminton');
      expect(body['booking']['studentId'], '20240001');
      expect(body['booking']['userName'], 'User');
      expect(body['booking']['phone'], '13800000000');
      return _jsonResponse({
        'success': true,
        'data': {
          'success': true,
          'message': '羽毛球 羽毛球场地1号 18:00-19:00 预约成功',
        },
      });
    });

    final service =
        OaGymService(
      fixture.auth,
      fixture.storage,
      fixture.tpAuth,
      client: client,
    );
    final result = await service.bookCourt(
      sport: OaSport.badminton,
      date: '2026-05-23',
      timeSlot: 8,
      courtNumber: 1,
      playersCount: 2,
    );

    expect(result.success, isTrue);
    expect(result.message, contains('预约成功'));
  });

  test('throws when eGate binding is absent', () async {
    final fixture = await _serviceFixture(bindEgate: false);
    final client = _FakeClient(
      (request) async => _jsonResponse({
        'success': true,
        'data': const <String, dynamic>{},
      }),
    );
    final service = OaGymService(
      fixture.auth,
      fixture.storage,
      fixture.tpAuth,
      client: client,
    );

    expect(
      () => service.checkAvailability(
        sports: {OaSport.badminton},
        date: '2026-05-23',
        startSlot: 8,
        endSlot: 8,
      ),
      throwsA(isA<OaGymException>()),
    );
  });
}

Future<_Fixture> _serviceFixture({
  bool bindEgate = true,
}) async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final storage = StorageService(prefs);
  // Primary account is the GeekPie SSO identity session — it carries no
  // CASTGC / CpDaily session at all.
  await storage.saveSession(
    UserSession(
      userId: 'user',
      userName: 'User',
      schoolName: 'School',
      phoneNumber: '13800000000',
      studentId: '',
      createdAt: DateTime.utc(2026),
    ),
  );
  if (bindEgate) {
    await storage.saveThirdPartyAccount(
      ThirdPartyAccount(
        platform: ThirdPartyPlatform.cpdaily,
        account: '20240001',
        sid: '20240001',
        token: 'session',
        raw: const {
          'tgc': 'tgc-value',
          'cookies': 'happyVoyage=happy',
          'sessionToken': 'session',
          'userId': 'user',
          'tenantId': 'tenant',
        },
        boundAt: DateTime.utc(2026),
      ),
    );
  }
  final logger = DebugLogger();
  final httpClient = LoggingHttpClient(logger);
  final uniAuth = UniAuthService();
  final auth = AuthService(storage, httpClient, uniAuth);
  final tpAuth = ThirdPartyAuthService(storage, httpClient);
  await auth.loadSession();
  await tpAuth.initialize();
  return _Fixture(storage, auth, tpAuth);
}

http.Response _jsonResponse(Map<String, dynamic> body) => http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

class _Fixture {
  final StorageService storage;
  final AuthService auth;
  final ThirdPartyAuthService tpAuth;

  const _Fixture(this.storage, this.auth, this.tpAuth);
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this._handler);

  final Future<http.Response> Function(http.BaseRequest request) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _handler(request);
    return http.StreamedResponse(
      Stream<List<int>>.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
