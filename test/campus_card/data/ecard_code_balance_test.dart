import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/data/api/ecard_api_client.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_card_repository.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_payment_code_repository.dart';
import 'package:techpie/features/campus_card/data/storage/secure_card_cache.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import '../support/fake_ecard_transport.dart';

const _session = EcardSession(sessionCookie: 'JSESSIONID=synthetic', openId: 'SYNTHETIC', orgId: '2', subjectId: 'subject',
  identity: EcardVerifiedIdentity(subjectId: 'subject', idSerial: 'STUDENT', cardId: 'CARD'),);
EcardResponseMap _response(Map<String, Object?> data, int order, {Future<void> Function()? validate}) =>
    EcardResponseMap(data, _session, validate ?? (() async {}), null, null, order);

void main() {
  late FakeEcardTransport transport;
  late EcardCardRepository cards;
  setUp(() {
    transport = FakeEcardTransport();
    cards = EcardCardRepository(transport,
      cache: SecureCardCache(InMemorySecureCredentialStore(), subjectReader: () async => 'subject', verifiedIdSerialReader: () async => 'STUDENT'),
      purgeLocalSecurityState: () async {}, verifiedIdSerialReader: () async => 'STUDENT',);
  });
  tearDown(() async { await cards.dispose(); });
  Future<void> account(String balance, int order) async {
    transport.enqueue('POST', '/myaccount/openMyAccountApp', {'success': true, 'data': _response({
      'cardinfo': {'idserial': 'STUDENT', 'cardbal': balance, 'username': 'Owner', 'accstatus': '1', 'pcode': '01'},
    }, order,),});
    await cards.refreshCard();
  }
  test('code balance merges metadata and cache; repeated value has no change', () async {
    await account('100.00', 1);
    final before = (await cards.readCachedCard())!;
    final changed = await cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 2), const MoneyFen(9919));
    final after = (await cards.readCachedCard())!;
    expect(changed, isTrue);
    expect(after.balance.value, 9919);
    expect(after.ownerName, before.ownerName);
    expect(after.positionCode, before.positionCode);
    expect(after.updatedAt, before.updatedAt);
    expect(await cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 3), const MoneyFen(9919)), isFalse);
  });
  test('older account and code snapshots cannot overwrite a newer balance', () async {
    await account('100.00', 1);
    await cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 3), const MoneyFen(9000));
    await account('95.00', 2);
    expect((await cards.readCachedCard())!.balance.value, 9000);
    await account('110.00', 5);
    expect(await cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 4), const MoneyFen(8000)), isFalse);
    expect((await cards.readCachedCard())!.balance.value, 11000);
  });
  test('balance received before card metadata survives an older initial account response', () async {
    expect(await cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 2), const MoneyFen(9500)), isFalse);
    await account('100.00', 1);
    expect((await cards.readCachedCard())!.balance.value, 9500);
  });
  test('invalid session context cannot update a cached balance', () async {
    await account('100.00', 1);
    await expectLater(cards.acceptCodeBalance(_response({'data': {'idserial': 'STUDENT'}}, 2,
      validate: () async { throw StateError('account changed'); },), const MoneyFen(1),), throwsStateError,);
    expect((await cards.readCachedCard())!.balance.value, 10000);
  });
  for (final raw in [null, '', 'invalid', '1.001', '0.00', '42.37']) {
    test('optional code balance parses without hiding QR: $raw', () async {
      var calls = 0;
      transport.enqueue('POST', '/offlineCode/openVirtualcard', {'success': true, 'data': {
        'code': 'SYNTHETIC-CODE', 'qrcode': 'SYNTHETIC-QR', 'cardbal': raw,
      },});
      final repo = EcardPaymentCodeRepository(transport, onBalance: (_, value) async { calls++; return true; });
      final frame = await repo.generateOnlineCode();
      expect(frame.qrPayload, 'SYNTHETIC-QR');
      final valid = raw == '0.00' || raw == '42.37';
      expect(calls, valid ? 1 : 0);
      expect(frame.balanceChanged, valid);
      expect(frame.balance?.value, raw == '0.00' ? 0 : raw == '42.37' ? 4237 : null);
    });
  }
}
