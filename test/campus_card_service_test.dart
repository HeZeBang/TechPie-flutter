import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/data/storage/flutter_secure_credential_store.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/credential_store.dart';
import 'package:techpie/services/campus_card_service.dart';

void main() {
  test('OPENID check does not save, while update verifies and stores it',
      () async {
    const openId = 'SYNTHETIC_OPENID_0123456789ABCDEF';
    final secureStore = InMemorySecureCredentialStore();
    final sessionStore = SecureSessionCredentialStore(secureStore);
    final auth = _VerifyingAuthPort(sessionStore);
    addTearDown(auth.dispose);
    final base = await buildDemoRuntime();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: base.cards,
      paymentCodes: base.paymentCodes,
      scanPayments: base.scanPayments,
      transactions: base.transactions,
      securitySettings: base.securitySettings,
      offlinePayments: base.offlinePayments,
      brightness: base.brightness,
      connectivity: base.connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
      disposeRuntime: base.dispose,
    );
    final service = CampusCardService.withStore(
      secureStore,
      runtimeFactory: () => runtime,
    );
    addTearDown(service.dispose);

    await service.verifyOpenId(openId);

    expect(auth.verifyCalls, 1);
    expect(await service.readOpenId(), isNull);
    expect(service.configured, isFalse);

    await service.connect(openId);

    expect(auth.signInCalls, 1);
    expect(await service.readOpenId(), openId);
    expect(service.configured, isTrue);
    await service.connect(openId, channel: EcardOpenIdChannel.alipay);
    expect(await sessionStore.readOpenIdChannel(), EcardOpenIdChannel.alipay);
    expect(service.openIdChannel, EcardOpenIdChannel.alipay);
    expect((await service.readSyncBinding())!.channel, EcardOpenIdChannel.alipay);
  });
}

final class _VerifyingAuthPort implements AuthPort, OpenIdAuthVerifier {
  _VerifyingAuthPort(this._sessionStore);

  final SessionCredentialStore _sessionStore;
  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);
  int verifyCalls = 0;
  int signInCalls = 0;

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() => restore();

  @override
  Future<AuthSnapshot> restore() async {
    final openId = await _sessionStore.readOpenId();
    return openId == null
        ? const AuthSnapshot(state: AuthState.signedOut)
        : _authenticated(openId);
  }

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async {
    final openIdCredential = credential as OpenIdAuthCredential;
    await verifyOpenId(openIdCredential.openId, channel: openIdCredential.channel);
    signInCalls += 1;
    await _sessionStore.writeSession(
      sessionCookie: 'JSESSIONID=synthetic',
      openId: openIdCredential.openId,
      orgId: '2',
      verifiedIdSerial: 'SYNTHETIC-STUDENT',
      verifiedCardId: 'SYNTHETIC-CARD',
      channel: openIdCredential.channel,
    );
    final snapshot = _authenticated(openIdCredential.openId);
    _changes.add(snapshot);
    return snapshot;
  }

  @override
  Future<void> verifyOpenId(String openId, {EcardOpenIdChannel channel = EcardOpenIdChannel.wechat}) async {
    OpenIdAuthCredential(openId: openId).validate();
    verifyCalls += 1;
  }

  @override
  Future<void> signOut() async {
    await _sessionStore.clear();
    _changes.add(const AuthSnapshot(state: AuthState.signedOut));
  }

  AuthSnapshot _authenticated(String openId) => const AuthSnapshot(
        state: AuthState.authenticated,
        session: AuthSession(
          subjectId: 'synthetic',
          orgId: '2',
          maskedIdentity: 'SYNT****CDEF',
        ),
      );

  Future<void> dispose() => _changes.close();
}
