import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth_service.dart';
import '../session/session_node.dart';
import '../third_party_auth_service.dart';
import 'campus_session.dart';
import 'eams_client.dart';
import 'elearning_client.dart';
import 'emap_client.dart';

/// Application-scoped clients; derived cookies and caches live only in memory.
class CampusClients {
  CampusClients(
    this.auth,
    this.bindings, {
    VoidCallback? onAccountChanged,
    EamsRequestQueue? eamsQueue,
  }) : _onAccountChanged = onAccountChanged {
    CampusSession session(String origin, SessionNode node) => CampusSession(
          Uri.parse(origin),
          _dio,
          <T>(action) => bindings.sessionTree.withCookie<T>(node, action),
          _currentIdentity,
        );
    _lastIdentity = _currentIdentity();
    emap = EmapClient(session('https://egate.shanghaitech.edu.cn', bindings.egateAppNode));
    eams = EamsClient(
      session('https://eams.shanghaitech.edu.cn', bindings.eamsNode),
      queue: eamsQueue,
    );
    elearning = ElearningClient(
      session('https://elearning.shanghaitech.edu.cn:8443', bindings.elearningNode),
    );
    auth.addListener(_accountChanged);
    bindings.addListener(_accountChanged);
  }

  final AuthService auth;
  final ThirdPartyAuthService bindings;
  final VoidCallback? _onAccountChanged;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  late final EmapClient emap;
  late final EamsClient eams;
  late final ElearningClient elearning;
  late CampusIdentity _lastIdentity;

  CampusIdentity _currentIdentity() => (
        user: auth.session?.userId,
        ids: bindings.hasIdsBinding ? bindings.idsAccount?.account : null,
      );

  void _accountChanged() {
    for (final session in [emap.session, eams.session, elearning.session]) {
      session.accountChanged();
    }
    final next = _currentIdentity();
    if (next != _lastIdentity) {
      _lastIdentity = next;
      _onAccountChanged?.call();
    }
  }

  void dispose() {
    auth.removeListener(_accountChanged);
    bindings.removeListener(_accountChanged);
    for (final session in [emap.session, eams.session, elearning.session]) {
      session.reset();
    }
    _dio.close(force: true);
  }
}
