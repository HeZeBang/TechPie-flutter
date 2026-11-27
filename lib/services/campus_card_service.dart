import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../features/campus_card/app/app_runtime.dart';
import '../features/campus_card/app/real_runtime_factory.dart';
import '../features/campus_card/core/async_mutex.dart';
import '../features/campus_card/core/config/app_environment.dart';
import '../features/campus_card/core/errors/app_failure.dart';
import '../features/campus_card/core/errors/core_error_catalog.dart';
import '../features/campus_card/data/auth/ecard_openid_auth_port.dart';
import '../features/campus_card/data/auth/geekpie_ecard_session_issuer.dart';
import '../features/campus_card/data/crypto/sm2_offline_crypto.dart';
import '../features/campus_card/data/storage/flutter_secure_credential_store.dart';
import '../features/campus_card/domain/models/auth_models.dart';
import '../features/campus_card/domain/models/card_models.dart';
import '../features/campus_card/domain/money_fen.dart';
import '../features/campus_card/domain/ports/auth_port.dart';
import '../features/campus_card/domain/ports/card_ports.dart';
import '../features/campus_card/domain/ports/credential_store.dart';
import '../models/ecard_sync_binding.dart';
import 'api_base_url.dart';
import 'campus_card_http_trace.dart';
import 'debug_logger.dart';
import 'storage_service.dart';
import 'watch_sync_service.dart';

typedef CampusCardRuntimeFactory = AppRuntime Function();

/// Owns the campus-card runtime and its independent OpenID account.
///
/// TechPie keeps this service alive for the process lifetime so camera,
/// connectivity, and authentication adapters are not recreated for every
/// page visit. Only presentation state is rebuilt when a route is opened.
final class CampusCardService extends ChangeNotifier implements EcardSyncStore {
  CampusCardService({DebugLogger? debugLogger, StorageService? storage})
      : this.withStore(
          FlutterSecureCredentialStore(),
          debugLogger: debugLogger,
          storage: storage,
        );

  CampusCardService.withStore(
    SecureCredentialStore secureStore, {
    CampusCardRuntimeFactory? runtimeFactory,
    DebugLogger? debugLogger,
    StorageService? storage,
  })  : _secureStore = secureStore,
        _storage = storage,
        _sessionStore = SecureSessionCredentialStore(secureStore),
        _runtimeFactory = runtimeFactory,
        _debugLogger = debugLogger {
    // Deliberately nothing here. This constructor runs inside `main`, before
    // `runApp`, and the runtime it used to build is a whole feature: its own
    // Dio, the request cipher, the e-card session issuer and the watch sync.
    // Building it on first use moves all of that off the splash — the first use
    // being the warm-up the boot fires once the first frame is up.
  }

  AppRuntime get _runtime => _runtimeInstance ??= _startRuntime();

  AppRuntime _startRuntime() {
    final watch = Stopwatch()..start();
    Uri sessionEndpoint() => Uri.parse(
      '${_storage == null ? prodApiBaseUrl : apiBaseUrl(_storage)}/auth/third-party/ecard',
    );
    Uri merchantAliasesEndpoint() => Uri.parse(
      '${_storage == null ? prodApiBaseUrl : apiBaseUrl(_storage)}/campus-card/merchant-aliases.json',
    );
    final runtime = _runtimeFactory?.call() ??
        buildRealRuntime(
          AppEnvironment.production,
          secureCredentialStore: _secureStore,
          sessionIssuer: GeekPieEcardSessionIssuer(endpoint: sessionEndpoint),
          merchantAliasesEndpoint: merchantAliasesEndpoint,
          httpTrace: _debugLogger == null
              ? null
              : campusCardHttpTrace(_debugLogger),
        );
    unawaited(CoreErrorCatalog.initialize());
    watchSync = WatchSyncService(runtime, _sessionStore, sessionEndpoint: sessionEndpoint)..initialize();
    _authSubscription = runtime.auth.changes.listen((_) {
      unawaited(refreshAccount());
    });
    final cards = runtime.cards;
    if (cards is CardSnapshotSource) {
      _cardSubscription = (cards as CardSnapshotSource).snapshots.listen(_applyCachedCard);
    }
    if (cards is CacheFirstCardRepository) {
      unawaited(_hydrateCachedCard(cards));
    }
    if (kDebugMode) {
      debugPrint('[ecard] runtime built ${watch.elapsedMilliseconds}ms');
    }
    return runtime;
  }

  final CampusCardRuntimeFactory? _runtimeFactory;
  final DebugLogger? _debugLogger;
  AppRuntime? _runtimeInstance;

  final SecureCredentialStore _secureStore;
  final StorageService? _storage;
  final _bindingMutex = AsyncMutex();
  static const _bindingKey = 'geekpay.auth.sync.binding';
  Future<void> Function()? onBindingChanged;

  Future<String> _syncDeviceId() async {
    if (_storage != null) return _storage.ensureDeviceId();
    const key = 'geekpay.auth.sync.device';
    final existing = await _secureStore.read(key);
    if (existing != null) return existing;
    final random = Random.secure();
    final value = List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    await _secureStore.write(key, value);
    return value;
  }

  Future<Map<String, Object?>> generateOfflinePaymentImage() async {
    try {
      final authorization =
          await _runtime.offlinePayments.mostRecentAuthorization();
      if (authorization == null) {
        return {'error': '未开通离线支付授权'};
      }
      final code = await _runtime.offlinePayments.generate(authorization.cardId);
      const size = 180.0;
      final painter = QrPainter(
        data: code.payload,
        version: QrVersions.auto,
        gapless: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, size, size),
        ui.Paint()..color = const ui.Color(0xFFFFFFFF),
      );
      painter.paint(canvas, const ui.Size(size, size));
      final image = await recorder
          .endRecording()
          .toImage(size.toInt(), size.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) return {'error': '二维码生成失败'};
      return {
        'png': base64Encode(data.buffer.asUint8List()),
        'generatedAt': code.generatedAt.millisecondsSinceEpoch,
      };
    } on AppFailure catch (failure) {
      return {'error': failure.safeMessage};
    } catch (_) {
      return {'error': '离线码生成失败'};
    }
  }

  /// 为手环导出离线签名凭证：手环本地做 SM2 签名生成消费码。
  /// 私钥经穿戴通道下发，仅在手环本地签名使用；不要把返回值写入日志。
  Future<Map<String, Object?>> exportOfflineCredentialForBand() async {
    try {
      final authorization =
          await _runtime.offlinePayments.mostRecentAuthorization();
      if (authorization == null) {
        return {'t': 'offline.cred', 'error': '未开通离线支付授权'};
      }
      final cred = await _runtime.offlinePayments.exportForWatch(
        authorization.cardId,
      );
      if (cred == null) {
        return {'t': 'offline.cred', 'error': '离线授权不可用，请联网续期'};
      }
      final coords = Sm2OfflineCrypto.publicKeyCoordinates(cred.privateKey);
      return {
        't': 'offline.cred',
        'cardID': cred.authorization.cardId,
        'privateKey': cred.privateKey,
        'pubX': coords.x,
        'pubY': coords.y,
        'authorInfo': cred.authorization.authorInfo,
        'checksum': cred.deviceChecksum,
        'expiresAt':
            (cred.authorization.expiresOn ?? DateTime.now().toUtc())
                .millisecondsSinceEpoch /
            1000,
        'totalUses': cred.authorization.totalUses,
      };
    } catch (_) {
      return {'t': 'offline.cred', 'error': '离线凭证导出失败'};
    }
  }

  @override
  Future<EcardSyncBinding?> readSyncBinding() async {
    final raw = await _secureStore.read(_bindingKey);
    if (raw != null) {
      try {
        final binding = EcardSyncBinding.fromJson(jsonDecode(raw));
        if (binding != null) return binding;
      } on FormatException {
        // Rebuild optional sync metadata from the authoritative local parameter.
      }
    }
    final openId = await _sessionStore.readOpenId();
    if (openId == null) return null;
    // Migration does not make an old local binding newer than a remote edit.
    final binding = EcardSyncBinding(openId: openId, channel: await _sessionStore.readOpenIdChannel(), updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      deviceId: await _syncDeviceId(),);
    await _secureStore.write(_bindingKey, jsonEncode(binding.toJson()));
    return binding;
  }

  Future<void> _recordBinding(String? openId) async {
    final previous = await readSyncBinding();
    var now = DateTime.now().toUtc();
    if (previous != null && !now.isAfter(previous.updatedAt)) {
      now = previous.updatedAt.add(const Duration(microseconds: 1));
    }
    final binding = EcardSyncBinding(openId: openId, channel: await _sessionStore.readOpenIdChannel(), updatedAt: now, deviceId: await _syncDeviceId());
    await _secureStore.write(_bindingKey, jsonEncode(binding.toJson()));
    // Sync failures do not undo a successful local account change.
    try { await onBindingChanged?.call(); } catch (_) {}
  }

  @override
  Future<void> applySyncBinding(EcardSyncBinding? binding) => _bindingMutex.protect(() async {
    if (binding == null) return;
    final local = await readSyncBinding();
    final winner = binding.merge(local);
    if (local != null && jsonEncode(local.toJson()) == jsonEncode(winner.toJson())) return;
    final currentOpenId = await _sessionStore.readOpenId();
    if (currentOpenId != winner.openId || await _sessionStore.readOpenIdChannel() != winner.channel) {
      if (winner.openId == null) {
        await _runtime.auth.signOut();
      } else {
        final auth = _runtime.auth;
        if (auth is! EcardOpenIdAuthPort) throw StateError('eCard sync requires the real auth adapter');
        await auth.importOpenId(winner.openId!, channel: winner.channel);
      }
    }
    await _secureStore.write(_bindingKey, jsonEncode(winner.toJson()));
    await refreshAccount();
  });

  final SecureSessionCredentialStore _sessionStore;
  late final WatchSyncService watchSync;

  StreamSubscription<AuthSnapshot>? _authSubscription;
  StreamSubscription<CampusCard?>? _cardSubscription;
  String? _maskedOpenId;
  MoneyFen? _cachedBalance;
  String? _cachedOwnerName;
  EcardOpenIdChannel _channel = EcardOpenIdChannel.wechat;
  EcardOpenIdChannel get openIdChannel => _channel;
  bool _busy = false;
  Object? _lastError;

  bool get busy => _busy;
  bool get configured => _maskedOpenId != null;
  String? get maskedOpenId => _maskedOpenId;
  MoneyFen? get cachedBalance => configured ? _cachedBalance : null;
  String? get cachedOwnerName => configured ? _cachedOwnerName : null;
  Object? get lastError => _lastError;
  AppRuntime get runtime => _runtime;

  void _applyCachedCard(CampusCard? card) {
    final balance = card?.balance;
    final trimmedOwner = card?.ownerName.trim() ?? '';
    final ownerName = trimmedOwner.isEmpty ? null : trimmedOwner;
    if (_cachedBalance == balance && _cachedOwnerName == ownerName) return;
    _cachedBalance = balance;
    _cachedOwnerName = ownerName;
    notifyListeners();
  }

  Future<void> _hydrateCachedCard(CacheFirstCardRepository cards) async {
    try {
      final cached = await cards.readCachedCard();
      if (cached != null) _applyCachedCard(cached);
    } catch (_) {
      // Optional home balance & name preview degrades cleanly when cache is unavailable.
    }
  }

  Future<void> refreshAccount() async {
    final openId = await _sessionStore.readOpenId();
    final masked = _maskOpenId(openId);
    final channel = await _sessionStore.readOpenIdChannel();
    final clearedBalance = masked == null && _cachedBalance != null;
    final clearedOwnerName = masked == null && _cachedOwnerName != null;
    if (_maskedOpenId == masked &&
        _channel == channel &&
        !clearedBalance &&
        !clearedOwnerName) {
      return;
    }
    _channel = channel;
    _maskedOpenId = masked;
    if (masked == null) {
      _cachedBalance = null;
      _cachedOwnerName = null;
    }
    notifyListeners();
  }

  /// Builds the runtime, so opening a pass does not pay for it. Called after the
  /// first frame: the constructor runs inside `main`, and building a whole
  /// feature there would hold up the splash.
  ///
  /// Deliberately *not* a session warm-up. A request that needs a session issues
  /// one itself, and doing it here meant fetching a session the user might never
  /// ask for while holding the session lock — so opening the pass waited on a
  /// round trip nobody requested.
  void prepare() => _runtime;

  Future<String?> readOpenId() => _sessionStore.readOpenId();
  Future<EcardOpenIdChannel> readOpenIdChannel() => _sessionStore.readOpenIdChannel();

  Future<void> verifyOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) async {
    final credential = OpenIdAuthCredential(openId: openId.trim(), channel: channel);
    credential.validate();
    _setBusy(true);
    _lastError = null;
    try {
      final auth = _runtime.auth;
      if (auth is! OpenIdAuthVerifier) {
        throw StateError('The active eCard runtime cannot verify OPENID');
      }
      await (auth as OpenIdAuthVerifier).verifyOpenId(credential.openId, channel: credential.channel);
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> connect(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) => _bindingMutex.protect(() => _connect(openId, channel));

  Future<void> _connect(String openId, EcardOpenIdChannel channel) async {
    final credential = OpenIdAuthCredential(openId: openId.trim(), channel: channel);
    credential.validate();
    _setBusy(true);
    _lastError = null;
    try {
      await _runtime.auth.signIn(credential);
      await refreshAccount();
      await _recordBinding(credential.openId);
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  Future<void> disconnect() => _bindingMutex.protect(_disconnect);

  Future<void> _disconnect() async {
    _setBusy(true);
    _lastError = null;
    try {
      await _runtime.auth.signOut();
      await refreshAccount();
      await _recordBinding(null);
    } catch (error) {
      _lastError = error;
      rethrow;
    } finally {
      _setBusy(false);
    }
  }

  void _setBusy(bool value) {
    if (_busy == value) return;
    _busy = value;
    notifyListeners();
  }

  static String? _maskOpenId(String? value) {
    final openId = value?.trim();
    if (openId == null || openId.isEmpty) return null;
    if (openId.length <= 8) return '••••';
    return '${openId.substring(0, 4)}••••${openId.substring(openId.length - 4)}';
  }

  @override
  void dispose() {
    // A service that was never used never built its runtime; there is nothing
    // to unwind in that case.
    final runtime = _runtimeInstance;
    if (runtime != null) {
      watchSync.dispose();
      unawaited(runtime.dispose());
    }
    unawaited(_authSubscription?.cancel());
    _authSubscription = null;
    unawaited(_cardSubscription?.cancel());
    _cardSubscription = null;
    super.dispose();
  }
}
