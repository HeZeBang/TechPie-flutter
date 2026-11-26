import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/pages/student_leave_editor.dart';
import 'package:techpie/services/campus/emap_client.dart';
import 'package:techpie/services/storage_service.dart';
import 'package:techpie/services/student_leave_service.dart';

import 'campus/campus_fixture.dart';

void main() {
  testWidgets('review keeps the draft on cancel and commits the confirmed application once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final account = ValueNotifier(0);
    final requests = <String>[];
    final submitted = <Map<String, dynamic>>[];
    final fixture = CampusFixture('https://egate.shanghaitech.edu.cn', (request) {
      const success = '#E000000000000';
      final name = request.uri.pathSegments.last;
      requests.add(name);
      final action = name.split('.').first;
      if (action == 'addLeaveApply') {
        submitted
            .add(jsonDecode((request.data as Map)['INDATA'] as String) as Map<String, dynamic>);
      }
      if (action == 'qjsqbd_jbxx' || action == 'wdqjbg') {
        return respond({
          'code': '0',
          'datas': {
            action: {
              'rows': [
                if (action == 'qjsqbd_jbxx') {'XSBH': 'student'},
              ],
              'totalSize': action == 'qjsqbd_jbxx' ? 1 : 0,
            },
          },
        });
      }
      const exampleKind = [
        {'LXDM': 'kind', 'LXMC': '事假', 'YL2': '0', 'SFSCCL': '0'},
      ];
      return respond(
        switch (action) {
          'getStudentAppliedDays' => {
              'datas': [
                {'YQJTS': 0},
              ],
            },
          'checkWhetherStudentCanApply' => {
              'datas': [
                {'applicable': true},
              ],
            },
          'getDictionaryOfLeaveProperty' => {
              'datas': [
                [
                  {'leavePropertyId': 'property', 'leaveProperty': '请假'},
                ]
              ],
            },
          'getStuxslbdm' => {
              'returnCode': success,
              'data': {'XSLBDM': '3'},
            },
          'getLeaveType' => {'returnCode': success, 'data': exampleKind},
          'getStuKcmc' => {
              'returnCode': success,
              'data': {'KCMC': ''},
            },
          'getAppliedDays' => {
              'returnCode': success,
              'data': {'ZDQJTS': 30, 'KQJTS': 30},
            },
          'getCaseByType' => {
              'returnCode': success,
              'data': {'DMBH': 'route'},
            },
          'checkLeaveDate' => {
              'returnCode': success,
              'data': <String, String>{},
            },
          _ => {'returnCode': success},
        },
      );
    });
    final service = StudentLeaveService(EmapClient(fixture.session), storage, account);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              child: const Text('开始填写'),
              onPressed: () => openStudentLeaveEditor(
                context,
                service,
                initial: const {
                  'QJXZ': 'property',
                  'QJXZ_DISPLAY': '请假',
                  'QJLX': 'kind',
                  'QJLX_DISPLAY': '事假',
                  'QJKSRQ': '2030-04-08',
                  'QJJSRQ': '2030-04-09',
                  'DZ_QJQX': 'district',
                  'DZ_QJQX_DISPLAY': '示例市/示例区',
                  'DZ_XXDZ': '示例地址',
                  'YL1': '10000000001',
                  'YL2': 'student@example.org',
                  'YL3': '无',
                  'YL4': '测试联系人',
                  'YL5': '10000000002',
                  'YL6': '0',
                  'YL6_DISPLAY': '不涉及课程',
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始填写'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('QJSY')), '参加家庭活动');
    await tester.tap(find.text('提交请假申请'));
    await tester.pumpAndSettle();
    expect(find.text('提交请假申请？'), findsOneWidget);
    expect(find.textContaining('2 天'), findsWidgets);
    expect(submitted, isEmpty);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
    expect(find.text('参加家庭活动'), findsOneWidget);
    await tester.tap(find.text('提交请假申请'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认提交'));
    await tester.pumpAndSettle();
    expect(find.text('开始填写'), findsOneWidget);
    expect(submitted.single, containsPair('QJSY', '参加家庭活动'));
    expect(requests.indexOf('wdqjbg.do'), greaterThan(requests.indexOf('addLeaveApply.do')));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    account.dispose();
  });
}
