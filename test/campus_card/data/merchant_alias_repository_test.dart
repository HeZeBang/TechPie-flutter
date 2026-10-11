import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:techpie/features/campus_card/data/repositories/merchant_alias_repository.dart';
import 'package:techpie/features/campus_card/domain/models/merchant_alias_models.dart';

Map<String, Object?> entry(
  String merchant, {
  String? pos,
  String alias = 'Synthetic cafeteria',
  bool enabled = true,
}) =>
    {
      'merchantId': merchant,
      if (pos != null) 'posCode': pos,
      'alias': alias,
      'verifiedAt': '2026-10-11',
      'evidence': 'Synthetic test data',
      'enabled': enabled,
      'category': 'dining',
    };

String config(
  List<Map<String, Object?>> entries, {
  int version = 1,
  int schema = 1,
}) =>
    jsonEncode({
      'schemaVersion': schema,
      'version': version,
      'updatedAt': '2026-10-11T00:00:00Z',
      'entries': entries,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled verified pairs remain usable before endpoint deployment',
      () async {
    final repository = MerchantAliasRepository(
      cache: _Cache(null),
      bundledConfigReader: () =>
          rootBundle.loadString(MerchantAliasRepository.bundledConfigAsset),
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    final directory = repository.current;
    expect(directory.version, 5);
    expect(directory.entries, hasLength(9));
    expect(directory.resolve('243000125', '0238')!.alias, '丝路二楼 · 米粉');
    expect(directory.resolve('243000125', '0237')!.alias, '丝路二楼 · 炸鸡');
    expect(directory.resolve('243000125', '0235')!.alias, '丝路二楼 · 煲仔饭');
    expect(directory.resolve('243000481', '0302')!.alias, '校内全家');
    expect(directory.resolve('243000481', '0305')!.alias, '校内全家');
    expect(directory.resolve('243000161', '0213')!.alias, '尚科二楼 · 滑蛋饭窗口');
    expect(directory.resolve('243000161', '0209')!.alias, '尚科二楼 · 铁板窗口');
    expect(directory.resolve('243000381', '0310')!.alias, '白玉兰一楼 · 麻辣香锅');
    expect(directory.resolve('243000381', '0315')!.alias, '白玉兰一楼 · 港式烧腊窗口');
    for (final pair in [
      ('243000125', '0235'),
      ('243000481', '0302'),
      ('243000481', '0305'),
      ('243000161', '0213'),
      ('243000161', '0209'),
      ('243000381', '0310'),
      ('243000381', '0315'),
    ]) {
      expect(directory.resolve('SYNTHETIC-OTHER', pair.$2), isNull);
      expect(directory.resolve(pair.$1, pair.$2.substring(1)), isNull);
      expect(directory.resolve(pair.$1, null), isNull);
    }
    expect(directory.resolve('243000125', '0239'), isNull);
    expect(directory.resolve('SYNTHETIC-OTHER', '0238'), isNull);
    expect(directory.resolve('243000125', '238'), isNull);
    expect(directory.resolve('243000125', null), isNull);
  });

  test('newer remote removal persists and does not resurrect bundled aliases',
      () async {
    final cache = _Cache(null);
    Future<String> readBundle() async => config([entry('A')], version: 2);
    final repository = MerchantAliasRepository(
      cache: cache,
      bundledConfigReader: readBundle,
      client:
          MockClient((_) async => http.Response(config([], version: 3), 200)),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    expect(repository.current.version, 3);
    expect(repository.current.resolve('A', null), isNull);

    final nextLaunch = MerchantAliasRepository(
      cache: cache,
      bundledConfigReader: readBundle,
      client: MockClient((_) async => http.Response('offline', 503)),
    );
    addTearDown(nextLaunch.dispose);
    await nextLaunch.initialize();
    expect(nextLaunch.current.version, 3);
    expect(nextLaunch.current.resolve('A', null), isNull);
  });

  test('invalid bundled config preserves valid cache', () async {
    final repository = MerchantAliasRepository(
      cache: _Cache(config([entry('A')])),
      bundledConfigReader: () async => 'invalid json',
      client: MockClient((_) async => http.Response('offline', 503)),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    expect(repository.current.resolve('A', null), isNotNull);
  });

  test('matches composite identity first and preserves leading zeros', () {
    final directory = MerchantAliasConfig.decode(
      config([
        entry('SYNTHETIC-A'),
        entry('SYNTHETIC-A', pos: '0238', alias: 'Synthetic stall'),
        entry('SYNTHETIC-B', pos: '0238', alias: 'Other stall'),
      ]),
    );
    expect(directory.resolve('SYNTHETIC-A', '0238')!.alias, 'Synthetic stall');
    expect(
      directory.resolve('SYNTHETIC-A', '0239')!.alias,
      'Synthetic cafeteria',
    );
    expect(directory.resolve('SYNTHETIC-B', '0238')!.alias, 'Other stall');
    expect(directory.resolve('SYNTHETIC-B', '238'), isNull);
    expect(directory.resolve('SYNTHETIC-C', '0238'), isNull);
    expect(directory.resolve(null, '0238'), isNull);
    expect(
      MerchantAliasConfig.decode(directory.encode())
          .resolve('SYNTHETIC-A', '0238')!
          .posCode,
      '0238',
    );
  });

  test('duplicates, conflicts and disabled keys cannot fall through to aliases',
      () {
    final directory = MerchantAliasConfig.decode(
      config([
        entry('A'),
        entry('A', pos: '0238'),
        entry('A', pos: '0238'),
        entry('B', pos: '0238'),
        entry('B', pos: '0238', alias: 'Conflict'),
        entry('C'),
        entry('C', pos: '0238', enabled: false),
        entry('D', enabled: false),
        entry('D', pos: '0238'),
      ]),
    );
    for (final merchant in ['A', 'B', 'C', 'D']) {
      expect(directory.resolve(merchant, '0238'), isNull);
    }
    expect(directory.resolve('A', '0239'), isNotNull);
  });

  test('rejects unsupported schema and invalid entries as a whole', () {
    for (final source in [
      config([], schema: 2),
      config([], version: 0),
      jsonEncode({
        'schemaVersion': 1.0,
        'version': 1,
        'updatedAt': '2026-10-11T00:00:00Z',
        'entries': <Object?>[],
      }),
      for (final date in [
        '2026-02-30T00:00:00Z',
        '2026-10-11T24:00:00Z',
        '2026-10-11T00:00:00+25:00',
      ])
        jsonEncode({
          'schemaVersion': 1,
          'version': 1,
          'updatedAt': date,
          'entries': <Object?>[],
        }),
      config([
        {...entry('A'), 'merchantId': 123},
      ]),
      config([
        {...entry('A'), 'posCode': 238},
      ]),
      config([
        {...entry('A'), 'verifiedAt': '2026-02-30'},
      ]),
      config([
        {...entry('A'), 'evidence': ''},
      ]),
      config([
        {...entry('A'), 'category': 'unverified-place'},
      ]),
    ]) {
      expect(() => MerchantAliasConfig.decode(source), throwsFormatException);
    }
  });

  test(
      'publishes cache before network finishes and refreshes without credentials',
      () async {
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    final cache = _Cache(config([entry('A')], version: 2));
    final repository = MerchantAliasRepository(
      cache: cache,
      client: MockClient((request) {
        expect(request.url, MerchantAliasRepository.endpoint);
        expect(request.headers.keys, isNot(contains('authorization')));
        expect(request.headers.keys, isNot(contains('cookie')));
        requested.complete();
        return pending.future;
      }),
    );
    addTearDown(repository.dispose);
    final initialization = repository.initialize();
    await requested.future;
    expect(repository.current.version, 2);
    expect(repository.current.resolve('A', null), isNotNull);
    pending.complete(http.Response(config([entry('B')], version: 3), 200));
    await initialization;
    expect(repository.current.version, 3);
    expect(repository.current.resolve('A', null), isNull);
    expect(MerchantAliasConfig.decode(cache.value!).version, 3);
  });

  test('failure, bad schema and older versions preserve valid cache', () async {
    var attempt = 0;
    final cache = _Cache(config([entry('A')], version: 5));
    final repository = MerchantAliasRepository(
      cache: cache,
      client: MockClient((request) async {
        switch (attempt++) {
          case 0:
            throw Exception('offline');
          case 1:
            return http.Response(config([], version: 6, schema: 99), 200);
          case 2:
            return http.Response(config([], version: 4), 200);
          default:
            return http.Response('unavailable', 503);
        }
      }),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    for (var i = 0; i < 3; i++) {
      await repository.refresh();
    }
    expect(repository.current.version, 5);
    expect(repository.current.resolve('A', null), isNotNull);
    expect(MerchantAliasConfig.decode(cache.value!).version, 5);
  });

  test('invalid cache and failed endpoint yield an empty directory', () async {
    final repository = MerchantAliasRepository(
      cache: _Cache('bad json'),
      client: MockClient((_) async => http.Response('not found', 404)),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    expect(repository.current.version, 0);
  });

  test('valid remote config remains usable if persistence fails', () async {
    final repository = MerchantAliasRepository(
      cache: _Cache(null, failWrite: true),
      client: MockClient((_) async => http.Response(config([entry('A')]), 200)),
    );
    addTearDown(repository.dispose);
    await repository.initialize();
    expect(repository.current.resolve('A', null), isNotNull);
  });
}

final class _Cache implements MerchantAliasCache {
  _Cache(this.value, {this.failWrite = false});
  String? value;
  final bool failWrite;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String source) async {
    if (failWrite) throw StateError('unavailable');
    value = source;
  }
}
