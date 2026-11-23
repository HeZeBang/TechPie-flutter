import 'package:flutter/foundation.dart';

import '../models/student_allowance.dart';
import 'auth_service.dart';
import 'debug_logger.dart';
import 'session/session_tree.dart';
import 'student_allowance_client.dart';
import 'third_party_auth_service.dart';

export 'student_allowance_client.dart' show StudentAllowanceException;

enum StudentAllowanceAccess { signIn, bindIds, ready }

/// Adapts the shared IDS session to a finance query. No finance cookie or
/// result is retained by this service or by the session tree.
class StudentAllowanceService extends ChangeNotifier {
  StudentAllowanceService(
    this._auth,
    this._thirdParty, {
    StudentAllowanceClient? client,
    DebugLogger? logger,
  }) : _client = client ?? StudentAllowanceClient(logger: logger) {
    _owner = _currentOwner;
    _auth.addListener(_onOwnerChanged);
    _thirdParty.addListener(_onOwnerChanged);
  }

  final AuthService _auth;
  final ThirdPartyAuthService _thirdParty;
  final StudentAllowanceClient _client;
  late (String?, String?) _owner;
  int _revision = 0;

  (String?, String?) get _currentOwner => (
        _auth.session?.userId,
        _thirdParty.idsBinding?.credential?.credentialId,
      );

  /// Changes on logout or rebind, but not on an ordinary token renewal.
  int get accountRevision => _revision;

  StudentAllowanceAccess get access {
    if (!_auth.isLoggedIn) return StudentAllowanceAccess.signIn;
    if (!_thirdParty.hasIdsBinding) return StudentAllowanceAccess.bindIds;
    return StudentAllowanceAccess.ready;
  }

  void _onOwnerChanged() {
    final owner = _currentOwner;
    if (owner == _owner) return;
    _owner = owner;
    _revision++;
    notifyListeners();
  }

  Future<StudentAllowanceReport> query(StudentAllowancePeriod period) async {
    switch (access) {
      case StudentAllowanceAccess.signIn:
        throw const StudentAllowanceException(StudentAllowanceFailure.signIn);
      case StudentAllowanceAccess.bindIds:
        throw const StudentAllowanceException(StudentAllowanceFailure.bindIds);
      case StudentAllowanceAccess.ready:
        break;
    }

    final revision = _revision;
    void checkAccess() {
      if (_revision != revision || _currentOwner != _owner) {
        throw const StudentAllowanceException(StudentAllowanceFailure.accessChanged);
      }
    }

    final node = _thirdParty.idsNode;
    var idsRejected = false;
    final report =
        await _thirdParty.sessionTree.withCookie<StudentAllowanceReport?>(node, (cookie) async {
      checkAccess();
      try {
        final result = await _client.query(
          idsCookies: cookie.cookies,
          period: period,
          checkAccess: checkAccess,
        );
        checkAccess();
        return CookieAction(result, expired: false);
      } on StudentAllowanceException catch (error) {
        checkAccess();
        if (error.failure != StudentAllowanceFailure.idsSession) rethrow;
        // A rejected finance query is NOT evidence of an expired IDS ticket.
        // Only the IDS response may ask the shared session tree to renew once.
        idsRejected = true;
        return const CookieAction(null, expired: true);
      }
    });
    checkAccess();
    if (report == null) {
      throw StudentAllowanceException(
        idsRejected || node.lastRenewWasCredentialError
            ? StudentAllowanceFailure.idsSession
            : StudentAllowanceFailure.unavailable,
      );
    }
    return report;
  }

  @override
  void dispose() {
    _revision++;
    _auth.removeListener(_onOwnerChanged);
    _thirdParty.removeListener(_onOwnerChanged);
    _client.close();
    super.dispose();
  }
}
