import 'dart:convert';

import 'package:flutter_secure_storage_ohos/flutter_secure_storage_ohos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/library_reservation_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('uses real availability fields and keeps CASTGC off booking requests', () async {
    final auth = await _auth();
    final requests = <http.BaseRequest>[];
    final client = _FakeClient((request) async {
      requests.add(request);
      if (request.url.path.endsWith('/login') &&
          request.url.host == 'libspace.shanghaitech.edu.cn') {
        expect(request.headers['cookie'], isNull);
        return _response('', 302, {
          'location': 'https://ids.shanghaitech.edu.cn/authserver/oauth2.0/authorize?state=state-1',
          'set-cookie': 'LIBSESSION=library; Path=/',
        });
      }
      if (request.url.host == 'ids.shanghaitech.edu.cn') {
        expect(request.headers['cookie'], contains('CASTGC=newest'));
        expect(request.headers['cookie'], isNot(contains('older')));
        return _response('', 302, {
          'location': 'https://libspace.shanghaitech.edu.cn/login?code=code-1&state=state-1',
        });
      }
      if (request.url.path.endsWith('/callBack')) {
        expect(request.headers['cookie'], 'LIBSESSION=library');
        expect(request.headers['cookie'], isNot(contains('CASTGC')));
        return _json({
          'code': 0,
          'data': {'access_token': 'library-token'},
        });
      }
      if (request.url.path.endsWith('/space-config')) {
        expect(request.headers['token'], 'library-token');
        return _json({
          'code': 0,
          'data': {
            'cycleDays': 7,
            'maxDurationHours': 4,
            'minDurationHours': 0.5,
            'openStartTime': '07:30',
            'openEndTime': '23:00',
          },
        });
      }
      if (request.url.path.endsWith('/spaces')) {
        final date = request.url.queryParameters['date'];
        expect(date, anyOf('2026-11-20', '2026-11-21'));
        final tomorrow = date == '2026-11-21';
        return _json({
          'code': 0,
          'data': {
            'total': 1,
            'list': [
              {
                'id': 6,
                'spaceName': '讨论室101-3',
                'capacity': 8,
                'scheduleDate': date,
                'slots': [
                  {'time': '09:30', 'statusCode': tomorrow ? 'OCCUPIED' : 'AVAILABLE'},
                  {'time': '10:00', 'statusCode': 'AVAILABLE'},
                  {'time': '10:30', 'statusCode': 'OCCUPIED'},
                  {'time': '11:00', 'statusCode': 'CLOSED'},
                  {'time': '11:30', 'statusCode': 'AVAILABLE'},
                ],
              },
            ],
          },
        });
      }
      expect(request.method, 'POST');
      expect(request.headers['token'], 'library-token');
      expect(request.headers['cookie'], isNull);
      final body = jsonDecode(await request.finalize().bytesToString());
      expect(body, {
        'spaceId': '6',
        'spaceType': 'DISCUSSION_ROOM',
        'dates': ['2026-11-20'],
        'continuous': false,
        'startTime': '09:30',
        'endTime': '10:30',
        'meetingType': 'SEMINAR',
        'title': 'Project',
        'inviterList': [
          {'inviterName': '同学', 'inviterNo': '20260001'},
        ],
      });
      return _json({'code': 0});
    });
    final service = LibraryReservationService(auth, client: client);
    final date = DateTime.utc(2026, 11, 20);
    final availability = await service.load(LibrarySpaceType.discussion, date);
    final room = availability.rooms.single;
    expect(availability.startTimes(room), [570, 600, 690]);
    expect(availability.statusAt(room, 630), LibrarySlotStatus.occupied);
    expect(availability.statusAt(room, 660), LibrarySlotStatus.closed);
    expect(availability.statusAt(room, 720), LibrarySlotStatus.closed);
    expect(availability.latestEnd(room, 570), 630);
    expect(availability.stepMinutes, 30);

    final nextDay = date.add(const Duration(days: 1));
    final switched = await service.load(LibrarySpaceType.discussion, nextDay);
    expect(switched.startTimes(switched.rooms.single), [600, 690]);
    final range = await service.load(LibrarySpaceType.study, date, through: nextDay);
    expect(range.startTimes(range.rooms.single), [600, 690]);
    expect(range.statusAt(range.rooms.single, 570), LibrarySlotStatus.occupied);

    await service.book(
      type: LibrarySpaceType.discussion,
      room: room,
      dates: [date],
      start: 570,
      end: 630,
      continuous: false,
      meetingType: 'SEMINAR',
      topic: 'Project',
      participants: const [
        LibraryParticipant(name: '同学', number: '20260001'),
      ],
    );

    expect(requests.where((r) => r.method == 'POST'), hasLength(1));
  });

  test('does not replay a booking after token expiry', () async {
    final auth = await _auth();
    var posts = 0;
    final client = _FakeClient((request) async {
      if (request.url.path.endsWith('/login') &&
          request.url.host == 'libspace.shanghaitech.edu.cn') {
        return _response('', 302, {
          'location': 'https://ids.shanghaitech.edu.cn/authserver/oauth2.0/authorize?state=s',
        });
      }
      if (request.url.host == 'ids.shanghaitech.edu.cn') {
        return _response('', 302, {
          'location': 'https://libspace.shanghaitech.edu.cn/login?code=c&state=s',
        });
      }
      if (request.url.path.endsWith('/callBack')) {
        return _json({
          'code': 0,
          'data': {'access_token': 'expired'},
        });
      }
      posts++;
      return _json({'code': 40101, 'msg': 'expired'}, status: 401);
    });
    final service = LibraryReservationService(auth, client: client);

    await expectLater(
      service.book(
        type: LibrarySpaceType.silent,
        room: const LibraryRoom(
          id: 'booth',
          name: '静音舱',
          capacity: 1,
          disabled: false,
          slots: {600: LibrarySlotStatus.available},
        ),
        dates: [DateTime(2026, 11, 20)],
        start: 600,
        end: 660,
        continuous: false,
      ),
      throwsA(isA<LibraryReservationException>()),
    );
    expect(posts, 1);
  });

  test('lists paged reservations and never replays cancellation', () async {
    final auth = await _auth();
    var cancellations = 0;
    final client = _FakeClient((request) async {
      if (request.url.path.endsWith('/login') &&
          request.url.host == 'libspace.shanghaitech.edu.cn') {
        return _response('', 302, {
          'location': 'https://ids.shanghaitech.edu.cn/authserver/oauth2.0/authorize?state=s',
        });
      }
      if (request.url.host == 'ids.shanghaitech.edu.cn') {
        return _response('', 302, {
          'location': 'https://libspace.shanghaitech.edu.cn/login?code=c&state=s',
        });
      }
      if (request.url.path.endsWith('/callBack')) {
        return _json({
          'code': 0,
          'data': {'access_token': 'token'},
        });
      }
      expect(request.method, 'POST');
      expect(request.headers['token'], 'token');
      if (request.url.path.endsWith('/my/reservations/list')) {
        expect(jsonDecode(await request.finalize().bytesToString()), {
          'tab': 'current',
          'pageNo': 2,
          'pageSize': 10,
        });
        return _json({
          'code': 0,
          'data': {
            'total': 21,
            'list': [
              {
                'reservationId': 42,
                'spaceName': '讨论室101',
                'typeName': '讨论室',
                'reservationType': 'DISCUSSION_ROOM',
                'reserveDate': '2026-11-20',
                'startTime': '09:30',
                'endTime': '10:30',
                'reservationStatus': 'WAIT_SIGN',
                'reservationStatusStr': '待签到',
              },
            ],
          },
        });
      }
      cancellations++;
      expect(request.url.path, endsWith('/my/reservations/42/cancel'));
      expect(await request.finalize().bytesToString(), isEmpty);
      return _json({'code': 40101, 'msg': 'expired'}, status: 401);
    });
    final service = LibraryReservationService(auth, client: client);

    final page = await service.listReservations(history: false, page: 2);
    expect(page.hasMore, isTrue);
    expect(page.records, hasLength(1));
    final record = page.records.single;
    expect(record.id, '42');
    expect(record.name, '讨论室101');
    expect(record.typeLabel, '讨论室');
    expect(record.date, '2026-11-20');
    expect(record.startTime, '09:30');
    expect(record.endTime, '10:30');
    expect(record.statusLabel, '待签到');
    expect(record.canCancel, isTrue);

    await expectLater(
      service.cancelReservation(record),
      throwsA(isA<LibraryReservationException>()),
    );
    expect(cancellations, 1);
  });
}

Future<ThirdPartyAuthService> _auth() async {
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({});
  final storage = StorageService(await SharedPreferences.getInstance());
  await storage.saveThirdPartyAccount(
    ThirdPartyAccount(
      platform: ThirdPartyPlatform.cpdaily,
      account: '20260000',
      sid: '20260000',
      token: 'session',
      raw: const {
        'tgc': 'newest',
        'cookies': 'CASTGC=older; happyVoyage=x; CASTGC=newest',
        'sessionToken': 'session',
        'userId': 'user',
        'tenantId': 'tenant',
      },
      boundAt: DateTime.utc(2026),
    ),
  );
  final auth = ThirdPartyAuthService(
    storage,
    LoggingHttpClient(DebugLogger(), inner: _FakeClient((_) async => _json({}))),
  );
  await auth.initialize();
  return auth;
}

http.Response _json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response _response(String body, int status, Map<String, String> headers) =>
    http.Response(body, status, headers: headers);

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);
  final Future<http.Response> Function(http.BaseRequest request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.followRedirects, isFalse);
    final response = await handler(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}
