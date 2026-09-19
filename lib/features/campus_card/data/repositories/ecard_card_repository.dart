import 'dart:async';
import 'dart:typed_data';

import '../../core/async_mutex.dart';
import '../../core/errors/app_failure.dart';
import '../../domain/models/card_models.dart';
import '../../domain/models/profile_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/card_ports.dart';
import '../api/ecard_api_client.dart';
import '../storage/secure_card_cache.dart';

typedef LocalSecurityPurge = Future<void> Function();
typedef VerifiedCardIdSerialReader = Future<String?> Function();

final class EcardCardRepository implements CacheFirstCardRepository, CardSnapshotSource {
  EcardCardRepository(
    this._client, {
    required SecureCardCache cache,
    required LocalSecurityPurge purgeLocalSecurityState,
    required VerifiedCardIdSerialReader verifiedIdSerialReader,
  })  : _cache = cache,
        _purgeLocalSecurityState = purgeLocalSecurityState,
        _verifiedIdSerialReader = verifiedIdSerialReader;

  final EcardTransport _client;
  final SecureCardCache _cache;
  final LocalSecurityPurge _purgeLocalSecurityState;
  final VerifiedCardIdSerialReader _verifiedIdSerialReader;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  final _snapshots = StreamController<CampusCard?>.broadcast();
  @override
  Stream<CampusCard?> get snapshots => _snapshots.stream;
  final _snapshotMutex = AsyncMutex();
  CampusCard? _latestSnapshot;
  String? _snapshotSubject;
  int _balanceOrder = -1;
  MoneyFen? _latestBalance;
  Future<void> dispose() async {
    await _changes.close();
    await _snapshots.close();
  }

  String _subject(Object? response, String id) =>
      response is EcardResponseMap ? response.session.subjectId : id;

  void _selectSubject(String subject) {
    if (_snapshotSubject == subject) return;
    _snapshotSubject = subject;
    _latestSnapshot = null;
    _latestBalance = null;
    _balanceOrder = -1;
  }

  Future<void> _saveSnapshot(CampusCard card, Object? response) async {
    try {
      await _cache.write(card,
        expectedSubjectId: response is EcardResponseMap ? response.session.subjectId : null,
        validateContext: () => validateEcardResponse(response),);
    } catch (_) {
      // Verified data can still update the UI when local persistence fails.
    }
    await validateEcardResponse(response);
    _latestSnapshot = card;
    if (!_snapshots.isClosed) _snapshots.add(card);
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<bool> acceptCodeBalance(Map<String, Object?> response, MoneyFen balance) =>
      _snapshotMutex.protect(() async {
    var changed = false;
    await commitEcardResponse(response, () async {
      final data = response['data'] is Map ? response['data'] as Map : response;
      final id = data['idserial']?.toString() ??
          (response is EcardResponseMap ? response.session.identity?.idSerial : null);
      if (id == null) return;
      await _assertVerifiedIdSerial(id);
      _selectSubject(_subject(response, id));
      final order = response is EcardResponseMap ? response.responseOrder : _balanceOrder + 1;
      if (order < _balanceOrder) return;
      final card = _latestSnapshot ?? await _cache.read();
      final previous = _latestBalance ?? card?.balance;
      changed = previous != null && previous != balance;
      _latestBalance = balance;
      _balanceOrder = order;
      if (card != null && card.id == id) {
        _latestSnapshot = card;
        if (card.balance != balance) await _saveSnapshot(card.withBalance(balance), response);
      }
    });
    return changed;
  });

  @override
  Future<CampusCard?> currentCard() async =>
      await readCachedCard() ?? refreshCard();

  @override
  Future<CampusCard?> readCachedCard() => _cache.read();

  @override
  Future<CampusCard?> refreshCard() async {
    final account = await _account();
    await validateEcardResponse(account);
    final rawCard = account['cardinfo'];
    if (rawCard == null) {
      return _snapshotMutex.protect(() async {
        CampusCard? result;
        await commitEcardResponse(account, () async {
          final id = await _verifiedIdSerialReader();
          _selectSubject(_subject(account, id ?? ''));
          final order = account is EcardResponseMap ? account.responseOrder : _balanceOrder + 1;
          if (order < _balanceOrder) { result = _latestSnapshot; return; }
          await _clearCacheBestEffort();
          _latestSnapshot = null;
          _latestBalance = null;
          _balanceOrder = order;
          if (!_snapshots.isClosed) _snapshots.add(null);
          if (!_changes.isClosed) _changes.add(null);
        });
        return result;
      });
    }
    final card = requireObjectMap(rawCard, context: 'CARD_INFO');
    final user = account['userInfo'] is Map
        ? requireObjectMap(account['userInfo'], context: 'CARD_USER_INFO')
        : const <String, Object?>{};
    final id = card['idserial']?.toString() ?? '';
    final positionCode = card['pcode']?.toString().trim();
    final displayCardNumber = id;
    if (id.isEmpty) {
      await commitEcardResponse(account, _clearCacheBestEffort);
      return null;
    }
    await _assertVerifiedIdSerial(id);
    final result = CampusCard(
      id: id,
      maskedNumber: maskCardNumber(displayCardNumber),
      ownerName:
          card['username']?.toString() ?? user['username']?.toString() ?? '',
      balance: MoneyFen.fromApiYuan(card['cardbal'] ?? 0, field: 'cardbal'),
      updatedAt: DateTime.now().toUtc(),
      status: CampusCardStatusRules.fromApi(
        card['accstatusStr'] ?? card['accstatus'],
      ),
      positionName: CampusPositionCatalog.displayName(
        positionCode,
        fallback: card['pname']?.toString(),
      ),
      positionCode: positionCode,
      offlineCodeAllowed: card['allowOfflineCode']?.toString() == '1',
      schoolName: card['schoolname']?.toString(),
      departmentName: card['departname']?.toString(),
      validUntil: _parseCardDate(card['effectdate']),
      lastTransactionAt: _parseCardDate(card['lasttxdate']),
      accountType: card['acctype']?.toString(),
    );
    return _snapshotMutex.protect(() async {
      late CampusCard accepted;
      await commitEcardResponse(account, () async {
        await _assertVerifiedIdSerial(id);
        _selectSubject(_subject(account, id));
        final order = account is EcardResponseMap ? account.responseOrder : _balanceOrder + 1;
        if (order < _balanceOrder && _latestBalance != null) {
          accepted = _latestSnapshot ?? result.withBalance(_latestBalance!);
        } else {
          accepted = result;
          _latestBalance = result.balance;
          _balanceOrder = order;
        }
        await _saveSnapshot(accepted, account);
      });
      return accepted;
    });
  }

  @override
  Future<UserProfile> profile() async {
    try {
      final account = await _account();
      final card = requireObjectMap(
        account['cardinfo'],
        context: 'PROFILE_CARD',
      );
      final user = account['userInfo'] is Map
          ? requireObjectMap(account['userInfo'], context: 'PROFILE_USER')
          : const <String, Object?>{};
      final id = card['idserial']?.toString() ?? '';
      await _assertVerifiedIdSerial(id);
      final displayCardNumber = id;
      Uint8List? avatar;
      if (id.isNotEmpty) {
        final avatarFlag = requireObjectMap(
          await _client.get('/home/userImageIsexists', {'idserial': id}),
          context: 'AVATAR_FLAG',
        );
        if (avatarFlag['photoIsOrNot'] == true) {
          avatar = Uint8List.fromList(
            await _client.download(
              '/repair/showImage?filename=${Uri.encodeQueryComponent('$id.jpg')}',
            ),
          );
        }
      }
      await _assertVerifiedIdSerial(id);
      await validateEcardResponse(account);
      return UserProfile(
        displayName: card['username']?.toString() ??
            user['username']?.toString() ??
            '校园用户',
        maskedCardNumber: maskCardNumber(displayCardNumber),
        positionName: CampusPositionCatalog.displayName(
          card['pcode'],
          fallback: card['pname']?.toString(),
        ),
        avatarBytes: avatar,
      );
    } on AppFailure catch (failure) {
      if (!failure.permitsCachedFallback) rethrow;
      final cached = await _cache.read();
      if (cached == null) rethrow;
      return UserProfile(
        displayName: cached.ownerName.isEmpty ? '校园用户' : cached.ownerName,
        maskedCardNumber: cached.maskedNumber,
        positionName: cached.positionName,
      );
    }
  }

  @override
  Future<BindCardResult> bind(BindCardCommand command) async {
    command.validate();
    final response = requireObjectMap(
      await _client.post('/bind/wechatBind', {
        'idserial': command.cardNumber,
        'cardpwd': command.queryPassword,
        'identityno': command.identityNumber,
        'identitytype': command.identityType.apiCode,
        'tel': command.phoneNumber,
        'usertype': '8',
        'idtype': '1',
      }),
      context: 'CARD_BIND',
    );
    if (!apiSuccess(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '卡片绑定失败。'),
        code: 'CARD_BIND_REJECTED',
      );
    }
    final result = response['resultData'] is Map
        ? requireObjectMap(response['resultData'], context: 'CARD_BIND_RESULT')
        : const <String, Object?>{};
    return BindCardResult(
      offlineCodeAllowed: result['allowOfflineCode']?.toString() == '1',
    );
  }

  @override
  Future<void> unbind({required String cardPassword}) async {
    if (!RegExp(r'^\d{6}$').hasMatch(cardPassword)) {
      throw const AppFailure(
        FailureKind.invalidInput,
        '卡片查询密码必须为 6 位数字。',
        code: 'CARD_PASSWORD_INVALID',
      );
    }
    final init = requireObjectMap(
      await _client.post('/bind/opencancelBind', const {}),
      context: 'CARD_UNBIND_INIT',
    );
    if (apiRejected(init)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(init, fallback: '无法初始化解绑流程。'),
        code: 'CARD_UNBIND_INIT_REJECTED',
      );
    }
    final data = init['data'] is Map
        ? requireObjectMap(init['data'], context: 'CARD_UNBIND_INIT_DATA')
        : init;
    final id = data['idserial']?.toString() ?? '';
    final username = data['username']?.toString() ?? '';
    if (id.isEmpty || username.isEmpty) {
      throw const AppFailure(
        FailureKind.protocol,
        '服务未返回解绑所需的卡片信息。',
        code: 'CARD_UNBIND_FIELDS_MISSING',
      );
    }
    await _assertVerifiedIdSerial(id);
    final response = requireObjectMap(
      await _client.post('/bind/cancelBind', {
        'idserial': id,
        'username': username,
        'cardpwd': cardPassword,
        'usertype': '8',
      }),
      context: 'CARD_UNBIND',
    );
    if (!apiSuccess(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '卡片解绑失败。'),
        code: 'CARD_UNBIND_REJECTED',
      );
    }
    await _purgeLocalSecurityState();
  }

  Future<Map<String, Object?>> _account() async {
    final response = requireObjectMap(
      await _client.post('/myaccount/openMyAccountApp', const {}),
      context: 'ACCOUNT',
    );
    if (apiRejected(response)) {
      throw AppFailure(
        FailureKind.server,
        apiMessage(response, fallback: '个人信息加载失败。'),
        code: 'ACCOUNT_REJECTED',
        retryable: true,
      );
    }
    return response['data'] is Map
        ? requireObjectMap(response['data'], context: 'ACCOUNT_DATA')
        : response;
  }

  Future<void> _clearCacheBestEffort() async {
    try {
      await _cache.clear();
    } catch (_) {
      // The validated server state remains authoritative for this process.
    }
  }

  Future<void> _assertVerifiedIdSerial(String idSerial) async {
    final expected = await _verifiedIdSerialReader();
    if (expected == null || expected.isEmpty) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '登录身份尚未完成校验。',
        code: 'CARD_VERIFIED_IDENTITY_MISSING',
      );
    }
    if (idSerial != expected) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '服务端返回了其他账户的卡片信息，已丢弃本次响应。',
        code: 'CARD_RESPONSE_IDENTITY_MISMATCH',
      );
    }
  }
}

DateTime? _parseCardDate(Object? value) {
  final source = value?.toString().trim();
  if (source == null || source.isEmpty) return null;
  return DateTime.tryParse(source.replaceFirst(' ', 'T'));
}

String maskCardNumber(String value) {
  if (value.isEmpty) return '';
  final visible = value.length <= 4 ? value : value.substring(value.length - 4);
  return '••••$visible';
}
