import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/main.dart';
import 'package:techpie/models/feature.dart';
import 'package:techpie/models/third_party_account.dart';
import 'package:techpie/models/user_session.dart';
import 'package:techpie/pages/grades_page.dart';
import 'package:techpie/pages/schedule_page.dart';
import 'package:techpie/services/assignment_service.dart';
import 'package:techpie/services/auth_service.dart';
import 'package:techpie/services/campus_card_service.dart';
import 'package:techpie/services/debug_logger.dart';
import 'package:techpie/services/ecard_bind_service.dart';
import 'package:techpie/services/egate_app_service.dart';
import 'package:techpie/services/http_client.dart';
import 'package:techpie/services/oa_gym_service.dart';
import 'package:techpie/services/schedule_service.dart';
import 'package:techpie/services/spotlight_service.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/sync_service.dart';
import 'package:techpie/services/theme_service.dart';
import 'package:techpie/services/third_party_auth_service.dart';
import 'package:techpie/services/uni_auth_service.dart';
import 'package:techpie/services/update_service.dart';
import 'package:techpie/theme/tp_icons.dart';
import 'package:techpie/widgets/app_shell/app_shell.dart';
import 'package:techpie/widgets/app_shell/desktop/desktop_command_palette.dart';

class _SignedInAuth extends AuthService {
  _SignedInAuth(super.storage, super.http, super.uniAuth);

  @override
  bool get isLoggedIn => true;

  @override
  UserSession? get session => UserSession(
        userId: '20260001',
        userName: '测试用户',
        schoolName: 'ShanghaiTech',
        createdAt: DateTime(2026, 1, 1),
      );
}

class _BoundThirdParty extends ThirdPartyAuthService {
  _BoundThirdParty(super.storage, super.http);

  static final ThirdPartyAccount _ids = ThirdPartyAccount(
    platform: ThirdPartyPlatform.ids,
    account: '20260001',
    sid: '20260001',
    name: '测试用户',
    email: 'test@example.edu.cn',
    token: 'mock-token',
    boundAt: DateTime(2026, 1, 1),
  );

  @override
  bool get hasIdsBinding => true;

  @override
  ThirdPartyAccount? get idsAccount => _ids;

  @override
  List<ThirdPartyPlatform> get boundPlatforms => const [ThirdPartyPlatform.ids];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    appShellPendingCommandId.value = null;
  });

  group('SpotlightService', () {
    test('serializeCommands filters blanks, deduplicates IDs, and trims fields',
        () {
      final serialized = SpotlightService.serializeCommands([
        DesktopCommandItem(
          id: ' tab.home ',
          title: ' 首页 ',
          subtitle: ' 今日课程 ',
          group: ' 导航 ',
          icon: TpIcons.home,
          keywords: const [' home ', '', 'shou ye'],
          onExecute: () {},
        ),
        DesktopCommandItem(
          id: 'tab.home',
          title: '重复项',
          group: '导航',
          icon: TpIcons.home,
          onExecute: () {},
        ),
        DesktopCommandItem(
          id: '',
          title: '空 ID',
          group: '导航',
          icon: TpIcons.home,
          onExecute: () {},
        ),
      ]);

      expect(serialized, hasLength(1));
      expect(serialized.first, {
        'id': 'tab.home',
        'title': '首页',
        'subtitle': '今日课程',
        'group': '导航',
        'aliases': const <String>[],
        'keywords': ['home', 'shou ye', 'shouye'],
        'rankingHint': 85,
      });
    });

    test('rankingHint prioritizes schedule, deadlines, and ELRC', () {
      expect(SpotlightService.rankingHintFor('tab.schedule'), 100);
      expect(SpotlightService.rankingHintFor('tab.deadlines'), 100);
      expect(SpotlightService.rankingHintFor('feature.elrc_recordings'), 100);
      expect(SpotlightService.rankingHintFor('tab.home'), 85);
      expect(SpotlightService.rankingHintFor('feature.grades'), 80);
      expect(SpotlightService.rankingHintFor('action.refresh'), 50);
    });

    test('donateCommandUsage sends serialized item with aliases and rankingHint',
        () async {
      const channel = MethodChannel('techpie/spotlight_donate_test');
      Map<Object?, Object?>? donated;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'donateUsage') {
          donated = call.arguments as Map<Object?, Object?>;
          return true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = SpotlightService(channel: channel, enabled: true);
      await service.donateCommandUsage(
        DesktopCommandItem(
          id: 'tab.schedule',
          title: '课表',
          subtitle: '查看周课表与课程详情',
          group: '导航',
          icon: TpIcons.schedule,
          aliases: const ['cls'],
          keywords: const ['schedule', 'ke biao'],
          onExecute: () {},
        ),
      );

      expect(donated, isNotNull);
      expect(donated!['id'], 'tab.schedule');
      expect(donated!['aliases'], ['cls']);
      expect(donated!['rankingHint'], 100);
      expect(donated!['keywords'], containsAll(['cls', 'ke biao', 'kebiao']));
      service.dispose();
    });

    test('DesktopCommandItem matches Chinese IME spaced and apostrophe pinyin',
        () {
      final scheduleItem = DesktopCommandItem(
        id: 'tab.schedule',
        title: '课表',
        subtitle: '查看周课表与课程详情',
        group: '导航',
        icon: TpIcons.schedule,
        aliases: const ['cls'],
        keywords: const ['schedule', 'ke biao', 'timetable'],
        onExecute: () {},
      );

      expect(scheduleItem.matches('ke biao'), isTrue);
      expect(scheduleItem.matches("ke'biao"), isTrue);
      expect(scheduleItem.matches('kebiao'), isTrue);
      expect(scheduleItem.matches('cls'), isTrue);
    });

    test('syncCommands deduplicates identical payloads and retries on failure',
        () async {
      const channel = MethodChannel('techpie/spotlight_sync_test');
      var syncCalls = 0;
      var failOnce = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'syncItems') {
          syncCalls++;
          if (failOnce) {
            failOnce = false;
            throw PlatformException(code: 'INDEX_ERR');
          }
          return true;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final service = SpotlightService(channel: channel, enabled: true);
      final items = [
        DesktopCommandItem(
          id: 'tab.schedule',
          title: '课表',
          subtitle: '查看周课表',
          group: '导航',
          icon: TpIcons.schedule,
          keywords: const ['schedule'],
          onExecute: () {},
        ),
      ];

      // First attempt fails -> digest reset so next sync retries.
      await service.syncCommands(items);
      expect(syncCalls, 1);

      // Second attempt succeeds.
      await service.syncCommands(items);
      expect(syncCalls, 2);

      // Identical payload is skipped.
      await service.syncCommands(items);
      expect(syncCalls, 2);

      service.dispose();
    });

    test('consumes pending cold-start command and handles warm-start openCommand',
        () async {
      const channel = MethodChannel('techpie/spotlight_dispatch_test');
      var ackCount = 0;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'consumePendingCommand':
            return 'feature.grades';
          case 'acknowledgePendingCommand':
            ackCount++;
            return null;
          default:
            return null;
        }
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final received = <String>[];
      final service = SpotlightService(channel: channel, enabled: true);
      service.initialize(onOpenCommand: received.add);
      await Future<void>.delayed(Duration.zero);

      expect(received, ['feature.grades']);
      expect(ackCount, 1);

      // Simulate native warm-start callback from SpotlightBridge.
      final codec = const StandardMethodCodec();
      final message =
          codec.encodeMethodCall(const MethodCall('openCommand', 'tab.schedule'));
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(channel.name, message, (_) {});

      expect(received, ['feature.grades', 'tab.schedule']);
      expect(ackCount, 2);

      service.dispose();
    });
  });

  group('AppShell Spotlight mirroring', () {
    testWidgets(
      'mirrors command palette items into Spotlight and executes Spotlight commands',
      (tester) async {
        const channel = MethodChannel('techpie/spotlight_shell_test');
        List<Map<Object?, Object?>>? syncedPayload;
        var acks = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          switch (call.method) {
            case 'syncItems':
              syncedPayload =
                  (call.arguments as List).cast<Map<Object?, Object?>>();
              return true;
            case 'consumePendingCommand':
              return null;
            case 'acknowledgePendingCommand':
              acks++;
              return null;
            default:
              return null;
          }
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });

        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        SharedPreferences.setMockInitialValues({'privacy_accepted_v1': true});
        final storage = StorageService(await SharedPreferences.getInstance());
        final logger = DebugLogger();
        final http = LoggingHttpClient(logger);
        addTearDown(http.close);
        final uniAuth = UniAuthService();
        final auth = _SignedInAuth(storage, http, uniAuth);
        final tpAuth = _BoundThirdParty(storage, http);
        final schedule = ScheduleService(storage, http, auth, tpAuth);
        await schedule.loadCachedData();
        final assignments =
            AssignmentService(storage, http, auth, tpAuth, schedule)
              ..loadCached();
        final campusCard = CampusCardService();
        final spotlight = SpotlightService(channel: channel, enabled: true)
          ..initialize();

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
            campusCardService: campusCard,
            ecardBindService: EcardBindService(),
            spotlightService: spotlight,
          ),
        );
        await tester.pumpAndSettle();
        await spotlight.flush();

        // Verify command palette items (tabs, campus features, actions) were synced.
        expect(syncedPayload, isNotNull);
        final byId = {
          for (final item in syncedPayload!) item['id'] as String: item,
        };
        expect(
          byId.keys,
          containsAll([
            'tab.home',
            'tab.schedule',
            'tab.deadlines',
            'action.refresh',
          ]),
        );
        expect(
          (byId['tab.schedule']!['keywords'] as List),
          contains('cls'),
        );
        expect(
          (byId['tab.deadlines']!['keywords'] as List),
          contains('ddl'),
        );
        for (final feature in featureEntries) {
          expect(byId.keys, contains('feature.${feature.id}'));
        }

        // Simulate Spotlight opening the Schedule tab.
        const codec = StandardMethodCodec();
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(const MethodCall('openCommand', 'tab.schedule')),
          (_) {},
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(SchedulePage), findsOneWidget);
        expect(acks, 1);

        // Simulate Spotlight opening the Grades campus service.
        await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
          channel.name,
          codec.encodeMethodCall(
            const MethodCall('openCommand', 'feature.grades'),
          ),
          (_) {},
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.byType(GradesPage), findsOneWidget);
        expect(acks, 2);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.macOS),
    );
  });
}
