import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus/campus_clients.dart';
import 'package:techpie/services/campus/campus_file_share.dart';
import 'package:techpie/services/campus/campus_file_share_io.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/service_provider.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_allowance_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/widgets/egate_visit.dart';

class _TestAuthService extends AuthService {
  _TestAuthService(super.storage, super.http, super.uniAuth);

  UserSession? testSession;

  @override
  UserSession? get session => testSession;

  @override
  bool get isLoggedIn => testSession != null;

  void setTestSession(UserSession? next) {
    testSession = next;
    notifyListeners();
  }
}

class _TestTpAuthService extends ThirdPartyAuthService {
  _TestTpAuthService(super.storage, super.http);

  ThirdPartyAccount? testIds;

  @override
  ThirdPartyAccount? get idsAccount => testIds;

  @override
  bool get hasIdsBinding => testIds != null;

  @override
  String get idsStudentId => testIds?.idsStudentId ?? '';

  void setTestIds(ThirdPartyAccount? next) {
    testIds = next;
    notifyListeners();
  }
}

UserSession _fakeUser(String id) => UserSession(
      userId: id,
      userName: 'Tester $id',
      schoolName: '上海科技大学',
      createdAt: DateTime.utc(2026),
    );

ThirdPartyAccount _fakeIds(String account) => ThirdPartyAccount(
      platform: ThirdPartyPlatform.ids,
      account: account,
      token: '',
      raw: const {'authMethod': 'passkey', 'tgc': 'tgc', 'uid': '20260001'},
      boundAt: DateTime.utc(2026),
    );

void main() {
  test('CampusFileShare sanitizes scope/filenames and manages temp files', () async {
    final tempDir = await Directory.systemTemp.createTemp('campus_file_share_test_');
    debugTempDirectoryOverride = () async => tempDir;
    addTearDown(() async {
      debugTempDirectoryOverride = null;
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    expect(CampusFileShare.normalizeScope('Transcript'), 'transcript');
    expect(() => CampusFileShare.normalizeScope('../escape'), throwsArgumentError);
    expect(CampusFileShare.sanitizeFilename('../../.secret?.pdf'), 'secret_.pdf');
    expect(CampusFileShare.sanitizeFilename('...'), 'file.bin');

    const channel = MethodChannel('techpie/platform');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    MethodCall? captured;
    messenger.setMockMethodCallHandler(channel, (call) async {
      captured = call;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));

    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    final res = await CampusFileShare.openOrShare(
      scope: 'certificates',
      filename: '../my report.pdf',
      bytes: [1, 2, 3],
      mimeType: 'application/pdf',
      preferShare: true,
    );
    expect(res.status, CampusFileOpenStatus.shared);
    expect(captured?.method, 'shareFile');
    expect(captured?.arguments, {
      'scope': 'certificates',
      'filename': 'my report.pdf',
      'mimeType': 'application/pdf',
    });
    expect(File(res.path!).existsSync(), isTrue);

    await CampusFileShare.clearScopedFiles(scope: 'certificates');
    expect(File(res.path!).existsSync(), isFalse);
  });

  testWidgets('EgateVisit keeps subtree mounted over pushed routes and resets on account change', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final http = LoggingHttpClient(DebugLogger());
    final auth = _TestAuthService(storage, http, UniAuthService())..testSession = _fakeUser('u1');
    final tpAuth = _TestTpAuthService(storage, http)..testIds = _fakeIds('20260001');
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
    final clients = CampusClients(auth, tpAuth);
    addTearDown(clients.dispose);

    final navKey = GlobalKey<NavigatorState>();
    var mountCount = 0;
    await tester.pumpWidget(
      ServiceProvider(
        authService: auth,
        debugLogger: DebugLogger(),
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: OaGymService(auth, storage, tpAuth),
        egateAppService: EgateAppService(auth, storage, tpAuth),
        studentAllowanceService: StudentAllowanceService(auth, tpAuth),
        uniAuthService: UniAuthService(),
        syncService: SyncService(auth, tpAuth, storage),
        updateService: UpdateService(),
        campusClients: clients,
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
        child: MaterialApp(
          navigatorKey: navKey,
          home: EgateVisit(
            title: 'Test Visit',
            builder: (_, student) {
              mountCount++;
              return Scaffold(body: Text('student:$student'));
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('student:20260001'), findsOneWidget);
    final initialMounts = mountCount;

    // Pushing a second route must not collapse the underlying EgateVisit to SizedBox.shrink().
    unawaited(
      navKey.currentState!.push<void>(
        MaterialPageRoute(builder: (_) => const Scaffold(body: Text('Dialog Route'))),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Dialog Route'), findsOneWidget);
    expect(find.text('student:20260001', skipOffstage: false), findsOneWidget);

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(mountCount, initialMounts);

    // Changing IDS binding shows the new student or prompts when unbound.
    tpAuth.setTestIds(null);
    await tester.pump();
    expect(find.text('绑定 IDS 账号'), findsOneWidget);
  });

  testWidgets('TechPieApp does not dispose caller-owned campusClients', (tester) async {
    SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
    final storage = StorageService(await SharedPreferences.getInstance());
    final logger = DebugLogger();
    final http = LoggingHttpClient(logger);
    final uniAuth = UniAuthService();
    final auth = _TestAuthService(storage, http, uniAuth);
    final tpAuth = _TestTpAuthService(storage, http);
    final schedule = ScheduleService(storage, http, auth, tpAuth);
    final assignments = AssignmentService(storage, http, auth, tpAuth, schedule);
    var accountChanges = 0;
    final externalClients = CampusClients(
      auth,
      tpAuth,
      onAccountChanged: () => accountChanges++,
    );
    addTearDown(externalClients.dispose);

    await tester.pumpWidget(
      TechPieApp(
        authService: auth,
        debugLogger: logger,
        storageService: storage,
        themeService: ThemeService(storage),
        scheduleService: schedule,
        assignmentService: assignments,
        thirdPartyAuthService: tpAuth,
        oaGymService: OaGymService(auth, storage, tpAuth),
        egateAppService: EgateAppService(auth, storage, tpAuth),
        uniAuthService: uniAuth,
        syncService: SyncService(auth, tpAuth, storage),
        updateService: UpdateService(),
        campusClients: externalClients,
        campusCardService: CampusCardService(),
        ecardBindService: EcardBindService(),
      ),
    );
    await tester.pump();

    // Unmounting TechPieApp must keep externalClients' listeners intact.
    await tester.pumpWidget(const SizedBox.shrink());
    auth.setTestSession(_fakeUser('u2'));
    expect(accountChanges, 1);
  });
}
