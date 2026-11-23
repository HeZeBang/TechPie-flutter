import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/campus_card/data/storage/flutter_secure_credential_store.dart';
import '../features/campus_card/domain/models/bill_models.dart';
import '../features/campus_card/domain/ports/bill_ports.dart';
import '../utils/platform.dart';
import 'auth_service.dart';
import 'campus_card_service.dart';
import 'storage_service.dart';

/// Opaque scope for notifications; credentials never cross the notification channel.
class SpendingIdentity {
  const SpendingIdentity({required this.owner, required this.subjectId});
  final String owner;
  final String subjectId;
}

typedef SpendingIdentityReader = Future<SpendingIdentity?> Function();

/// Full snapshots reach one native ledger shared by foreground/background engines.
/// The first snapshot is a baseline, not a batch of historical receipts.
final class SpendingAlertService extends ChangeNotifier implements SpendingAlertPort {
  SpendingAlertService(
    this._storage, {
    MethodChannel? channel,
    SpendingIdentityReader? identityReader,
  })  : _channel = channel ?? const MethodChannel('techpie/spending_alerts'),
        _identityReader = identityReader;

  final StorageService _storage;
  final MethodChannel _channel;
  final SpendingIdentityReader? _identityReader;
  AuthService? _auth;
  CampusCardService? _card;
  bool _disposed = false;
  int _configurationRevision = 0;

  bool get supported => isAndroid();
  bool get enabled => supported && _storage.spendingAlertsEnabled;

  Future<SpendingIdentity?> _identity() async {
    if (!_storage.privacyAccepted || (_auth != null && !_auth!.isLoggedIn)) return null;
    if (_identityReader != null) return _identityReader();
    final primary = await _storage.loadSession();
    if (primary == null) return null;
    final store = SecureSessionCredentialStore(FlutterSecureCredentialStore());
    final openId = await store.readOpenId();
    if (openId == null || openId.isEmpty) return null;
    final subject = (await store.readOpenIdChannel()).subjectId(openId);
    final owner = sha256.convert(utf8.encode(jsonEncode([primary.userId, subject]))).toString();
    return SpendingIdentity(owner: owner, subjectId: subject);
  }

  void start(AuthService auth, CampusCardService card) {
    if (!supported || _auth != null) return;
    _auth = auth;
    _card = card;
    auth.addListener(_accountChanged);
    card.addListener(_accountChanged);
    unawaited(synchronize());
  }

  void _accountChanged() => unawaited(synchronize());

  /// Native configure is idempotent for the same owner, and invalidates in-flight
  /// reads plus clears visible receipts on disable, sign-out or account change.
  Future<void> synchronize() async {
    if (!supported || _disposed) return;
    final revision = ++_configurationRevision;
    try {
      final identity = enabled ? await _identity() : null;
      if (_disposed || revision != _configurationRevision) return;
      await _channel.invokeMethod<bool>('configure', {'owner': identity?.owner});
    } catch (_) {
      // Notification setup must never prevent the normal card/account flow.
    }
  }

  Future<void> setEnabled(bool value) async {
    if (!supported || _disposed) return;
    await _storage.setSpendingAlertsEnabled(value);
    if (_disposed) return;
    notifyListeners();
    await synchronize();
    if (value && enabled && !_disposed) {
      try {
        await _channel.invokeMethod<bool>('requestPermission',);
      } on PlatformException {
        // The system notification setting remains authoritative.
      } on MissingPluginException {
        // Tests and other platform hosts have no Android bridge.
      }
    }
  }

  Future<Map<Object?, Object?>?> _status() => _channel.invokeMapMethod<Object?, Object?>('status');

  @override
  Future<void> observeTransactions(List<TransactionRecord> records,
      {required String subjectId,}) async {
    if (!enabled || _disposed) return;
    try {
      final identity = await _identity();
      if (identity == null || identity.subjectId != subjectId) return;
      final status = await _status();
      if (status == null || status['owner'] != identity.owner) return;
      await _submit(identity, status, records);
    } catch (_) {
      // A notification failure is separate from payment and ledger success.
    }
  }

  Future<void> _submit(
    SpendingIdentity identity,
    Map<Object?, Object?> status,
    List<TransactionRecord> records,
  ) async {
    if (_disposed || !enabled) return;
    final current = await _identity();
    if (current?.owner != identity.owner) return;
    await _channel.invokeMethod<bool>('observe', {
      'owner': identity.owner,
      'generation': status['generation'],
      'records': records
          .take(50)
          .map(
            (record) => {
              'key': sha256.convert(utf8.encode(record.id)).toString(),
              'at': record.occurredAt.millisecondsSinceEpoch,
              'spending': record.kind == TransactionKind.consumption,
              'title': '消费提醒',
              'body': _body(record),
            },
          )
          .toList(),
    });
  }

  /// Called only by WorkManager. Capture native generation before I/O so a
  /// disable/re-enable during the request cannot turn old results into news.
  Future<bool> refreshInBackground(Future<List<TransactionRecord>> Function() load) async {
    if (!supported) return true;
    try {
      await _storage.reloadNotificationPreferences();
      if (!enabled || !_storage.privacyAccepted) return true;
      final identity = await _identity();
      final status = await _status();
      if (identity == null || status == null || status['owner'] != identity.owner) return true;
      final records = await load();
      await _storage.reloadNotificationPreferences();
      await _submit(identity, status, records);
      return true;
    } catch (_) {
      return false;
    }
  }

  static String _body(TransactionRecord record) {
    final amount = record.amount.toYuanFixed();
    final merchant = record.merchantName ?? record.location ?? record.title;
    return [
      amount.startsWith('-') ? amount : '-$amount',
      if (merchant.isNotEmpty) merchant,
      if (record.balance != null) '余额 ${record.balance!.toYuanFixed()}',
    ].join(' · ');
  }

  @override
  void dispose() {
    _disposed = true;
    _configurationRevision++;
    _auth?.removeListener(_accountChanged);
    _card?.removeListener(_accountChanged);
    super.dispose();
  }
}
