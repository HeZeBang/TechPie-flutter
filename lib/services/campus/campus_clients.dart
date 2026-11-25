import 'package:dio/dio.dart';

import '../auth_service.dart';
import '../session/session_node.dart';
import '../third_party_auth_service.dart';
import 'campus_session.dart';
import 'eams_client.dart';
import 'elearning_client.dart';
import 'emap_client.dart';

/// Application-scoped clients; derived cookies and caches live only in memory.
class CampusClients {
  CampusClients(this.auth, this.bindings) {
    CampusSession session(String origin, SessionNode node) => CampusSession(
          Uri.parse(origin),
          _dio,
          <T>(action) => bindings.sessionTree.withCookie<T>(node, action),
          () => (
            user: auth.session?.userId,
            ids: bindings.hasIdsBinding ? bindings.idsAccount?.account : null
          ),
        );
    emap = EmapClient(session('https://egate.shanghaitech.edu.cn', bindings.egateAppNode));
    eams = EamsClient(session('https://eams.shanghaitech.edu.cn', bindings.eamsNode));
    elearning = ElearningClient(
      session('https://elearning.shanghaitech.edu.cn:8443', bindings.elearningNode),
    );
    auth.addListener(_accountChanged);
    bindings.addListener(_accountChanged);
  }
  final AuthService auth;
  final ThirdPartyAuthService bindings;
  final _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
    ),
  );
  late final EmapClient emap;
  late final EamsClient eams;
  late final ElearningClient elearning;

  void _accountChanged() {
    for (final session in [emap.session, eams.session, elearning.session]) {
      session.accountChanged();
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
