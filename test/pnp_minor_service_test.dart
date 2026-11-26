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

const current =
    '<table><tr><th>课程 名称</th><th>审核 状态</th><th>姓名</th><th>备注</th></tr><tr><td>Data</td><td>通过</td><td>Private</td><td>忽略</td></tr></table>';
const program =
    '<table><tr><th>院系</th><th>辅修专业</th><th>计划人数</th></tr><tr><td>理学院</td><td>数学</td><td>15</td></tr></table>';
void main() {
  test('window stays unknown on an unfamiliar page and closed notices precede stale buttons', () {
    expect(PnpMinorService.parseWindow('欢迎来到 EAMS'), ApplicationWindow.unknown);
    expect(PnpMinorService.parseWindow('<button>申请P/NP</button>'), ApplicationWindow.open);
    expect(
      PnpMinorService.parseWindow('<a onclick="apply()">申请P/NP</a>'),
      ApplicationWindow.open,
    );
    expect(
      PnpMinorService.parseWindow('<a href="javascript:void(0)" onclick="apply()">提交</a>'),
      ApplicationWindow.open,
    );
    expect(
      PnpMinorService.parseWindow('<body><script>const msg = "未开放";</script><button>报名</button>'),
      ApplicationWindow.open,
    );
    expect(
      PnpMinorService.parseWindow('<div hidden><button>报名</button></div>'),
      ApplicationWindow.unknown,
    );
    expect(
      PnpMinorService.parseWindow('<div style="display: none"><button>报名</button></div>'),
      ApplicationWindow.unknown,
    );
    expect(
      PnpMinorService.parseWindow('尚未开放P/NP申请<button>申请P/NP</button>'),
      ApplicationWindow.closed,
    );
    expect(PnpMinorService.parseWindow('当前暂不开放辅修报名'), ApplicationWindow.closed);
    expect(PnpMinorService.parseWindow('不在申请时间内'), ApplicationWindow.closed);
    expect(PnpMinorService.parseWindow('<button disabled>报名</button>'), ApplicationWindow.unknown);
    expect(
      PnpMinorService.parseWindow('<button aria-disabled="true">报名</button>'),
      ApplicationWindow.unknown,
    );
    expect(PnpMinorService.parseRows(program).single.title, '数学');
    expect(PnpMinorService.parseRows(current).single.fields, {'审核状态': '通过'});
    expect(PnpMinorService.parseRows('未绑定辅修培养方案'), isEmpty);
    expect(() => PnpMinorService.parseRows('error'), throwsA(isA<CampusRequestException>()));
  });

  test('reads semester, history and minor sections, preserves window on error, clears cache',
      () async {
    var limited = false;
    var failMinorPlan = true;
    var minorShellMode = false;
    final f = CampusFixture('https://eams.shanghaitech.edu.cn', (r) {
      if (limited) return respond('请不要过快点击');
      if (r.headers['Cookie'] == 'SESSION=v0') return respond('<input name="execution">');
      final path = r.uri.path;
      if (path.endsWith('dataQuery.action')) return respond('<option value="7">Spring</option>');
      if (path.endsWith('myMinorPlan.action')) {
        return failMinorPlan ? respond('Not Found', status: 404) : respond('未绑定辅修培养方案');
      }
      if (path.endsWith('innerIndex.action')) {
        return respond(minorShellMode ? '$program<a onclick="bm()">报名</a>' : program);
      }
      if (path.contains('!')) return respond(current);
      if (path.endsWith('minorApply.action') && minorShellMode) {
        return respond('<div>辅修入口</div>');
      }
      return respond('尚未开放');
    });
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final auth = ValueNotifier(0), ids = ValueNotifier(0);
    final s = PnpMinorService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      storage,
      auth,
      ids,
    );
    addTearDown(s.dispose);
    await s.refresh(AcademicApplicationTab.pnp);
    expect(f.renewals, 1);
    expect(s.selected, '7');
    expect(s.sections['本学期申请']!.single.fields, {'审核状态': '通过'});
    expect(s.windows[AcademicApplicationTab.pnp], ApplicationWindow.closed);
    expect(f.requests.any((r) => r.uri.queryParameters['semesterId'] == '7'), isTrue);

    // Partial-section failure on minorPlan must not block other minor sections.
    await s.refresh(AcademicApplicationTab.minor);
    expect(s.sections['可报名专业']!.single.title, '数学');
    expect(s.sections['已退选']!.single.title, 'Data');
    expect(s.sectionErrors['辅修培养方案'], isNotNull);

    // Minor innerIndex refines unknown shell window to open.
    failMinorPlan = false;
    minorShellMode = true;
    await s.refresh(AcademicApplicationTab.minor);
    expect(s.windows[AcademicApplicationTab.minor], ApplicationWindow.open);
    expect(s.sections['辅修培养方案'], isEmpty);
    expect(s.sectionErrors, isEmpty);

    final offline = PnpMinorService(s.client, storage, auth, ids);
    addTearDown(offline.dispose);
    expect(offline.sections['我的辅修申请']!.single.title, 'Data');
    expect(offline.windows, isEmpty);

    // Failed refresh must preserve previously known windows[tab].
    limited = true;
    await expectLater(s.refresh(AcademicApplicationTab.pnp), fails(CampusErrorKind.rateLimited));
    expect(s.windows[AcademicApplicationTab.pnp], ApplicationWindow.closed);

    await storage.clearCampusCaches();
    expect(storage.pnpMinorHistory('["user","bound"]'), isNull);

    await s.storage.savePnpMinorHistory('["user","bound"]', '{}');
    f.identity = (user: 'second', ids: 'other');
    ids.value++;
    expect(s.sections, isEmpty);
    expect(storage.pnpMinorHistory('["user","bound"]'), isNull);
  });

  testWidgets('PnpMinorPage shows fallback EAMS button when unknown and hides when closed',
      (tester) async {
    var closed = false;
    final f = CampusFixture(
      'https://eams.shanghaitech.edu.cn',
      (r) => respond(closed ? '<div>尚未开放</div>' : '<div>暂无记录</div>'),
    );
    SharedPreferences.setMockInitialValues({});
    final storage = StorageService(await SharedPreferences.getInstance());
    final auth = ValueNotifier(0), ids = ValueNotifier(0);
    final s = PnpMinorService(
      EamsClient(f.session, minInterval: Duration.zero, retryDelay: Duration.zero),
      storage,
      auth,
      ids,
    );
    addTearDown(s.dispose);

    await tester.pumpWidget(MaterialApp(home: PnpMinorPage(service: s)));
    await tester.pumpAndSettle();
    expect(s.windows[AcademicApplicationTab.pnp], ApplicationWindow.unknown);
    expect(find.text('前往 EAMS 查看或办理'), findsOneWidget);

    closed = true;
    await tester.tap(find.byTooltip('刷新'));
    await tester.pumpAndSettle();
    expect(s.windows[AcademicApplicationTab.pnp], ApplicationWindow.closed);
    expect(find.text('前往 EAMS 查看或办理'), findsNothing);
    expect(find.text('前往 EAMS 办理 P/NP'), findsNothing);
  });
}
