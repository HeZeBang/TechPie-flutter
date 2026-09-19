import 'dart:convert';

import '../../core/errors/app_failure.dart';
import '../../domain/models/card_models.dart';
import '../../domain/money_fen.dart';
import '../../domain/ports/credential_store.dart';

typedef CardCacheSubjectReader = Future<String?> Function();
typedef CardCacheIdSerialReader = Future<String?> Function();

/// Stores the last verified eCard snapshot for one hashed OpenID subject.
final class SecureCardCache {
  SecureCardCache(
    this._store, {
    required CardCacheSubjectReader subjectReader,
    required CardCacheIdSerialReader verifiedIdSerialReader,
  })  : _subjectReader = subjectReader,
        _verifiedIdSerialReader = verifiedIdSerialReader;

  static const _key = 'geekpay.card.snapshot.v2';
  static const _legacyKey = 'geekpay.card.snapshot.v1';

  final SecureCredentialStore _store;
  final CardCacheSubjectReader _subjectReader;
  final CardCacheIdSerialReader _verifiedIdSerialReader;

  Future<CampusCard?> read() async {
    await _discardLegacyCache();
    final subjectId = await _subjectReader();
    final verifiedIdSerial = await _verifiedIdSerialReader();
    if (subjectId == null ||
        subjectId.isEmpty ||
        verifiedIdSerial == null ||
        verifiedIdSerial.isEmpty) {
      return null;
    }
    final raw = await _store.read(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value['version'] != 2 ||
          value['subjectId'] != subjectId) {
        throw const FormatException();
      }
      final id = value['id'] as String;
      final maskedNumber = value['maskedNumber'] as String;
      if (id != verifiedIdSerial || maskedNumber.isEmpty) {
        throw const FormatException();
      }
      final statusName = value['status'] as String;
      final status = CampusCardStatus.values.firstWhere(
        (candidate) => candidate.name == statusName,
      );
      if (await _subjectReader() != subjectId ||
          await _verifiedIdSerialReader() != verifiedIdSerial) {
        return null;
      }
      return CampusCard(
        id: id,
        maskedNumber: maskedNumber,
        ownerName: value['ownerName'] as String,
        balance: MoneyFen(value['balanceFen'] as int),
        status: status,
        positionName: value['positionName'] as String,
        positionCode: value['positionCode'] as String?,
        offlineCodeAllowed: value['offlineCodeAllowed'] as bool,
        schoolName: value['schoolName'] as String?,
        departmentName: value['departmentName'] as String?,
        validUntil: _date(value['validUntil']),
        lastTransactionAt: _date(value['lastTransactionAt']),
        accountType: value['accountType'] as String?,
        detailsAvailable: value['detailsAvailable'] as bool? ?? true,
        updatedAt: _date(value['cachedAt']),
      );
    } catch (_) {
      try {
        await _store.delete(_key);
      } catch (_) {
        // A corrupt optional cache must not block authentication or payment.
      }
      return null;
    }
  }

  Future<void> write(CampusCard card,
      {String? expectedSubjectId,
      Future<void> Function()? validateContext,}) async {
    final subjectId = await _subjectReader();
    final verifiedIdSerial = await _verifiedIdSerialReader();
    if (subjectId == null ||
        subjectId.isEmpty ||
        verifiedIdSerial == null ||
        verifiedIdSerial.isEmpty) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '无法确认卡片缓存所属账户。',
        code: 'CARD_CACHE_SUBJECT_MISSING',
      );
    }
    if (expectedSubjectId != null && subjectId != expectedSubjectId) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '请求期间校园卡账户已变化。',
        code: 'CARD_CACHE_IDENTITY_MISMATCH',
      );
    }
    if (card.id != verifiedIdSerial) {
      throw const AppFailure(
        FailureKind.authenticationExpired,
        '卡片信息与当前已验证账户不一致，已拒绝缓存。',
        code: 'CARD_CACHE_IDENTITY_MISMATCH',
      );
    }
    await validateContext?.call();
    await _store.write(
      _key,
      jsonEncode({
        'version': 2,
        'subjectId': subjectId,
        'id': card.id,
        'maskedNumber': card.maskedNumber,
        'ownerName': card.ownerName,
        'balanceFen': card.balance.value,
        'status': card.status.name,
        'positionName': card.positionName,
        'positionCode': card.positionCode,
        'offlineCodeAllowed': card.offlineCodeAllowed,
        'schoolName': card.schoolName,
        'departmentName': card.departmentName,
        'validUntil': card.validUntil?.toUtc().toIso8601String(),
        'lastTransactionAt': card.lastTransactionAt?.toUtc().toIso8601String(),
        'accountType': card.accountType,
        'detailsAvailable': card.detailsAvailable,
        'cachedAt': card.updatedAt?.toUtc().toIso8601String(),
      }),
    );
  }

  Future<void> clear() => _store.deleteAll({_key, _legacyKey});

  Future<void> _discardLegacyCache() async {
    try {
      await _store.delete(_legacyKey);
    } catch (_) {
      // An unscoped legacy cache is never used, even if deletion fails.
    }
  }

  static DateTime? _date(Object? value) {
    final source = value as String?;
    return source == null ? null : DateTime.tryParse(source);
  }
}
