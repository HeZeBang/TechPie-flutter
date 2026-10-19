import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:techpie/services/wear/wear_engine_service.dart';
import 'package:techpie/services/wear/wear_protocol.dart';

final testNow = DateTime.utc(2026, 10, 13);
const fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

class MemoryMetadata implements WearMetadata {
  String? value;
  @override
  String? read() => value;
  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class Source implements WearDataSource {
  String scope = 'account-a';
  bool failDdl = false;
  List<WearDdl> items = [];
  Completer<WearCampusCode>? delayedCode;
  Completer<List<WearDdl>>? delayedDdl;
  Completer<WearAccount>? delayedAccount;
  @override
  Future<WearAccount> account() async => delayedAccount == null
      ? WearAccount(scope: scope, name: '张三', studentId: '00123')
      : delayedAccount!.future;
  @override
  Future<List<WearDdl>> deadlines() async {
    if (failDdl) throw const WearFailure('SERVICE_UNAVAILABLE');
    return delayedDdl == null ? items : delayedDdl!.future;
  }

  @override
  Future<WearCampusCode> campusCode(String purpose) async => delayedCode == null
      ? WearCampusCode(
          bytes: Uint8List.fromList([0, 128, 255]),
          issuedAt: testNow,
          validUntil: testNow.add(const Duration(seconds: 30)),
        )
      : delayedCode!.future;
}

class Peer implements WearTransport {
  final received = <Map<String, dynamic>>[];
  final codec = WearFrames();
  final frameStream = StreamController<Uint8List>.broadcast();
  final stateStream = StreamController<Map<String, dynamic>>.broadcast();
  bool ignoreAccount = false;
  bool rejectDdl = false;
  bool ignoreHeartbeat = false;
  List<String> capabilities = [
    'account.display',
    'ddl.display',
    'campusCode.qrBytes',
  ];
  bool staleAck = false;
  int droppedAcks = 0, counter = 0, clears = 0;
  Map<String, dynamic>? schedule;
  String? session, binding;
  @override
  Stream<Uint8List> get frames => frameStream.stream;
  @override
  Stream<Map<String, dynamic>> get states => stateStream.stream;
  @override
  Future<Map<String, dynamic>> status() async => {
        'service': 'ready',
        'device': 'connected',
        'permission': {'p2p': true, 'notify': true},
      };
  @override
  Future<List<Map<String, dynamic>>> devices() async => [
        {'id': 'watch'},
      ];
  @override
  Future<Map<String, dynamic>> authorize({required bool notify}) async =>
      {'p2p': true, 'notify': notify};
  @override
  Future<void> open(String deviceId, String fingerprint) async {}
  @override
  Future<void> close() async {
    codec.clear();
  }

  void respond(
    Map<String, dynamic> request,
    String type,
    Map<String, dynamic> body, {
    bool handshake = false,
  }) {
    emit({
      'v': 1,
      'id': 'w${counter++}',
      'replyTo': request['id'],
      'sessionId': handshake
          ? null
          : staleAck
              ? 'old'
              : session,
      'bindingId': handshake ? null : binding,
      'type': type,
      'sentAtMs': testNow.millisecondsSinceEpoch,
      'body': body,
    });
  }

  void emit(Map<String, dynamic> message) {
    for (final frame in WearFrames.encode(message)) {
      frameStream.add(frame);
    }
  }

  void request(String type, Map<String, dynamic> body) => emit({
        'v': 1,
        'id': 'q${counter++}',
        'replyTo': null,
        'sessionId': session,
        'bindingId': binding,
        'type': type,
        'sentAtMs': testNow.millisecondsSinceEpoch,
        'body': body,
      });
  @override
  Future<void> send(Uint8List bytes) async {
    expectSync(bytes.length, lessThanOrEqualTo(1024));
    final message = codec.accept(bytes, testNow);
    if (message == null) return;
    received.add(message);
    final body = message['body'] as Map;
    switch (message['type']) {
      case 'session.hello':
        respond(
          message,
          'session.welcome',
          {
            'nonce': body['nonce'],
            'version': 1,
            'watchInstanceId': 'watch-install',
            'capabilities': capabilities,
          },
          handshake: true,
        );
      case 'session.open':
        session = body['sessionId'] as String;
        binding = body['bindingId'] as String;
        respond(message, 'session.opened', {}, handshake: true);
      case 'account.snapshot':
        if (ignoreAccount) return;
        if (droppedAcks > 0) {
          droppedAcks--;
          return;
        }
        respond(message, 'result', {
          'status': 'ok',
          'code': 'OK',
          'resource': 'account',
          'revision': body['revision'],
        });
      case 'ddl.snapshot':
        if (rejectDdl) {
          respond(message, 'result', {
            'status': 'error',
            'code': 'SERVICE_UNAVAILABLE',
          });
          return;
        }
        respond(message, 'result', {
          'status': 'ok',
          'code': 'OK',
          'resource': 'ddl',
          'revision': body['revision'],
        });
      case 'session.clear':
        respond(message, 'result', {'status': 'ok', 'code': 'OK'});
      case 'session.close':
        respond(message, 'result', {'status': 'ok', 'code': 'OK'});
      case 'session.ping':
        if (!ignoreHeartbeat) {
          respond(message, 'result', {'status': 'ok', 'code': 'OK'});
        }
      case 'campusCode.snapshot':
        respond(message, 'result', {'status': 'ok', 'code': 'OK'});
    }
  }

  @override
  Future<void> scheduleReminders(Map<String, dynamic> spec) async {
    schedule = spec;
  }

  @override
  Future<void> cancelReminders() async {
    clears++;
    schedule = null;
  }

  @override
  Future<String> sendReminder(String id) async => 'submitted';
  @override
  void dispose() {
    unawaited(frameStream.close());
    unawaited(stateStream.close());
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Peer peer;
  late Source source;
  late MemoryMetadata metadata;
  late WearEngineService service;
  setUp(() {
    peer = Peer();
    source = Source();
    metadata = MemoryMetadata();
    service = WearEngineService(
      transport: peer,
      source: source,
      metadata: metadata,
      now: () => testNow,
      timeout: const Duration(milliseconds: 25),
      retryDelays: [Duration.zero],
    );
  });
  tearDown(() {
    service.dispose();
  });
  Future<void> open({bool notify = false}) async => await service.open(
        'watch',
        watchFingerprint: fingerprint,
        notify: notify,
      );

  test('UTF-8 Chinese framing roundtrips out of order without exceeding 1KB',
      () {
    final message = {
      'v': 1,
      'id': 'm1',
      'type': 'account.snapshot',
      'sentAtMs': 1,
      'body': {'text': '校园任务' * 1200},
    };
    final frames = WearFrames.encode(message);
    final codec = WearFrames();
    Map<String, dynamic>? result;
    for (final frame in frames.reversed) {
      expect(frame.length, lessThanOrEqualTo(1024));
      result = codec.accept(frame, testNow) ?? result;
    }
    expect(result, message);
  });
  test('matrix-capable watch receives a byte-preserving QR matrix', () async {
    peer.capabilities = [
      'account.display',
      'ddl.display',
      'campusCode.qrMatrix',
    ];
    await open();
    peer.request(
      'campusCode.request',
      {'purpose': 'campus', 'format': 'qrBytes'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final body = peer.received
        .firstWhere((m) => m['type'] == 'campusCode.snapshot')['body'] as Map;
    final bytes = Uint8List.fromList([0, 128, 255]);
    final reference = QrImage(
      QrCode.fromUint8List(
        data: bytes,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ),
    );
    expect(body['matrixSize'], reference.moduleCount);
    final bits = base64Decode(body['matrix'] as String);
    for (var row = 0; row < reference.moduleCount; row++) {
      for (var col = 0; col < reference.moduleCount; col++) {
        final index = row * reference.moduleCount + col;
        expect(
          (bits[index ~/ 8] & (1 << (7 - index % 8))) != 0,
          reference.isDark(row, col),
        );
      }
    }
    expect(base64Decode(body['payload'] as String), bytes);
  });
  test(
      'reminder toggle schedules after consent and cancels on disable or close',
      () async {
    source.items = [
      WearDdl(
        id: 'task',
        title: '作业',
        courseName: '数学',
        dueAt: testNow.add(const Duration(hours: 2)),
        completed: false,
        remindAt: [testNow.add(const Duration(hours: 1))],
      ),
    ];
    await open();
    expect(service.remindersEnabled, false);
    expect(peer.schedule, isNull);
    await service.setRemindersEnabled(true);
    expect(service.remindersEnabled, true);
    expect(peer.schedule!['items'], hasLength(1));
    await service.setRemindersEnabled(false);
    expect(peer.schedule, isNull);
    await service.setRemindersEnabled(true);
    await service.close();
    expect(peer.schedule, isNull);
    expect(service.remindersEnabled, false);
  });
  test('failed reminder enable rolls back consent and supports retry',
      () async {
    await open();
    source.failDdl = true;
    await expectLater(
      service.setRemindersEnabled(true),
      throwsA(isA<WearFailure>()),
    );
    expect(service.remindersEnabled, false);
    expect(service.supports('reminder.phoneNotify'), false);
    expect(peer.schedule, isNull);
    source.failDdl = false;
    await service.setRemindersEnabled(true);
    expect(service.remindersEnabled, true);
    expect(peer.schedule, isNotNull);
  });

  test('failed watch receipt cancels partially scheduled reminders', () async {
    source.items = [
      WearDdl(
        id: 'task',
        title: '作业',
        courseName: '数学',
        dueAt: testNow.add(const Duration(hours: 2)),
        completed: false,
        remindAt: [testNow.add(const Duration(hours: 1))],
      ),
    ];
    await open();
    peer.rejectDdl = true;
    await expectLater(
      service.setRemindersEnabled(true),
      throwsA(isA<WearFailure>()),
    );
    expect(service.remindersEnabled, false);
    expect(peer.schedule, isNull);
  });

  test('disconnect during reminder enrollment cannot re-enable reminders',
      () async {
    await open();
    source.delayedDdl = Completer<List<WearDdl>>();
    final pending = service.setRemindersEnabled(true);
    final failure = expectLater(pending, throwsA(isA<WearFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.close();
    source.delayedDdl!.complete([]);
    await failure;
    expect(service.remindersEnabled, false);
    expect(peer.schedule, isNull);
  });

  test('rejects oversized data and conflicting duplicate fragments', () {
    expect(
      () => WearFrames.encode({
        'v': 1,
        'id': 'm',
        'body': {'data': 'a' * 40000},
      }),
      throwsA(isA<WearFailure>()),
    );
    final codec = WearFrames();
    Uint8List fragment(int byte) => Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'v': 1,
              'mid': 'm',
              'i': 0,
              'n': 2,
              'data': base64Encode(List.filled(512, byte)),
            }),
          ),
        );
    codec.accept(fragment(1), testNow);
    expect(
      () => codec.accept(fragment(2), testNow),
      throwsA(isA<WearFailure>()),
    );
  });
  test('handshake and application receipts publish only minimal account fields',
      () async {
    await open();
    expect(service.ready, true);
    expect((service.getStatus()['sync'] as Map)['account']['state'], 'applied');
    final account =
        peer.received.firstWhere((m) => m['type'] == 'account.snapshot');
    expect(account['body']['data'], {'name': '张三', 'studentId': '00123'});
    expect(jsonEncode(account), isNot(contains('account-a')));
  });
  test('SDK sends without application acknowledgements stay failed', () async {
    peer.ignoreAccount = true;
    await open();
    expect(service.ready, true);
    expect((service.getStatus()['sync'] as Map)['account']['state'], 'failed');
    expect((service.getStatus()['sync'] as Map)['ddl']['state'], 'applied');
  });
  test('lost receipt retries the identical message id and revision', () async {
    peer.droppedAcks = 1;
    await open();
    final snapshots =
        peer.received.where((m) => m['type'] == 'account.snapshot').toList();
    expect(snapshots.length, 2);
    expect(snapshots[0], snapshots[1]);
  });
  test('old session receipt cannot acknowledge new data', () async {
    peer.staleAck = true;
    await open();
    expect((service.getStatus()['sync'] as Map)['account']['state'], 'failed');
  });
  test('DDL selection truncates whole items and retains binary code bytes',
      () async {
    source.items = List.generate(
      60,
      (i) => WearDdl(
        id: 'ddl-$i',
        title: '任务 $i',
        courseName: '课程',
        dueAt: testNow.add(Duration(hours: i + 1)),
        completed: false,
      ),
    );
    await open();
    final ddl =
        peer.received.firstWhere((m) => m['type'] == 'ddl.snapshot')['body'];
    expect(ddl['items'].length, 50);
    expect(ddl['truncated'], true);
    peer.request(
      'campusCode.request',
      {'purpose': 'campus', 'format': 'qrBytes'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final code = peer.received
        .firstWhere((m) => m['type'] == 'campusCode.snapshot')['body'];
    expect(base64Decode(code['payload'] as String), [0, 128, 255]);
    expect(
      code['validUntilMs'],
      testNow.add(const Duration(seconds: 30)).millisecondsSinceEpoch,
    );
  });
  test(
      'reminders require separate notify consent and account mutation clears them',
      () async {
    source.items = [
      WearDdl(
        id: 'd',
        title: '任务',
        courseName: '课',
        dueAt: testNow.add(const Duration(hours: 2)),
        completed: false,
        remindAt: [testNow.add(const Duration(hours: 1))],
      ),
    ];
    await open(notify: true);
    expect(peer.schedule!['items'].length, 1);
    source.scope = 'account-b';
    await service.reconcileAccount();
    expect(service.ready, false);
    expect(peer.schedule, isNull);
    expect(peer.received.any((m) => m['type'] == 'session.clear'), true);
    expect(jsonDecode(metadata.value!)['binding'], isNull);
  });
  test('late campus code response is dropped when the account changes',
      () async {
    await open();
    source.delayedCode = Completer<WearCampusCode>();
    peer.request(
      'campusCode.request',
      {'purpose': 'campus', 'format': 'qrBytes'},
    );
    await Future<void>.delayed(const Duration(milliseconds: 5));
    source.scope = 'other-account';
    source.delayedCode!.complete(
      WearCampusCode(
        bytes: Uint8List.fromList([1]),
        issuedAt: testNow,
        validUntil: testNow.add(const Duration(seconds: 30)),
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(peer.received.any((m) => m['type'] == 'campusCode.snapshot'), false);
  });
  test('revocation while disconnected remains durable until clear receipt',
      () async {
    await open();
    await service.close();
    await service.clear(reason: 'logout');
    expect(jsonDecode(metadata.value!)['pendingClear'], 'logout');
    await open();
    final messages = peer.received.map((m) => m['type']).toList();
    final clearIndex = messages.indexOf('session.clear');
    expect(clearIndex, greaterThan(0));
    expect(messages.sublist(clearIndex + 1), contains('account.snapshot'));
    expect(jsonDecode(metadata.value!)['pendingClear'], isNull);
  });
  test('account switch during DDL fetch cannot schedule or transmit old tasks',
      () async {
    await open(notify: true);
    source.delayedDdl = Completer<List<WearDdl>>();
    final refresh = service.refresh(resources: ['ddl']);
    final failure = expectLater(refresh, throwsA(isA<WearFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    source.scope = 'new-account';
    await service.reconcileAccount();
    source.delayedDdl!.complete([
      WearDdl(
        id: 'old',
        title: '旧账号任务',
        courseName: '旧课',
        dueAt: testNow.add(const Duration(hours: 2)),
        completed: false,
        remindAt: [testNow.add(const Duration(hours: 1))],
      ),
    ]);
    await failure;
    expect(peer.schedule, isNull);
    expect(peer.received.where((m) => m['type'] == 'ddl.snapshot').length, 1);
  });
  test('revocation wins over delayed connection enrollment', () async {
    source.delayedAccount = Completer<WearAccount>();
    final enrollment = open();
    final failure = expectLater(enrollment, throwsA(isA<WearFailure>()));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await service.clear();
    source.delayedAccount!.complete(
      const WearAccount(scope: 'account-a', name: '张三', studentId: '00123'),
    );
    await failure;
    expect(service.ready, false);
    expect(peer.received.any((m) => m['type'] == 'account.snapshot'), false);
    source.delayedAccount = null;
    await open();
    expect(service.ready, true);
  });
}
