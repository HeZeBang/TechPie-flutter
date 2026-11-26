import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../storage_service.dart';
import 'campus_errors.dart';
import 'campus_session.dart';

/// Stores only feature-selected fields. Account changes invalidate outstanding
/// operations and remove the previous owner's persisted snapshot.
class EmapAccountCache extends ChangeNotifier {
  EmapAccountCache(this.feature, this.storage, this.identity, this.accounts) {
    accounts.addListener(_update);
    _update();
  }

  final String feature;
  final StorageService storage;
  final CampusIdentity Function() identity;
  final Listenable accounts;
  CampusIdentity? _owner;
  int _revision = 0;
  int get revision => _revision;
  bool _disposed = false;
  Map<String, dynamic> values = {};

  bool get ready => _owner?.ids != null && _owner?.user != null;

  void _update() {
    final next = identity();
    if (next == _owner) return;
    _owner = next;
    _revision++;
    values = {};
    final raw = storage.readEmapCache(feature);
    if (raw != null) {
      try {
        final stored = jsonDecode(raw);
        if (ready &&
            stored is Map<String, dynamic> &&
            stored['user'] == next.user &&
            stored['ids'] == next.ids &&
            stored['values'] is Map<String, dynamic>) {
          values = stored['values'] as Map<String, dynamic>;
        } else {
          unawaited(storage.writeEmapCache(feature, null));
        }
      } catch (_) {
        unawaited(storage.writeEmapCache(feature, null));
      }
    }
    notifyListeners();
  }

  void check(int expected) {
    if (_disposed) throw CampusRequestException.expired;
    _update();
    if (!ready || expected != revision) throw CampusRequestException.expired;
  }

  Future<void> save(int expected, String key, Object value) async {
    check(expected);
    values[key] = value;
    await storage.writeEmapCache(
      feature,
      jsonEncode({
        'user': _owner!.user,
        'ids': _owner!.ids,
        'values': values,
      }),
    );
    check(expected);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    accounts.removeListener(_update);
    super.dispose();
  }
}
