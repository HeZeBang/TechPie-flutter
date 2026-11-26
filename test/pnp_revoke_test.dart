import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:techpie/models/pnp_and_minor.dart';
import 'package:techpie/pages/pnp_minor_page.dart';
import 'package:techpie/services/campus/campus_errors.dart';
import 'package:techpie/services/campus/eams_client.dart';
import 'package:techpie/services/pnp_minor_service.dart';
import 'package:techpie/services/storage_service.dart';

import 'campus/campus_fixture.dart';

const action = '<script>bar.addItem("撤销申请","revoke()");</script>';
const handler = '<script>function revoke(){}</script>';
const form = '<form name="semesterForm" method="post"><input name="semester.id" value="7"></form>'
    '<form method="post" name="stdAppliesForm" action="/eams/pnp/std-pnp-apply!myApplies.action"></form>';
const box = '<input type="checkbox" name="pnpApply.id" value="row-id">';
const rows = '<table><tr><th></th><th>课程名称</th><th>申请状态</th></tr>'
    '<tr><td>$box</td><td>课程甲</td><td>待审核</td></tr></table>';
const page = '$form$action$handler$rows';

Future<PnpMinorService> makeService(CampusFixture fixture, ValueNotifier<int> identity) async {
  SharedPreferences.setMockInitialValues({});
  final service = PnpMinorService(
    EamsClient(fixture.session, minInterval: Duration.zero, retryDelay: Duration.zero),
    StorageService(await SharedPreferences.getInstance()),
    ValueNotifier(0),
    identity,
  );
  addTearDown(service.dispose);
  return service;
}

void main() {
  test('only an offered action and an enabled school row are revocable', () {
    for (final input in [
      rows,
      '$form$handler$rows',
      page.replaceFirst('name="stdAppliesForm"', 'name="anotherForm"'),
      page.replaceFirst('bar.addItem', '// bar.addItem'),
      page
          .replaceFirst('bar.addItem', '/*\nbar.addItem')
          .replaceFirst(';</script>', ';\n*/</script>'),
      page.replaceFirst('<td>$box', '<td style="display:none">$box'),
      page.replaceFirst('type="checkbox"', 'disabled type="checkbox"'),
      page.replaceFirst('value="row-id"', 'value="first,second"'),
    ]) {
      final eligible = <AcademicApplicationRow, String>{};
      expect(PnpMinorService.parseRows(input, revokeIds: eligible), hasLength(1));
      expect(eligible, isEmpty);
    }
    final eligible = <AcademicApplicationRow, String>{};
    PnpMinorService.parseRows(page, revokeIds: eligible);
    expect(eligible.values, ['row-id']);
    expect(eligible.keys.single.toJson().toString(), isNot(contains('row-id')));
  });

  test('rechecks the selected row before writing and discards stale account handles', () async {
    var current = page;
    final identity = ValueNotifier(0);
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path.endsWith('dataQuery.action')) return respond('<option value="7">春季</option>');
      if (r.uri.path.endsWith('!myApplies.action')) {
        expect(r.uri.queryParameters['semesterId'], '7');
        return respond(current);
      }
      if (r.uri.path.endsWith('!revoke.action')) fail('unexpected write');
      return respond('暂无记录');
    });
    final s = await makeService(f, identity);
    await s.refresh(AcademicApplicationTab.pnp);
    final row = s.sections['本学期申请']!.single;
    current = page.replaceFirst('type="checkbox"', 'disabled type="checkbox"');
    await expectLater(s.revoke(row), fails(CampusErrorKind.rejected));
    expect(s.canRevoke(row), isFalse);
    current = page;
    await s.refresh(AcademicApplicationTab.pnp);
    final other = s.sections['本学期申请']!.single;
    f.identity = (user: 'other', ids: 'another');
    identity.value++;
    await expectLater(s.revoke(other), fails(CampusErrorKind.rejected));
  });

  testWidgets(
      'cancel sends nothing, confirmation posts once, and records refresh on uncertain receipt',
      (tester) async {
    var writes = 0, currentReads = 0;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (r.uri.path.endsWith('dataQuery.action')) return respond('<option value="7">春季</option>');
      if (r.uri.path.endsWith('!myApplies.action')) {
        currentReads++;
        return respond(writes == 0 ? page : '暂无记录');
      }
      if (r.uri.path.endsWith('!revoke.action')) {
        expect(r.method, 'POST');
        expect(r.data, {'applyId': 'row-id'});
        writes++;
        return respond('', status: 503);
      }
      if (r.uri.path.endsWith('!historyList.action')) return respond(page);
      return respond('尚未开放P/NP申请');
    });
    final s = await makeService(f, ValueNotifier(0));
    await tester.pumpWidget(MaterialApp(home: PnpMinorPage(service: s)));
    await tester.pumpAndSettle();
    final button = find.text('撤销申请');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('课程甲', findRichText: true), findsWidgets);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(writes, 0);
    expect(currentReads, 1);
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认撤销'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(currentReads, 3);
    expect(s.sections['本学期申请'], isEmpty);
    expect(button, findsNothing);
    expect(find.textContaining('无法确认撤销结果'), findsOneWidget);
  });
}
