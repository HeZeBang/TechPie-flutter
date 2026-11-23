import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/core/errors/app_failure.dart';
import 'package:techpie/features/campus_card/data/repositories/ecard_transaction_history_repository.dart';
import 'package:techpie/features/campus_card/domain/models/bill_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';

import '../support/fake_ecard_transport.dart';

void main() {
  test('validates calendar and clock values without changing time zones',
      () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
        'success': true,
        'resultData': {
          'rows': [
            for (final date in [
              '2026-02-30 12:34:56',
              '2026-13-10 12:34:56',
              '2026-10-10 24:00:00',
              '2026-10-10 12:60:00',
              '2026-10-10T12:34:56+08:60',
              '999999999999999999',
              '2024-02-29 12:34:56',
              '2026-10-10T00:30:00.123+08:00',
            ])
              {
                'id': date,
                'txdate': date,
                'txname': '消费',
                'mername': '合成餐饮公司',
                'txamt': '-100',
              },
          ],
        },
      });
    final page = await EcardTransactionHistoryRepository(
      transport,
      subjectReader: () async => 'synthetic-account',
    ).timelineRange();
    final valid = page.items.where((record) => record.hasValidDate).toList();
    expect(valid, hasLength(2));
    expect(
      valid.first.occurredAt,
      DateTime.utc(2026, 10, 9, 16, 30, 0, 123),
    );
    expect(page.items.every((record) => !record.isDining), isTrue);
    expect(page.items.last.details['txdate'], page.items.last.id);
  });

  test(
      'retains string identifiers, rejects conflicting fields and invalid dates',
      () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
        'success': true,
        'resultData': {
          'rows': [
            {
              'id': 'SYNTHETIC-ID',
              'merchantno': '000125',
              'poscode': '0238',
              'txdate': '2026-10-10 12:34:56',
              'txname': '餐饮消费',
              'txamt': '-100',
            },
            {
              'id': 'SYNTHETIC-ALT',
              'merno': '000126',
              'terminalno': '0238',
              'txdate': 'not-a-date',
              'txname': '补足信用额度',
              'txtype': '2',
              'txamt': '100',
            },
            {
              'id': 'SYNTHETIC-CONFLICT',
              'merchantno': 'a',
              'merchantid': 'b',
              'poscode': '-',
              'txname': '未知操作',
              'txamt': '0',
            },
          ],
        },
      });
    final page = await EcardTransactionHistoryRepository(
      transport,
      subjectReader: () async => 'synthetic-account',
    ).timelineRange();
    final records = {for (final record in page.items) record.id: record};
    expect(records['SYNTHETIC-ID']!.merchantId, '000125');
    expect(records['SYNTHETIC-ID']!.posCode, '0238');
    expect(records['SYNTHETIC-ID']!.isDining, isTrue);
    expect(records['SYNTHETIC-ID']!.hasValidDate, isTrue);
    expect(records['SYNTHETIC-ID']!.details['poscode'], '0238');
    expect(records['SYNTHETIC-ALT']!.merchantId, '000126');
    expect(records['SYNTHETIC-ALT']!.posCode, '0238');
    expect(records['SYNTHETIC-ALT']!.kind, TransactionKind.creditReplenishment);
    expect(records['SYNTHETIC-ALT']!.isHiddenFromHistory, isTrue);
    expect(isTransactionVisible(records['SYNTHETIC-ID']!), isTrue);
    expect(isTransactionVisible(records['SYNTHETIC-ALT']!), isFalse);
    expect(records['SYNTHETIC-ALT']!.hasValidDate, isFalse);
    expect(records['SYNTHETIC-CONFLICT']!.merchantId, isNull);
    expect(records['SYNTHETIC-CONFLICT']!.posCode, isNull);
    expect(records['SYNTHETIC-CONFLICT']!.kind, TransactionKind.adjustment);
    expect(records['SYNTHETIC-CONFLICT']!.hasValidDate, isFalse);
  });

  test(
    'maps a paged read-only transaction response and caches detail',
    () async {
      final transport = FakeEcardTransport()
        ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
          'success': true,
          'resultData': {
            'currentPage': 0,
            'totalpage': 2,
            'rows': [
              {
                'tradeno': 'SYNTHETIC-TX-1',
                'txdate': '2026-08-21 12:34:56',
                'txname': '校园餐饮',
                'txamt': '-1234',
                'balance': '88.76',
                'merchantname': '合成餐厅',
              },
            ],
          },
        });
      final repository = EcardTransactionHistoryRepository(
        transport,
        subjectReader: () async => 'subject-a',
      );

      final page = await repository.timeline(month: '2026-08', pageSize: 5);

      expect(page.items, hasLength(1));
      expect(page.hasMore, isTrue);
      expect(page.nextCursor, '1');
      expect(page.items.single.amount, const MoneyFen(-1234));
      expect(page.items.single.balance, const MoneyFen(8876));
      expect(page.items.single.kind, TransactionKind.consumption);
      expect((await repository.detail('SYNTHETIC-TX-1')).merchantName, '合成餐厅');
      expect(
        transport.requests.single.data,
        containsPair('starttime', '2026-08-01'),
      );
      expect(
        transport.requests.single.data,
        containsPair('endtime', '2026-09-01'),
      );
      expect(transport.requests.single.data, containsPair('tradeType', 0));
      expect(transport.requests.single.data, containsPair('pageNumber', 0));
    },
  );

  test('loads an unbounded paged feed and maps journo/txtype fields', () async {
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
        'success': true,
        'resultData': {
          'currentPage': 0,
          'totalpage': 2,
          'rows': [
            {
              'id': 'SYNTHETIC-JOURNO-1',
              'txdate': '2026-09-02 08:30:00',
              'txname': '充值',
              'mername': '校园卡线上充值',
              'txamt': '10000',
            },
          ],
        },
      });
    final repository = EcardTransactionHistoryRepository(
      transport,
      subjectReader: () async => 'subject-a',
    );

    final page = await repository.timelineRange(pageSize: 1);

    expect(page.items.single.id, 'SYNTHETIC-JOURNO-1');
    expect(page.items.single.kind, TransactionKind.recharge);
    expect(page.items.single.amount, const MoneyFen(10000));
    expect(page.items.single.details['txdate'], '2026-09-02 08:30:00');
    expect(page.hasMore, isTrue);
    expect(transport.requests.single.data, contains('beginDate'));
    expect(transport.requests.single.data, contains('endDate'));
    expect(transport.requests.single.data, containsPair('pageSize', 1));
    expect(transport.requests.single.data, containsPair('pageNumber', 0));
  });

  test(
    'returns an empty page for a successful response without resultData',
    () async {
      final transport = FakeEcardTransport()
        ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
          'success': true,
          'message': 'synthetic empty',
        });
      final page = await EcardTransactionHistoryRepository(
        transport,
        subjectReader: () async => 'subject-a',
      ).timeline(month: '2026-02');
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    },
  );

  test(
    'classifies service actions, balance carryover, and scan payment',
    () async {
      final transport = FakeEcardTransport()
        ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
          'success': true,
          'resultData': {
            'currentPage': 0,
            'totalpage': 1,
            'rows': [
              {
                'id': 'ACTION-1',
                'txdate': '2026-09-02 22:32:54',
                'txname': '持卡人修改消费限额',
                'mername': '持卡人修改消费限额',
                'txamt': '0',
              },
              {
                'id': 'CARRY-1',
                'txdate': '2026-08-31 22:34:55',
                'txname': '余额结转',
                'txamt': '9207',
              },
              {
                'id': 'SCAN-1',
                'txdate': '2026-09-02 13:57:09',
                'txname': '虚拟卡主扫支付',
                'mername': '合成场馆',
                'txamt': '-1',
              },
            ],
          },
        });

      final page = await EcardTransactionHistoryRepository(
        transport,
        subjectReader: () async => 'subject-a',
      ).timelineRange();

      final byId = {for (final record in page.items) record.id: record};
      expect(byId['ACTION-1']!.kind, TransactionKind.adjustment);
      expect(byId['CARRY-1']!.kind, TransactionKind.recharge);
      expect(byId['SCAN-1']!.kind, TransactionKind.consumption);
      expect(byId['CARRY-1']!.amount, const MoneyFen(9207));
    },
  );

  test('does not expose cached transaction detail across accounts', () async {
    var subject = 'subject-a';
    final transport = FakeEcardTransport()
      ..enqueue('GET', '/selftrade/queryCardSelfTradeList', {
        'success': true,
        'resultData': {
          'rows': [
            {
              'journo': 'ACCOUNT-A-TX',
              'txdate': '2026-09-02 08:30:00',
              'txname': '消费',
              'txamt': '-100',
            },
          ],
        },
      });
    final repository = EcardTransactionHistoryRepository(
      transport,
      subjectReader: () async => subject,
    );
    await repository.timelineRange();

    subject = 'subject-b';

    await expectLater(
      repository.detail('ACCOUNT-A-TX'),
      throwsA(
        isA<AppFailure>().having(
          (failure) => failure.code,
          'code',
          'TRANSACTION_DETAIL_NOT_CACHED',
        ),
      ),
    );
  });
}
