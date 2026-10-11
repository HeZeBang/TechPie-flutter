import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/merchant_alias_models.dart';
import '../../domain/ports/merchant_alias_port.dart';

abstract interface class MerchantAliasCache {
  Future<String?> read();
  Future<void> write(String source);
}

final class SharedPreferencesMerchantAliasCache implements MerchantAliasCache {
  static const key = 'geekpay.merchantAliases.v1';

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String source) async {
    await (await SharedPreferences.getInstance()).setString(key, source);
  }
}

final class MerchantAliasRepository implements MerchantAliasPort {
  MerchantAliasRepository({
    http.Client? client,
    MerchantAliasCache? cache,
    Future<String> Function()? bundledConfigReader,
    this.timeout = const Duration(seconds: 8),
  })  : _client = client ?? http.Client(),
        _cache = cache ?? SharedPreferencesMerchantAliasCache(),
        _bundledConfigReader = bundledConfigReader;

  static const bundledConfigAsset =
      'assets/campus_card/data/merchant_aliases.json';
  static final endpoint = Uri.https(
    'techpie.geekpie.club',
    '/api/campus-card/merchant-aliases.json',
  );
  final http.Client _client;
  final MerchantAliasCache _cache;
  final Future<String> Function()? _bundledConfigReader;
  final Duration timeout;
  final _changes = StreamController<MerchantAliasConfig>.broadcast(sync: true);
  MerchantAliasConfig _current = const MerchantAliasConfig.empty();
  Future<void>? _initialization;
  Future<void>? _refreshing;
  bool _disposed = false;

  @override
  MerchantAliasConfig get current => _current;

  @override
  Stream<MerchantAliasConfig> get changes => _changes.stream;

  Future<void> initialize() => _initialization ??= _initialize();

  Future<void> _initialize() async {
    try {
      final cached = await _cache.read();
      if (cached != null && !_disposed) {
        final config = MerchantAliasConfig.decode(cached);
        if (config.version > _current.version) _publish(config);
      }
    } catch (_) {
      // A corrupt or unavailable optional cache does not affect transactions.
    }
    final readBundle = _bundledConfigReader;
    if (readBundle != null && !_disposed) {
      try {
        final bundled = MerchantAliasConfig.decode(await readBundle());
        if (bundled.version > _current.version) _publish(bundled);
      } catch (_) {
        // A missing or invalid bundle never replaces a validated snapshot.
      }
    }
    if (!_disposed) await refresh();
  }

  Future<void> refresh() =>
      _refreshing ??= _refresh().whenComplete(() => _refreshing = null);

  Future<void> _refresh() async {
    try {
      // This public configuration client never receives account credentials.
      final response = await _client.get(endpoint).timeout(timeout);
      if (response.statusCode != 200 || _disposed) return;
      final next = MerchantAliasConfig.decode(utf8.decode(response.bodyBytes));
      if (next.version <= _current.version) return;
      _publish(next);
      try {
        await _cache.write(next.encode());
      } catch (_) {/* Keep the in-memory config. */}
    } catch (_) {
      // Retain the last validated configuration, including on timeout.
    }
  }

  void _publish(MerchantAliasConfig config) {
    if (_disposed) return;
    _current = config;
    _changes.add(config);
  }

  Future<void> dispose() async {
    _disposed = true;
    _client.close();
    await _changes.close();
  }
}
