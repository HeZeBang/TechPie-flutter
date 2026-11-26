import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/student_leave_application.dart';
import 'package:techpie/pages/student_leave_page.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_leave_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  testWidgets('the application selector replaces the type and date when the property changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
      final action = request.uri.pathSegments.last;
      return switch (action) {
        'getStudentAppliedDays.do' => respond({
            'datas': [
              {'YQJTS': 0},
            ],
          }),
        'checkWhetherStudentCanApply.do' => respond({
            'datas': [
              {'applicable': true},
            ],
          }),
        'getDictionaryOfLeaveProperty.do' => respond({
            'datas': [
              [
                {'leavePropertyId': 'N', 'leaveProperty': '请假'},
                {'leavePropertyId': 'R', 'leaveProperty': '补假'},
              ]
            ],
          }),
        'getLeaveType.do' => respond({
            'data': [
              {'LXDM': 'A', 'LXMC': '事假', 'YL2': '0'},
            ],
          }),
        _ => respond({}),
      };
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              StudentLeaveApplication(service: service, schoolFormButton: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('请假申请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('请假性质'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('请假').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('请假类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('事假').last);
    await tester.pumpAndSettle();
    expect(find.text('选择请假日期'), findsOneWidget);
    await tester.tap(find.text('请假').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('补假').last);
    await tester.pumpAndSettle();
    expect(find.text('选择请假日期'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    account.dispose();
  });

  testWidgets('leave history opens the selected application and drops the detail on sign-out',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
      if (request.uri.path.contains('getAppConfig')) return respond({});
      final model = request.uri.pathSegments.last.split('.').first;
      if (model == 'getDefaultRole') return respond({});
      if (model == 'getStudentAppliedDays') {
        return respond({
          'datas': [
            {'YQJTS': 3},
          ],
        });
      }
      if (model == 'checkWhetherStudentCanApply') {
        return respond({
          'datas': [
            {'applicable': false, 'reason': '已有申请在审批中'},
          ],
        });
      }
      if (model == 'getDictionaryOfLeaveProperty') {
        return respond({
          'datas': [<Object>[]],
        });
      }
      if (model == 'getStudentLeaveRecords') {
        return respond({
          'datas': [
            [
              {
                'leaveId': 'mobile+approval/2',
                'leaveType': '其他假期',
                'leaveProperty': '补假',
                'leaveDays': '2026-11-21 至 2026-11-23',
              }
            ]
          ],
        });
      }
      if (model == 'getStudentLeaveRecordDetails') {
        expect(request.uri.queryParameters['leaveId'], 'mobile+approval/2');
        return respond({
          'datas': [
            {
              'leaveInfo': {
                'auditStateDisplay': '已审核',
                'SHYJ': '审批意见示例',
                'leaveReason': '事由示例',
              },
            }
          ],
        });
      }
      final record = switch (model) {
        'wdqjbg' => {'SQBH': 'record-2', 'QJLX_DISPLAY': '事假', 'SHZT_DISPALY': '待审'},
        'qjxqbd' => {'SQBH': 'record-2', 'QJSY': '测试详情'},
        _ => throw StateError(model),
      };
      return respond({
        'code': 0,
        'datas': {
          model: {
            'rows': [record],
            'totalSize': 1,
          },
        },
      });
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
    await tester.pumpWidget(MaterialApp(home: StudentLeavePage(service: service)));
    await tester.pumpAndSettle();
    expect(find.text('请假申请'), findsOneWidget);
    expect(find.text('待审'), findsOneWidget);
    await tester.tap(find.text('事假'));
    await tester.pumpAndSettle();
    expect(find.text('测试详情'), findsOneWidget);
    await tester.tap(find.text('请假申请'));
    await tester.pumpAndSettle();
    expect(find.text('本学期已请假 3 天'), findsOneWidget);
    expect(find.text('已有申请在审批中'), findsOneWidget);
    expect(find.text('选择请假日期'), findsNothing);
    expect(fixture.requests.where((r) => r.uri.path.contains('saveStudentLeaveRecord')), isEmpty);
    await tester.ensureVisible(find.text('学校审批意见'));
    await tester.tap(find.text('学校审批意见'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('补假 · 其他假期'));
    await tester.tap(find.text('补假 · 其他假期'));
    await tester.pumpAndSettle();
    expect(find.text('审批意见示例'), findsOneWidget);
    expect(storage.readEmapCache('student_leave'), isNot(contains('审批意见示例')));
    fixture.identity = (user: null, ids: null);
    account.value++;
    await tester.pumpAndSettle();
    expect(find.text('登录 TechPie'), findsOneWidget);
    expect(find.text('测试详情'), findsNothing);
    expect(find.text('已有申请在审批中'), findsNothing);
    expect(find.text('审批意见示例'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    account.dispose();
  });
}
