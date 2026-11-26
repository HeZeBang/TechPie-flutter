import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:techpie/models/campus_job.dart';
import 'package:techpie/pages/campus_jobs_page.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/campus_job_service.dart';

import 'campus/campus_fixture.dart';

const student = '20240000';
const privateAmount = '1837.42';
const origin = 'https://egate.shanghaitech.edu.cn';

CampusFixture fixture({
  Set<String> rejectModels = const {},
  void Function(String path, dynamic data)? onPost,
}) =>
    CampusFixture(origin, (r) {
      final path = r.uri.path;
      if (path.contains('/getAppConfig/')) return respond({});
      onPost?.call(path, r.data);
      if (path.endsWith('/T_ZJGL_SQXX_SAVE.do') ||
          path.endsWith('/StuSqSentMassage.do') ||
          path.endsWith('/xzxssgdz.do') ||
          path.endsWith('/GwsqSentMassage.do')) {
        return respond({'code': '0', 'returnCode': '#E000000000000'});
      }
      if (path.contains('/commoncall/callBatch/')) {
        return respond({'resultCode': '00000'});
      }
      final model = r.uri.pathSegments.last.split('.').first;
      if (rejectModels.contains(model)) {
        return respond({'code': '-1', 'msg': 'rejected'});
      }
      final assistant = path.contains('/zjglapp_shanghaitech/');
      final name = assistant ? '程序设计助教' : '图书馆助理';
      final form = r.data as Map;
      if (!['ksqdgwcx', 'gwxqtable'].contains(model)) expect(form['XSBH'], student);
      final rows = switch (model) {
        'ksqdgwcx' => [
            {
              'GWMC': name,
              'GWDM': 'job',
              'DWDM': 'unit-1',
              'XN': '2026-2027',
              'XQ': '1',
              'WID': 'id',
            },
          ],
        'gwxqtable' => [
            {'GWMC': name, 'WID': 'other', 'XQRS': 8},
            {'GWMC': name, 'WID': 'id', 'XQRS': 3, 'YL5': '600'},
          ],
        'cxsgsqxx' => [
            {'XSBH': 'other', 'SQBH': 'other-record'},
            {'XSBH': student, 'SQBH': 'mine', 'SQRQ': '2026-01-03', 'SHZT_DISPLAY': '审核中'},
          ],
        'cxgwxx' => [
            {'DWDM_DISPLAY': '图书馆', 'GZKSRQ': '2026-01-01'},
          ],
        'tjje' => [
            {'JE': privateAmount},
          ],
        'xzmx' => [
            {'FFYF': '2026-01', 'SFJE': privateAmount, 'GS': 16, 'BCBZ': 22},
          ],
        _ => throw StateError('unexpected action $model'),
      };
      return respond({
        'code': 0,
        'datas': {
          model: {'rows': rows, 'totalSize': rows.length},
        },
      });
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('each program uses its own catalog, matched details and personal query', () async {
    final f = fixture();
    final service = CampusJobService(EmapClient(f.session), student);
    for (final program in CampusJobProgram.values) {
      final job = (await service.openings(program)).single;
      expect(job.name, program == CampusJobProgram.workStudy ? '图书馆助理' : '程序设计助教');
      final detail = await service.detail(program, job);
      expect(detail?.headcount, '3');
      expect(
        await service.detail(program, CampusJobOpening.fromJson({'WID': 'unmatched'})),
        isNull,
      );
      final record = (await service.applications(program)).single;
      expect(record.reference, 'mine');
      expect(record.status, '审核中');
      expect(
        f.requests.any((r) => r.uri.path.endsWith('${program.app}-${program.appId}.do')),
        isTrue,
      );
    }
    f.identity = (user: 'new', ids: 'other');
    await expectLater(
      service.applications(CampusJobProgram.workStudy),
      fails(CampusErrorKind.sessionExpired),
    );
    final noStudent = CampusJobService(EmapClient(f.session), '');
    final before = f.requests.length;
    await expectLater(
      noStudent.applications(CampusJobProgram.teachingAssistant),
      fails(CampusErrorKind.idsNotBound),
    );
    expect(f.requests.length, before);
  });

  test('pay is held by the caller, with no preferences or printed amounts', () async {
    const disk = MethodChannel('plugins.flutter.io/shared_preferences');
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(disk, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(disk, null));
    final logs = <String>[];
    await runZoned(
      () async {
        final f = fixture();
        final service = CampusJobService(EmapClient(f.session), student);
        final data = await service.employment();
        expect(data.total, privateAmount);
        expect(data.payments.single.hours, '16');
        expect(data.positions.single.unit, '图书馆');
        service.dispose();
        await expectLater(
          service.applications(CampusJobProgram.workStudy),
          fails(CampusErrorKind.sessionExpired),
        );
      },
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)),
    );
    expect(calls, isEmpty);
    expect(logs.join(), isNot(contains(privateAmount)));
  });

  test('employment isolates partial section failure while rethrowing auth expiry', () async {
    final f = fixture(rejectModels: const {'xzmx'});
    final service = CampusJobService(EmapClient(f.session), student);
    final partial = await service.employment();
    expect(partial.positions, hasLength(1));
    expect(partial.total, privateAmount);
    expect(partial.payments, isEmpty);
    expect(partial.positionsError, isNull);
    expect(partial.totalError, isNull);
    expect(partial.paymentsError, isNotNull);

    f.identity = (user: 'other', ids: 'other');
    await expectLater(service.employment(), fails(CampusErrorKind.sessionExpired));
    service.dispose();
  });

  test('validates TA 20-char rule, submits TA and work-study applications with no leaks', () async {
    const disk = MethodChannel('plugins.flutter.io/shared_preferences');
    final diskCalls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(disk, (call) async {
      diskCalls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(disk, null));

    final calls = <(String, Map<String, dynamic>)>[];
    final f = fixture(
      onPost: (path, data) {
        if (data is Map) {
          calls.add((path, Map<String, dynamic>.from(data)));
        }
      },
    );
    final service = CampusJobService(EmapClient(f.session), student);
    final taJob = (await service.openings(CampusJobProgram.teachingAssistant)).single;
    final wsJob = (await service.openings(CampusJobProgram.workStudy)).single;
    final beforeShort = f.requests.length;

    await expectLater(
      service.applyTeachingAssistant(job: taJob, reason: '不足二十字'),
      throwsFormatException,
    );
    expect(f.requests.length, beforeShort);

    const longReason = '熟悉数据结构与算法课程内容，能够认真批改实验报告并协助答疑。';
    const secretPhone = '13999998888';
    final logs = <String>[];
    await runZoned(
      () async {
        await service.applyTeachingAssistant(
          job: taJob,
          reason: longReason,
          intro: '成绩优异',
          date: '2026-09-01',
        );
        await service.applyWorkStudy(
          job: wsJob,
          reason: longReason,
          phone: secretPhone,
          acceptAdjustment: true,
          intro: '认真负责',
          date: '2026-09-01',
        );
      },
      zoneSpecification: ZoneSpecification(print: (self, parent, zone, line) => logs.add(line)),
    );

    final taSave = calls.firstWhere((e) => e.$1.endsWith('/T_ZJGL_SQXX_SAVE.do'));
    final taPayload =
        jsonDecode(taSave.$2['T_ZJGL_SQXX_SAVE'] as String) as Map<String, dynamic>;
    expect(taPayload['LGLBDM'], '0');
    expect(taPayload['XSBH'], student);
    expect(taPayload['SQLY'], longReason);
    expect(taPayload['BZ5'], 0);
    expect(calls.any((e) => e.$1.endsWith('/StuSqSentMassage.do')), isTrue);

    final wsBatch =
        calls.firstWhere((e) => e.$1.endsWith('/T_QGZX_SGSQSD-DATAMODEL-SAVE.do'));
    final wsRows = jsonDecode(wsBatch.$2['requestParams'] as String) as List<dynamic>;
    expect((wsRows.single as Map)['LXFS'], secretPhone);

    final wsForm = calls.firstWhere((e) => e.$1.endsWith('/xzxssgdz.do'));
    expect(
      wsForm.$2.keys,
      containsAll([
        '0da20ab7_bf71_43c9_a3f2_3ec9166bac84',
        '7222ea39_d3b5_4750_a9a8_b3c15c0aa09d',
      ]),
    );
    expect(calls.any((e) => e.$1.endsWith('/GwsqSentMassage.do')), isTrue);
    expect(diskCalls, isEmpty);
    expect(logs.join(), isNot(contains(secretPhone)));
    service.dispose();
  });

  testWidgets('narrow-screen sections and salary visibility follow current visit', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final f = fixture();
    await tester.pumpWidget(
      MaterialApp(home: CampusJobPanels(client: EmapClient(f.session), studentId: student)),
    );
    await tester.pumpAndSettle();
    expect(find.text('图书馆助理'), findsOneWidget);
    await tester.tap(find.text('图书馆助理'));
    await tester.pumpAndSettle();
    expect(find.textContaining('需求人数'), findsOneWidget);
    expect(find.text('申请岗位'), findsOneWidget);
    await tester.tap(find.text('在岗薪资'));
    await tester.pumpAndSettle();
    expect(find.textContaining(privateAmount), findsNothing);
    await tester.tap(find.byTooltip('显示金额'));
    await tester.pumpAndSettle();
    expect(find.text(privateAmount), findsOneWidget);
    await tester.tap(find.text('我的申请'));
    await tester.pumpAndSettle();
    expect(find.text('mine'), findsOneWidget);
    await tester.tap(find.text('在岗薪资'));
    await tester.pumpAndSettle();
    expect(find.textContaining(privateAmount), findsNothing);
    await tester.tap(find.text('助教岗位'));
    await tester.pumpAndSettle();
    expect(find.text('程序设计助教'), findsOneWidget);
    expect(find.text('在岗薪资'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TA application enforces 20-char rule and submits after confirmation dialog',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final saved = <Map<String, dynamic>>[];
    final f = fixture(
      onPost: (path, data) {
        if (path.endsWith('/T_ZJGL_SQXX_SAVE.do') && data is Map) {
          saved.add(jsonDecode(data['T_ZJGL_SQXX_SAVE'] as String) as Map<String, dynamic>);
        }
      },
    );
    await tester.pumpWidget(
      MaterialApp(home: CampusJobPanels(client: EmapClient(f.session), studentId: student)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('助教岗位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('程序设计助教'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('申请岗位'));
    await tester.pumpAndSettle();

    expect(find.textContaining('最多可申请 3 个助教岗位'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('job-apply-reason')), '太短');
    await tester.tap(find.text('提交申请'));
    await tester.pumpAndSettle();
    expect(find.text('申请理由不少于 20 字'), findsOneWidget);
    expect(saved, isEmpty);

    const validReason = '我已完成该课程并取得优秀成绩，有耐心且每周有充足时间参与助教工作。';
    await tester.enterText(find.byKey(const ValueKey('job-apply-reason')), validReason);
    await tester.tap(find.text('提交申请'));
    await tester.pumpAndSettle();
    expect(find.text('确认提交岗位申请？'), findsOneWidget);
    expect(saved, isEmpty);

    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(saved, hasLength(1));
    expect(saved.single['SQLY'], validReason);
    expect(find.text('mine'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
