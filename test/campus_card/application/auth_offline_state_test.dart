import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/features/campus_card/app/app_providers.dart';
import 'package:techpie/features/campus_card/app/app_runtime.dart';
import 'package:techpie/features/campus_card/app/demo_runtime_factory.dart';
import 'package:techpie/features/campus_card/core/config/offline_authorization_banner_controller.dart';
import 'package:techpie/features/campus_card/data/mock/in_memory_ports.dart';
import 'package:techpie/features/campus_card/domain/models/auth_models.dart';
import 'package:techpie/features/campus_card/domain/models/card_models.dart';
import 'package:techpie/features/campus_card/domain/models/offline_models.dart';
import 'package:techpie/features/campus_card/domain/models/profile_models.dart';
import 'package:techpie/features/campus_card/domain/money_fen.dart';
import 'package:techpie/features/campus_card/domain/ports/auth_port.dart';
import 'package:techpie/features/campus_card/domain/ports/card_ports.dart';

void main() {
  test(
    'logout clears cached offline state and resets the dismissed banner',
    () async {
      SharedPreferences.setMockInitialValues({});
      final runtime = await buildDemoRuntime();
      final container = ProviderContainer(
        overrides: [appRuntimeProvider.overrideWithValue(runtime)],
      );
      addTearDown(() async {
        container.dispose();
        await runtime.dispose();
      });

      await container.read(authControllerProvider.future);
      await container
          .read(authControllerProvider.notifier)
          .signIn(const DemoAuthCredential());
      final card = await container.read(cardControllerProvider.future);
      expect(card, isNotNull);
      expect(
        (await container.read(
          offlineAuthorizationProvider(card!.id).future,
        ))
            .state,
        OfflineAuthorizationState.active,
      );
      await container
          .read(offlineAuthorizationBannerDismissedProvider.notifier)
          .dismiss();
      container.read(manualOfflineModeProvider.notifier).setEnabled(true);

      await container.read(authControllerProvider.notifier).signOut();

      expect(
        await container.read(
          offlineAuthorizationBannerDismissedProvider.future,
        ),
        isFalse,
      );
      expect(container.read(manualOfflineModeProvider), isFalse);
      expect(
        (await container.read(
          offlineAuthorizationProvider(card.id).future,
        ))
            .state,
        OfflineAuthorizationState.missingCredential,
      );

      await container
          .read(authControllerProvider.notifier)
          .signIn(const DemoAuthCredential());
      expect(
        (await container.read(
          offlineAuthorizationProvider(card.id).future,
        ))
            .state,
        OfflineAuthorizationState.missingCredential,
      );
    },
  );

  test('restores locally first and revalidates when connectivity returns',
      () async {
    final base = await buildDemoRuntime();
    final auth = _CountingAuthPort();
    final connectivity = InMemoryConnectivityPort(online: false);
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
      connectivity: connectivity,
      lifecycle: base.lifecycle,
      feedback: base.feedback,
      scanner: base.scanner,
      disposeRuntime: () async {
        await auth.dispose();
        await base.dispose();
      },
    );
    final container = ProviderContainer(
      overrides: [appRuntimeProvider.overrideWithValue(runtime)],
    );
    addTearDown(() async {
      container.dispose();
      await runtime.dispose();
    });

    final local = await container.read(authControllerProvider.future);

    expect(local.state, AuthState.authenticated);
    expect(auth.localRestoreCalls, 1);
    expect(auth.serverRestoreCalls, 0);

    await Future<void>.delayed(Duration.zero);
    expect(auth.serverRestoreCalls, 1);

    connectivity.setOnline(true);
    await Future<void>.delayed(Duration.zero);
    expect(auth.serverRestoreCalls, 2);
  });

  test('an account subject change invalidates the visible card state',
      () async {
    final base = await buildDemoRuntime();
    final auth = _CountingAuthPort();
    final cards = _SubjectCardRepository();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: cards,
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
      disposeRuntime: () async {
        await auth.dispose();
        await base.dispose();
      },
    );
    final container = ProviderContainer(
      overrides: [appRuntimeProvider.overrideWithValue(runtime)],
    );
    addTearDown(() async {
      container.dispose();
      await runtime.dispose();
    });

    await container.read(authControllerProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect((await container.read(cardControllerProvider.future))!.id, 'CARD-A');

    cards.subject = 'B';
    auth.switchSubject('subject-b');
    await Future<void>.delayed(Duration.zero);

    expect((await container.read(cardControllerProvider.future))!.id, 'CARD-B');
    expect(cards.currentCardCalls, 2);
  });

  test('an old background refresh cannot replace the new account', () async {
    final base = await buildDemoRuntime();
    final auth = _CountingAuthPort();
    final cards = _DelayedCachedCardRepository();
    final runtime = AppRuntime(
      environment: base.environment,
      capabilities: base.capabilities,
      auth: auth,
      cards: cards,
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
      disposeRuntime: () async {
        await auth.dispose();
        await base.dispose();
      },
    );
    final container = ProviderContainer(
      overrides: [appRuntimeProvider.overrideWithValue(runtime)],
    );
    addTearDown(() async {
      container.dispose();
      await runtime.dispose();
    });

    await container.read(authControllerProvider.future);
    await Future<void>.delayed(Duration.zero);
    expect((await container.read(cardControllerProvider.future))!.id, 'CARD-A');

    cards.subject = 'B';
    auth.switchSubject('subject-b');
    await Future<void>.delayed(Duration.zero);

    expect((await container.read(cardControllerProvider.future))!.id, 'CARD-B');
    cards.oldRefresh.complete(
      const CampusCard(
        id: 'CARD-A',
        maskedNumber: '••••A',
        ownerName: 'Account A',
        balance: MoneyFen.zero,
        status: CampusCardStatus.normal,
        positionName: 'Student',
        offlineCodeAllowed: false,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(container.read(cardControllerProvider).valueOrNull!.id, 'CARD-B');
  });
}

final class _CountingAuthPort implements AuthPort {
  static const _authenticated = AuthSnapshot(
    state: AuthState.authenticated,
    session: AuthSession(subjectId: 'subject-a', orgId: '2'),
  );

  final _changes = StreamController<AuthSnapshot>.broadcast(sync: true);
  AuthSnapshot _snapshot = _authenticated;
  int localRestoreCalls = 0;
  int serverRestoreCalls = 0;

  @override
  Stream<AuthSnapshot> get changes => _changes.stream;

  @override
  Future<AuthSnapshot> restoreLocal() async {
    localRestoreCalls++;
    return _snapshot;
  }

  @override
  Future<AuthSnapshot> restore() async {
    serverRestoreCalls++;
    return _snapshot;
  }

  @override
  Future<AuthSnapshot> signIn(AuthCredential credential) async => _snapshot;

  @override
  Future<void> signOut() async {
    _snapshot = const AuthSnapshot(state: AuthState.signedOut);
    _changes.add(const AuthSnapshot(state: AuthState.signedOut));
  }

  void switchSubject(String subjectId) {
    _snapshot = AuthSnapshot(
      state: AuthState.authenticated,
      session: AuthSession(subjectId: subjectId, orgId: '2'),
    );
    _changes.add(_snapshot);
  }

  Future<void> dispose() => _changes.close();
}

final class _SubjectCardRepository implements CardRepository {
  String subject = 'A';
  int currentCardCalls = 0;

  @override
  Future<CampusCard?> currentCard() async {
    currentCardCalls++;
    return CampusCard(
      id: 'CARD-$subject',
      maskedNumber: '••••$subject',
      ownerName: 'Account $subject',
      balance: MoneyFen.zero,
      status: CampusCardStatus.normal,
      positionName: 'Student',
      offlineCodeAllowed: false,
    );
  }

  @override
  Future<UserProfile> profile() async => UserProfile(
        displayName: 'Account $subject',
        maskedCardNumber: '••••$subject',
        positionName: 'Student',
      );

  @override
  Future<BindCardResult> bind(BindCardCommand command) =>
      throw UnimplementedError();

  @override
  Future<void> unbind({required String cardPassword}) async {}
}

final class _DelayedCachedCardRepository extends _SubjectCardRepository
    implements CacheFirstCardRepository {
  final oldRefresh = Completer<CampusCard?>();

  @override
  Future<CampusCard?> readCachedCard() => super.currentCard();

  @override
  Future<CampusCard?> refreshCard() =>
      subject == 'A' ? oldRefresh.future : super.currentCard();
}
