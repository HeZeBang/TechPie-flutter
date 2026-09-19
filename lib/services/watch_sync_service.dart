import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../features/campus_card/app/app_runtime.dart';
import '../features/campus_card/core/async_mutex.dart';
import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/data/repositories/ecard_card_repository.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../features/campus_card/domain/models/card_models.dart';
import '../features/campus_card/domain/models/offline_models.dart';
import '../features/campus_card/domain/ports/card_ports.dart';
import '../features/campus_card/domain/ports/credential_store.dart';

final class WatchSyncEvent {
  const WatchSyncEvent(
      {required this.at, required this.text, this.isError = false,});
  final DateTime at;
  final String text;
  final bool isError;
}

/// The phone remains the only authority for shared watch credentials and data.
final class WatchSyncService extends ChangeNotifier {
  WatchSyncService(this._runtime, this._session, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('techpie/watch');

  final AppRuntime _runtime;
  final SessionCredentialStore _session;
  final MethodChannel _channel;
  final _mutex = AsyncMutex();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _disposed = false;
  int _epoch = 0;
  bool busy = false;
  String? message;
  bool hasError = false;
  final List<WatchSyncEvent> _events = [];
  List<WatchSyncEvent> get events => List.unmodifiable(_events);
  Map<String, dynamic> status = {};
  bool get enabled => status['enabled'] == true;
  bool get ready => status['ready'] == true;
  bool get isAcknowledged =>
      status['revision'] is int &&
      (status['revision'] as int) > 0 &&
      status['revision'] == status['acknowledged'];

  void _record(String text, {bool error = false}) {
    if (_events.isNotEmpty &&
        _events.last.text == text &&
        _events.last.isError == error) {
      return;
    }
    _events.add(WatchSyncEvent(at: DateTime.now(), text: text, isError: error));
    if (_events.length > 20) _events.removeAt(0);
  }

  void _notice(String text, {bool error = false}) {
    message = text;
    hasError = error;
    // Upstream error wording is shown as the current actionable notice only;
    // the local event history never stores arbitrary server/credential content.
    _record(error ? '同步未完成' : text, error: error);
  }

  void initialize() {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'watchChanged') {
        await refreshStatus();
        unawaited(synchronize());
      }
    });
    _subscriptions.add(
      _runtime.auth.changes.listen((snapshot) {
        if (snapshot.reason == AuthChangeReason.userSignedOut ||
            snapshot.reason == AuthChangeReason.accountChanged) {
          unawaited(disable(reason: snapshot.reason!.name));
        } else if (snapshot.state == AuthState.authenticated) {
          unawaited(synchronize());
        } else if (snapshot.state != AuthState.signingIn && enabled) {
          _notice('校园卡会话暂未就绪，已保留手表授权');
          if (!_disposed) notifyListeners();
        }
      }),
    );
    _subscriptions.add(
      _runtime.offlinePayments.changes.listen((_) => unawaited(synchronize())),
    );
    final cards = _runtime.cards;
    if (cards is EcardCardRepository) {
      _subscriptions.add(cards.changes.listen((_) => unawaited(synchronize())));
    }
    unawaited(refreshStatus().then((_) => synchronize()));
  }

  Future<void> refreshStatus() async {
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('status');
      if (_disposed) return;
      final previousReceipt = status['acknowledged'];
      status = value ?? {};
      if (!enabled && status['revocationReason'] == 'peerChanged') {
        _notice('手表安装身份已变化，请重新开启手表授权', error: true);
      }
      if (enabled &&
          isAcknowledged &&
          status['acknowledged'] != previousReceipt) {
        _notice('手表已确认同步');
      }
      notifyListeners();
    } on MissingPluginException {
      // Other platforms do not initialize this service.
    } on PlatformException {
      if (!_disposed) {
        _notice('暂时无法读取 Apple Watch 状态', error: true);
        notifyListeners();
      }
    }
  }

  Future<void> enable() => synchronize(enroll: true, refresh: true);

  Future<void> disable({String reason = 'userRevoked'}) async {
    _epoch++;
    try {
      final value = await _channel.invokeMapMethod<String, dynamic>('disable', {'reason': reason});
      if (_disposed) return;
      status = value ?? {};
      _record('撤销手表授权：$reason');
      _notice('已取消授权，手表连接后会清除校园卡');
      notifyListeners();
    } on MissingPluginException {
      // No watch bridge on other platforms.
    } on PlatformException {
      if (!_disposed) {
        _notice('取消授权失败，请重试', error: true);
        notifyListeners();
      }
    }
  }

  Future<void> synchronize({bool enroll = false, bool refresh = false}) =>
      _mutex.protect(() async {
        if (_disposed) return;
        await refreshStatus();
        if (_disposed || (!enroll && !enabled)) return;
        if (enroll && !ready) {
          _notice('请先在已配对的 Apple Watch 上打开 TechPie', error: true);
          notifyListeners();
          return;
        }
        final epoch = _epoch;
        String? openID;
        String? verifiedID;
        try {
          openID = await _session.readOpenId();
          verifiedID = await _session.readVerifiedIdSerial();
        } catch (_) {
          _notice('请解锁手机后重新同步', error: true);
          if (!_disposed) notifyListeners();
          return;
        }
        if (openID == null) {
          _notice(enabled ? '校园卡账号暂未就绪，已保留手表授权' : '请先连接校园卡账号', error: true);
          if (!_disposed) notifyListeners();
          return;
        }
        final channel = await _session.readOpenIdChannel();
        final subject = channel.subjectId(openID);
        if (!enroll &&
            status['subject'] != null &&
            status['subject'] != subject) {
          await disable(reason: 'accountChanged');
          _notice('校园卡账号已变更，请重新开启手表授权', error: true);
          if (!_disposed) notifyListeners();
          return;
        }
        if (verifiedID == null) {
          _notice(enabled ? '正在等待校园卡身份恢复，已保留手表授权' : '请先在手机完成校园卡身份校验', error: true);
          if (!_disposed) notifyListeners();
          return;
        }
        final showProgress = enroll || refresh;
        if (showProgress) {
          busy = true;
          _record(enroll ? '正在准备手表授权' : '正在更新卡片与离线授权');
          notifyListeners();
        }
        try {
          final repository = _runtime.cards;
          final card = repository is CacheFirstCardRepository
              ? (refresh
                  ? await repository.refreshCard()
                  : await repository.readCachedCard() ?? await repository.refreshCard())
              : await repository.currentCard();
          if (card == null || card.id != verifiedID) {
            throw const AppFailure(
              FailureKind.credentialMissing,
              '请先在手机打开校园卡并更新卡片信息',
            );
          }
          if (refresh) {
            final grant =
                await _runtime.offlinePayments.mostRecentAuthorization();
            if (grant != null && grant.cardId == card.id) {
              // Keep a still-valid local authorization on transient renewal failure.
              try {
                await _runtime.offlinePayments.renew(card.id);
              } on AppFailure catch (error) {
                if (!error.permitsCachedFallback) rethrow;
              }
            }
          }
          // A valid existing offline grant authorizes presentation. The API's
          // allowOfflineCode flag is not used by the phone's offline generator.
          final grant = card.status.permitsPayment
              ? await _runtime.offlinePayments.exportForWatch(card.id)
              : null;
          var grantStatus = grant == null ? 'cardUnavailable' : 'ready';
          if (grant == null && card.status.permitsPayment) {
            final view = await _runtime.offlinePayments.status(card.id);
            grantStatus = view.authorization == null ||
                    view.state == OfflineAuthorizationState.missingCredential
                ? 'missing'
                : view.authorization!.isLimited
                    ? 'limited'
                    : view.authorization!.expiresOn == null
                        ? 'missingExpiry'
                        : view.state == OfflineAuthorizationState.expired
                            ? 'expired'
                            : 'changed';
          }
          if (_disposed ||
              epoch != _epoch ||
              await _session.readOpenId() != openID ||
              await _session.readOpenIdChannel() != channel ||
              await _session.readVerifiedIdSerial() != verifiedID) {
            return;
          }
          final previousRevision = status['revision'];
          final value =
              await _channel.invokeMapMethod<String, dynamic>('publish', {
            'enroll': enroll,
            'grantStatus': grantStatus,
            'subject': subject,
            'card': {
              'name': card.ownerName,
              'studentID': card.id,
              'balanceFen': card.balance.value,
              'updatedAt': card.updatedAt == null
                  ? null
                  : card.updatedAt!.millisecondsSinceEpoch / 1000,
              'permitsPayment': card.status.permitsPayment,
            },
            'credential': grant?.toMessage(),
          });
          if (_disposed || epoch != _epoch) return;
          status = value ?? {};
          if (!enabled) {
            _notice('校园卡账号已变更，请重新开启手表授权', error: true);
            return;
          }
          if (!showProgress && hasError && status['revision'] == previousRevision) return;
          _notice(grant == null
              ? '卡片信息已发送；请在手机开通或续期离线授权后同步'
              : isAcknowledged
                  ? '手表已确认同步'
                  : '已发送，等待手表确认',);
        } on AppFailure catch (error) {
          _notice(error.safeMessage, error: true);
        } on PlatformException catch (error) {
          _notice(
              switch (error.code) {
                'WATCH_SYNC_SESSION' => '手表配对状态尚未就绪，请保持两端 TechPie 打开后重试',
                'WATCH_SYNC_ENCODE' ||
                'WATCH_SYNC_DECODE' =>
                  '手表授权数据格式不匹配，请更新手机应用',
                'WATCH_SYNC_VALIDATE' => '离线授权数据校验失败，请在手机更新校园卡授权后重试',
                'WATCH_SYNC_PERSIST' ||
                'WATCH_STORAGE_UNAVAILABLE' =>
                  '无法保存手表授权，请解锁手机后重试',
                _ => '同步失败，请在手表打开 TechPie 后重试',
              },
              error: true,);
        } on MissingPluginException {
          _notice('当前设备不支持 Apple Watch', error: true);
        } catch (_) {
          _notice('暂时无法同步校园卡，请重试', error: true);
        } finally {
          if (showProgress) busy = false;
          if (!_disposed) notifyListeners();
        }
      });

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      _channel.setMethodCallHandler(null);
    }
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    super.dispose();
  }
}
