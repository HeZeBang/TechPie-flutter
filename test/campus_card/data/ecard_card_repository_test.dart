import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_card_repository.dart';
import 'package:techpie/features/campus_card/data/storage/secure_card_cache.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  test('maps balance and masks the student number tail', () async {
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/myaccount/openMyAccountApp', {
        'success': true,
        'data': {
          'cardinfo': {
            'idserial': 'TEST-STUDENT-0001',
            'cardid': '285000999',
            'cardbal': '92.07',
            'accstatus': '1',
            'username': '合成用户',
            'pcode': '01',
          },
          'userInfo': <String, Object?>{},
        },
      });
    final repository = EcardCardRepository(
      transport,
      cache: SecureCardCache(
        InMemorySecureCredentialStore(),
        subjectReader: () async => 'subject-a',
        verifiedIdSerialReader: () async => 'TEST-STUDENT-0001',
      ),
      purgeLocalSecurityState: () async {},
      verifiedIdSerialReader: () async => 'TEST-STUDENT-0001',
    );

    final card = await repository.currentCard();

    expect(card, isNotNull);
    expect(card!.id, 'TEST-STUDENT-0001');
    expect(card.maskedNumber, '••••0001');
    expect(card.balance, const MoneyFen(9207));
    expect(card.status, CampusCardStatus.normal);
    expect(card.positionCode, '01');
    expect(card.positionName, '学生');
    expect(transport.requests.single.method, 'POST');
  });

  test('maps all 33 pcode identities and their configured limits', () {
    expect(CampusPositionCatalog.profiles, hasLength(33));
    expect(CampusPositionCatalog.fromCode('05')!.name, '在聘职工（教工）');
    expect(CampusPositionCatalog.fromCode('23')!.cardPerDayFen, 15000);
    expect(CampusPositionCatalog.fromCode('31')!.cardPerDayFen, 50000);
    expect(CampusPositionCatalog.fromCode('32')!.cardPerTransactionFen, 100000);
    expect(CampusPositionCatalog.fromCode('32')!.validityMonths, 120);
    expect(CampusPositionCatalog.fromCode('33')!.name, '附属学校学生');
  });

  test('returns the last verified card without waiting for the network',
      () async {
    var subject = 'synthetic-subject';
    var verifiedIdSerial = 'TEST-STUDENT-CACHED';
    final cache = SecureCardCache(
      InMemorySecureCredentialStore(),
      subjectReader: () async => subject,
      verifiedIdSerialReader: () async => verifiedIdSerial,
    );
    final online = FakeEcardTransport()
      ..enqueue('POST', '/myaccount/openMyAccountApp', {
        'success': true,
        'data': {
          'cardinfo': {
            'idserial': 'TEST-STUDENT-CACHED',
            'cardid': '285000777',
            'cardbal': '51.23',
            'accstatus': '1',
            'username': '缓存用户',
            'pcode': '01',
            'allowOfflineCode': '1',
          },
        },
      });
    final onlineRepository = EcardCardRepository(
      online,
      cache: cache,
      purgeLocalSecurityState: () async {},
      verifiedIdSerialReader: () async => verifiedIdSerial,
    );
    await onlineRepository.refreshCard();

    final offline = FakeEcardTransport();
    final offlineRepository = EcardCardRepository(
      offline,
      cache: cache,
      purgeLocalSecurityState: () async {},
      verifiedIdSerialReader: () async => verifiedIdSerial,
    );
    final cached = await offlineRepository.currentCard();

    expect(cached!.id, 'TEST-STUDENT-CACHED');
    expect(cached.balance, const MoneyFen(5123));
    expect(cached.offlineCodeAllowed, isTrue);
    expect(offline.requests, isEmpty);

    subject = 'different-subject';
    expect(await cache.read(), isNull);

    subject = 'synthetic-subject';
    verifiedIdSerial = 'OTHER-STUDENT';
    expect(await cache.read(), isNull);
  });

  test('discards a card response for another verified identity', () async {
    final cache = SecureCardCache(
      InMemorySecureCredentialStore(),
      subjectReader: () async => 'subject-a',
      verifiedIdSerialReader: () async => 'TEST-STUDENT-0001',
    );
    final transport = FakeEcardTransport()
      ..enqueue('POST', '/myaccount/openMyAccountApp', {
        'success': true,
        'data': {
          'cardinfo': {
            'idserial': 'OTHER-STUDENT',
            'cardid': 'OTHER-CARD',
            'cardbal': '10.00',
            'accstatus': '1',
            'username': '其他用户',
            'pcode': '01',
          },
        },
      });
    final repository = EcardCardRepository(
      transport,
      cache: cache,
      purgeLocalSecurityState: () async {},
      verifiedIdSerialReader: () async => 'TEST-STUDENT-0001',
    );

    await expectLater(
      repository.refreshCard(),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'CARD_RESPONSE_IDENTITY_MISMATCH',
        ),
      ),
    );
    expect(await cache.read(), isNull);
  });

  test('never returns a cached card after the verified student changes',
      () async {
    var verifiedIdSerial = 'TEST-STUDENT-0001';
    final cache = SecureCardCache(
      InMemorySecureCredentialStore(),
      subjectReader: () async => 'subject-a',
      verifiedIdSerialReader: () async => verifiedIdSerial,
    );
    await cache.write(
      const CampusCard(
        id: 'TEST-STUDENT-0001',
        maskedNumber: '••••0001',
        ownerName: '账户 A',
        balance: MoneyFen(100),
        status: CampusCardStatus.normal,
        positionName: '学生',
        offlineCodeAllowed: true,
      ),
    );

    verifiedIdSerial = 'TEST-STUDENT-0002';

    expect(await cache.read(), isNull);
  });
}
